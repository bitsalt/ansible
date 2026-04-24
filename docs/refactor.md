# Ansible Refactor — Coding-Standards Adoption & Drift Reconciliation

Carry-over from session 2026-04-23. Two independent workstreams.

---

## Background

A new Ansible addendum to the coding standards was authored this session:
`~/projects/coding-standards/coding-standards-ansible.md`. It codifies how the
core coding standards (§1–§16) map onto Ansible, and flags five known gaps in
this repo. This document tracks the work to close those gaps and to reconcile
the pre-existing drift that surfaced when a baseline `--check --diff` was run.

The `--check --diff` baseline captured this session lives at:
`.checks/baseline.log` (not committed — regenerate with the command below).

```bash
cd playbooks
ansible-playbook site.yml --check --diff > ../.checks/baseline.log 2>&1
```

Baseline recap: `ok=45 changed=9 skipped=4 failed=0 unreachable=0`.

---

## Task A — Adopt the Ansible coding-standards addendum

Four code changes derived from the "Known gaps" section of the addendum.
All four are pure code edits. **None require the playbook to be applied** —
they land by commit. Use `--check --diff` before/after each to confirm the
change-set either shrinks (change 4) or stays identical (changes 1–3) vs.
baseline.

Ordered from zero-risk to highest blast radius. Do them in this order.

### A1. `no_log: true` on every task that renders a secret ✅

**Status:** Done — commit `927b264` (2026-04-24). `--check --diff` matches
baseline (`ok=45 changed=9`); env-template diff bodies now suppressed.

Addendum §7/§8. Currently leaking vault values to stdout at `-v` and above.

