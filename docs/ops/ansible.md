# Operations: Ansible

Day-to-day Ansible operations for this `ansible` project. Reference material; for step-by-step procedures see the runbooks under `docs/runbooks/`.

**Related architecture:** [architecture.md § Ansible structure](../architecture.md#ansible-structure)

---

## Common run commands

All run from `playbooks/` directory:

```bash
cd ~/projects/ansible/playbooks
```

### Full provisioning

```bash
ansible-playbook site.yml --ask-vault-pass
```

Brings the Droplet to the desired state across every role (common, docker, traefik, all enabled sites).

### Single role

```bash
ansible-playbook site.yml --ask-vault-pass --tags traefik
```

Replace `traefik` with `common`, `docker`, `wordpress`, `laravel`, `webapp`, or `logging` to target one role's tasks.

### Dry run

```bash
ansible-playbook site.yml --ask-vault-pass --check --diff
```

Shows what *would* change without making changes. The `--diff` flag also shows file-level diffs for templated files. Tasks that render `vault_*` values have their diffs suppressed (`no_log: true`); the change-flag is still visible.

`--check` mode fidelity requires `community.docker` ≥ 3.10 — otherwise dry-run mode markers may be missing from output (KB lesson). Currently pinned to 5.2.0 in `requirements.yml`.

### Targeting one site

Pass `node_site_filter=<site_name>` (or the equivalent variable per role) to limit a tagged run to one site:

```bash
ansible-playbook site.yml --ask-vault-pass --tags wordpress --extra-vars "node_site_filter=taotedev"
```

(Confirm the actual filter variable name per role; the `webapp` role accepts `node_site_filter`. Other roles may have different names — check the role's `meta/argument_specs.yml`.)

### Capture a `--check` baseline

```bash
ansible-playbook site.yml --check --diff > ../.checks/baseline.log 2>&1
```

The `.checks/` directory is gitignored. Regenerate baselines at the start of any session that's about to apply changes; compare before/after to spot drift.

---

## Role loop pattern

Roles that run per-site (`wordpress`, `webapp`) are invoked as `include_role` inside a task-level loop in `site.yml`:

```yaml
- name: WordPress sites
  ansible.builtin.include_role:
    name: wordpress
    apply: { tags: [wordpress] }
  loop: "{{ wordpress_sites }}"
  loop_control:
    loop_var: item
    label: "{{ item.site_name }}"
  when: item.enabled | default(false)
```

Two non-obvious points:

- **`apply: { tags: [wordpress] }`** is required for `--tags wordpress` to execute the tasks *inside* the role. Without it, the include itself runs but the role tasks are skipped. This bit us before the refactor — it's why `site.yml` doesn't use the simpler `roles:` syntax.
- **`when: item.enabled`** lets a site sit in `wordpress_sites` while being skipped — the `enabled: false` toggle in the site var file. Required for parking a site without removing its var file.

Single-site roles (`common`, `docker`, `traefik`, `laravel`) don't loop; they're invoked once with their tag.

---

## Secrets pattern

All secrets live in `playbooks/group_vars/all/vault.yml`, encrypted with `ansible-vault`. See [ADR 0004](../adr/0004-ansible-vault-only-secret-store.md) for the decision rationale.

### Naming

Convention: `vault_<scope>_<purpose>`. Examples:

- `vault_dockerhub_username`, `vault_dockerhub_token` — Docker Hub auth.
- `vault_traefik_acme_email` — Let's Encrypt account.
- `vault_<site>_db_password` — per-site DB credential.

Legacy exception: `taotedev_db_password` (without prefix) — kept for backward compatibility, flagged for renaming on a future pass.

### Referencing in templates and var files

In non-vault files (vars.yml, site var files, role templates), reference vault values directly:

```yaml
wp_db_password: "{{ vault_<site>_db_password }}"
```

### `no_log: true` requirement

Per the Ansible coding-standards addendum §7/§8, **any task that renders or accepts a vault value must carry `no_log: true`.** This prevents leakage to stdout at `-v` and above. Currently enforced across:

- `playbooks/roles/wordpress/tasks/main.yml` — `.env` template task.
- `playbooks/roles/webapp/tasks/main.yml` — `.env` template task.
- `playbooks/roles/laravel/tasks/main.yml` — `.env` template task.
- `playbooks/roles/docker/tasks/main.yml` — Docker Hub login task.

If you add a new task that touches a vault value, add `no_log: true`. The lint check (CI) does not catch this automatically; review during PR.

### Editing the vault

See [vault-edit.md](../runbooks/vault-edit.md).

### Vault password

Delivered out-of-band. Never stored on the Droplet, never committed, never in environment variables on shared systems. Use `--ask-vault-pass` at runtime.

---

## Argument-spec validation

Per Ansible coding-standards addendum §5/§14, every role declares `meta/argument_specs.yml` and `defaults/main.yml`. Status (post-A3, see `docs/refactor.md`):

| Role | argument_specs | Required entry-point fields |
|---|---|---|
| `common` | ✅ | (4 path globals, all defaulted) |
| `docker` | ✅ | `vault_dockerhub_username`, `vault_dockerhub_token` (no defaults) |
| `traefik` | ✅ | `traefik_acme_email` (no default; vault sourced) |
| `wordpress` | ✅ | `enabled, site_name, site_domain, wp_image, wp_db_host, wp_db_name, wp_db_user, wp_db_password, wp_table_prefix` |
| `laravel` | ✅ | (laravel_site dict — read directly, not via item) |
| `webapp` | ✅ | `enabled, site_name, site_domain, image, port, env_vars` (optional: `www_redirect`) |
| `logging` | ✅ | `logging_enabled, logging_dir, logging_vector_image, logging_loki_endpoint, logging_loki_user, logging_loki_token, logging_deployment_label, logging_traefik_access_enabled, logging_traefik_access_path` (the three Loki credentials are vault-sourced, no default; `logging_loki_token` carries `no_log: true`) |

Missing required fields cause the role to fail at entry with a clear error rather than templating garbage.

---

## Linting

Two linters run in CI and locally:

- `ansible-lint` (production profile) — config at `.ansible-lint`. Pinned in `requirements.txt`.
- `yamllint` — config at `.yamllint`. Pinned in `requirements.txt`.

Both should exit 0 against `playbooks/`. CI workflow at `.github/workflows/lint.yml` runs on push and PR.

```bash
# Local checks before commit:
ansible-lint playbooks/
yamllint playbooks/
```

If you add a lint ignore, document the reason next to it. Do not silence lint findings without a written rationale.

---

## Container recreation policy

Per addendum §4: prefer `recreate: auto` over `recreate: always` on container-start tasks. Current state (post-A4):

- `wordpress`, `laravel`, `webapp`, `traefik` Start tasks: all `recreate: auto`.
- Traefik handler (`Restart traefik`): explicitly `recreate: always`, with block-comment rationale (compose v2 cannot detect changes to bind-mounted file content; `socket-proxy.conf` edits would be missed under `auto`).

If you add a new Start task, default to `auto`. Use `always` only with a written reason.

---

## Two parallel structures: `playbooks/` and `v1/`

Current state during the refactor:

- `playbooks/` — current structure. All new work lands here. Source of truth.
- `v1/` — legacy structure, retained for reference until the refactor is fully validated against all sites without regression.

When `v1/` retirement is appropriate, that's a sprint-level decision (PM step), not an architectural one.