- [playbooks/roles/wordpress/tasks/main.yml:50](../playbooks/roles/wordpress/tasks/main.yml#L50) — "Deploy .env file" renders `WORDPRESS_DB_PASSWORD` from a vault var.
- [playbooks/roles/webapp/tasks/main.yml:27](../playbooks/roles/webapp/tasks/main.yml#L27) — "Deploy .env file" renders site env vars (may include secrets depending on site).
- [playbooks/roles/laravel/tasks/main.yml](../playbooks/roles/laravel/tasks/main.yml) — check and add wherever `.env` is templated.
- [playbooks/roles/docker/tasks/main.yml:53](../playbooks/roles/docker/tasks/main.yml#L53) — "Authenticate with Docker Hub" already uses `community.docker.docker_login` with vault creds; add `no_log: true`.

Rule: any task whose module arguments or rendered output include a `vault_*`
variable gets `no_log: true`.

**Verification:** post-edit `--check --diff` should match baseline exactly,
except that the diffs for the touched template tasks are suppressed (Ansible
replaces them with "the output has been hidden due to the fact that 'no_log: true'
was specified"). No task `changed` flags should flip.

### A2. `ansible-lint` + `yamllint` config + CI hook ✅

**Status:** Done — commit `c4bffe3` (2026-04-24). Both linters exit 0 against
`playbooks/` (ansible-lint passes the `production` profile). CI workflow at
`.github/workflows/lint.yml` runs on push/PR. Versions pinned in
`requirements.txt` (ansible-lint 6.17.2, yamllint 1.33.0). `--check --diff`
matches post-A1 baseline (`ok=45 changed=9`).

Addendum §11. Neither is currently configured.

- Add `.ansible-lint` and `.yamllint` to the repo root (or `playbooks/`, decide
  based on where `ansible-lint` discovers files).
- Minimal config: adopt defaults, add ignore lines only for real false
  positives (document the reason next to each ignore).
- Wire a pre-commit hook (optional) and a CI step (GitHub Actions lives under
  `.github/workflows/` — there's already a `deploy-staging.yml` to reference).
- Fix whatever lint flags. Expect complaints about: missing `changed_when` on
  a `shell`/`command` task if any exist; task names; YAML indentation drift.

**Verification:** `ansible-lint playbooks/` and `yamllint playbooks/` both exit 0.
Playbook `--check --diff` unchanged vs. baseline.

### A3. `meta/argument_specs.yml` + `defaults/main.yml` on every role

Addendum §5/§14. No role currently has either. Start with the `webapp` role —
it has the highest reuse (Node.js + FastAPI) so the schema pays off most.

Roles to add files to (current list):
- `playbooks/roles/webapp/` ✅ — commit `162a6fb` (2026-04-24). `item` dict
  schema declared (required: enabled, site_name, site_domain, image, port,
  env_vars; optional: www_redirect). Negative test passes (role refuses to
  run on missing required field with a clear error).
- `playbooks/roles/wordpress/` ✅ — commit `23c8545` (2026-04-24). `item`
  dict schema declared (required: enabled, site_name, site_domain, wp_image,
  wp_db_host, wp_db_name, wp_db_user, wp_db_password, wp_table_prefix).
  `wp_db_password` carries `no_log: true` in the spec. Negative test passes.
- `playbooks/roles/laravel/` ✅ — commit `a8fd960` (2026-04-24). Declares
  the `laravel_site` dict schema (role reads it directly, not via `item`).
  `laravel_app_key`/`laravel_db_password` carry `no_log: true`;
  `laravel_app_debug` is str with choices ["true","false"] because Ansible
  renders Python bools as "True"/"False" (capital) which Laravel's .env
  parser rejects. Negative test via `-e` passes.
- `playbooks/roles/traefik/` ✅ — commit `5955773` (2026-04-24). Five
  globals declared (proxy_dir, traefik_image, docker_proxy_network,
  docker_proxy_subnet, traefik_acme_email); the email has no default (vault
  sourced, no safe fallback), the other four do. First non-looped role, so
  no negative test for missing-field — every field has either a default or
  a non-optional group_vars source.
- `playbooks/roles/common/` ✅ — commit `898c256` (2026-04-24). Four path
  globals declared (sites_base_dir, proxy_dir, backup_dir, scripts_dir),
  all with defaults.
- `playbooks/roles/docker/` ✅ — commit `1de1471` (2026-04-24). Four inputs
  declared: docker_proxy_network, deploy_user, plus vault_dockerhub_username
  and vault_dockerhub_token (both `no_log: true`). Vault credentials have
  no defaults — missing values must fail at entry.

**A3 complete** — all 6 roles (webapp, wordpress, laravel, traefik, common,
docker) now have `meta/argument_specs.yml` and `defaults/main.yml`.
Final post-A3 baseline: `ok=53 changed=9` (baseline was `ok=45`; the +8 is
one arg-spec validation per role invocation: 2 wordpress + 3 webapp + 1
traefik + 1 common + 1 docker = 8).

Expect: when a site vars file omits a required field, the role should fail at
entry with a clear error rather than halfway through template rendering.

**Verification:** `--check --diff` matches baseline; additionally, deliberately
remove a required field from a site vars file and confirm the role refuses to
run instead of templating garbage.

### A4. `recreate: always` → `recreate: auto` ✅

**Status:** Done — commit `8bba511` (2026-04-24). Flipped to `auto` on
three Start tasks (wordpress, laravel, traefik). The traefik handler stays
at `always` with a block-comment rationale (compose v2 cannot detect
changes to bind-mounted file content; socket-proxy.conf edits would be
missed under `auto`). Also caught and flipped the laravel task that the
original doc missed.

**Verification caveat:** `--check --diff` does *not* visibly shrink from
`changed=9` to `changed=6` because community.docker 3.7.0 simulates
pull/recreate steps regardless of the `recreate:` setting, inflating the
check-mode view. Observing the reduction requires the collection upgrade
(Task B step 1) first. The code change is §4-compliant and takes effect
on real apply.

Addendum §4. Current uses:
- [playbooks/roles/traefik/tasks/main.yml:49](../playbooks/roles/traefik/tasks/main.yml#L49) — "Start Traefik stack"
- [playbooks/roles/traefik/handlers/main.yml](../playbooks/roles/traefik/handlers/main.yml) — "Restart traefik" handler
- [playbooks/roles/wordpress/tasks/main.yml:71](../playbooks/roles/wordpress/tasks/main.yml#L71) — "Start WordPress site"

For WordPress: the role already has a separate task (line 59) that removes the
site with `remove_volumes: true` when `.env` changes. That's the legitimate
"real change detected, force recreate" path. The `recreate: always` on the
following task is redundant with that mechanism and causes unnecessary
recreation on every run. Change to `recreate: auto`.

For Traefik: there's no similar change-detection task today. Before flipping
to `auto`, confirm that a config change (templated `docker-compose.yml` or
`socket-proxy.conf`) will be picked up by compose's own change detection. It
should be — compose hashes the config. If in doubt, register the template
tasks and notify a handler that does `recreate: always` only when the template
changed.

**Verification:** `--check --diff` after this change should show *fewer*
changed tasks than baseline (the recreate-churn entries drop out). This is
the one task in A where the change-set is expected to shrink, not match.

### Landing sequence

Per one-task-per-session, A1–A4 may be one session each or bundled. Recommend:

- A1 alone (security, obviously correct) → commit
- A2 alone (tooling, may surface rework) → commit
- A3 possibly split by role → commit per role
- A4 last, with extra scrutiny on Traefik

Do not apply the playbook after any A* commit. Applying is Task B.

---

## Task B — Reconcile pre-existing drift, then apply

Independent of Task A. The baseline `--check --diff` revealed drift between
what the Ansible repo templates and what's on the Droplet:

### Drift inventory (from session 2026-04-23 baseline)

1. **`community.docker` 3.7.0 installed; `requirements.yml` wants ≥ 3.10.0.**
   Symptom: many `[WARNING]: Event line is missing dry-run mode marker` lines.
   Not breaking, but check-mode fidelity is degraded. **Upgrade first** before
   trusting further `--check` runs.

2. **Traefik stack would be recreated on apply.** Driven by `recreate: always`
   in [playbooks/roles/traefik/tasks/main.yml:49](../playbooks/roles/traefik/tasks/main.yml#L49). Apply = brief full-stack outage
   (all sites) while Traefik restarts. Task A4 reduces the blast radius of
   future runs but does not resolve this one — the next apply after A4
   lands will still recreate if the templated `docker-compose.yml` or
   `socket-proxy.conf` differs from what's deployed (compose will detect and
   recreate).

3. ✅ ~~Three webapp sites have real `docker-compose.yml` drift~~ —
   **resolved by ownership change (2026-04-24).** Decision: Ansible owns
   `.env` for webapp sites; the app repo owns `docker-compose.yml`.
   `webapp` role no longer templates compose. See CLAUDE.md "Ownership
   boundary for `webapp` sites." The 3 drift entries dropped out of
   `--check --diff` (`changed=7 → changed=4`).

4. **bitsalt-staging has `.env` drift** — stale `SITE_DOMAIN=` and
   `SERVICE_NAME=` lines on disk; template no longer emits them.

5. **Two WordPress sites recreate on every apply** — `recreate: always` in
   wordpress role. Same fix path as Traefik (Task A4).

6. **`wordpress : Create wp-content bind mount directory`** reports changed
   every run. Likely `recurse: true, mode: "0755"` flipping mode bits on
   user-owned files under `wp-content/`. Cosmetic but worth fixing —
   investigate whether the recurse is actually needed or can be replaced
   with a one-time chmod at site creation.

### Suggested Task B sequencing (future session)

1. ✅ Upgrade `community.docker` to ≥ 3.10.0 — **done** (`364d33c`,
   2026-04-24). Galaxy resolved to 5.2.0; `requirements.yml` pinned to
   `==5.2.0` per addendum §12. Post-upgrade baseline: `ok=53 changed=7`
   (was `changed=9` under 3.7.0); A4's wordpress recreate-churn dropped
   out. Dry-run warnings gone. KB lesson: `community.docker/check-mode-fidelity-pre-3-10.md`.
2. Re-run baseline and re-inspect drift with better check-mode fidelity.
3. ✅ ~~For each webapp site with compose drift~~ — resolved by ownership
   decision. Ansible no longer templates webapp compose (see drift #3 above).
4. Identify maintenance window for Traefik restart. Three customer-facing
   sites share Traefik (bitsalt.com, frujo.net, mybusinessmagnet.tech);
   pick a low-traffic window and apply via `--tags traefik`.
5. Apply in order: common → docker → traefik (window) → webapp sites
   (one at a time with `node_site_filter`) → wordpress sites.
6. Second consecutive apply must report `changed=0`. If not, investigate
   non-idempotent tasks.

---

## Open questions — resolved 2026-04-24

- ✅ **Compose ownership.** Ansible owns `.env` for webapp sites; the app
  repo owns `docker-compose.yml` and the deploy flow. App repos differ
  enough in deploy needs that Ansible re-rendering compose was fighting
  per-repo decisions. See CLAUDE.md "Ownership boundary for `webapp` sites."
  `wordpress` and `laravel` roles are unaffected — no per-app CI, Ansible
  keeps full compose ownership for those.
- ✅ **Customer-facing sites for the Traefik window.** bitsalt.com,
  frujo.net, mybusinessmagnet.tech. Traefik restart blast radius = 3.
  Pick a low-traffic window (weekend night / dawn) when scheduling Task
  B step 4.
