# Getting started

How to set up a fresh control node for ansible (the BitSalt infra-Ansible project) work and reach a state where you can run the playbook against the Droplet. Audience: an operator who has just cloned the repo and has the relevant credentials available.

For first-time bootstrap of a brand-new Droplet (which is a different concern), see [runbooks/bootstrap.md](runbooks/bootstrap.md).

For an end-to-end onboarding from zero context, see [onboarding.md](onboarding.md).

---

## Prerequisites

You should have:

- A Linux or macOS workstation. Windows via WSL works but is not the primary path.
- Python 3.11+ available.
- An SSH key registered as the `ansible` user's authorized key on the target Droplet (delivered out-of-band by the existing operator).
- The Ansible Vault password (delivered out-of-band).
- Read access to `~/projects/coding-standards/` (the general standards plus `coding-standards-ansible.md`).

---

## Set up the control node

```bash
# Clone the repo
git clone <ansible-repo-url> ~/projects/ansible
cd ~/projects/ansible

# Create a virtualenv for control-node tooling (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install the pinned tooling
pip install -r requirements.txt

# Install Ansible Galaxy collections
ansible-galaxy collection install -r playbooks/requirements.yml
```

Verify Ansible is on the version we expect (≥ 2.15):

```bash
ansible --version
```

---

## Verify the inventory

Open `playbooks/inventory/hosts.yml` and confirm:

- The Droplet IP / hostname matches the current target.
- The SSH port is the configured custom port (default 2222).
- The `ansible_user: ansible` line is present.

If the inventory is wrong for your workstation (e.g., a different SSH config alias), edit it locally — but **do not commit** workstation-specific changes. Use a per-user override file or a local-only branch.

---

## Validate vault access

```bash
cd playbooks
ansible-vault view group_vars/all/vault.yml
```

Enter the vault password when prompted. If the file decrypts and you see plain YAML, vault access is working. (The file should re-encrypt automatically when you exit the viewer.)

If you don't have the vault password, stop here and request it from the existing operator.

---

## First run — dry mode

Before applying anything, run a dry-run to confirm the control node can reach the Droplet, the inventory is correct, and you can see what the playbook would change:

```bash
ansible-playbook site.yml --ask-vault-pass --check --diff
```

Expected: a list of tasks the playbook would touch, with `changed=N` reflecting current drift between the repo and the Droplet. Any `unreachable` errors mean SSH or inventory is misconfigured — fix that before going further.

For more detail on `--check --diff`, see [ops/ansible.md § Common run commands](ops/ansible.md#common-run-commands).

---

## Run the linters

CI runs these on push/PR. Run them locally before commit too:

```bash
ansible-lint playbooks/
yamllint playbooks/
```

Both should exit 0. If either flags an issue, fix it (or document the ignore inline with a written rationale).

---

## Logging is opt-in

The `logging` role ships container stdout/stderr (and optionally Traefik's access log) to Grafana Cloud Loki via a single Vector container at `/opt/logging/`. **It is off by default** so a fresh clone applies cleanly before Loki credentials exist. If you've cloned this repo and run `ansible-playbook site.yml`, no log shipping is happening yet — that's expected.

To turn it on:

1. Populate `vault_logging_loki_endpoint`, `vault_logging_loki_user`, and `vault_logging_loki_token` in `playbooks/group_vars/all/vault.yml` (`ansible-vault edit`). The token is treated as `no_log` — never echo it.
2. Set `logging_enabled: true` in `playbooks/group_vars/all/vars.yml`.
3. Re-run the playbook (`--tags logging` is sufficient for an incremental change).

If any of the three Loki vault values are missing when the role runs, it fails at role entry with a clear error rather than starting a silently-misconfigured Vector — that's intentional.

For depth: [architecture.md § Logging](architecture.md#logging-cross-cutting) covers what the role does, [ADR 0008](adr/0008-centralized-logging-vector-loki.md) covers why Vector and Grafana Cloud Loki, and [requirements.md NFR7](requirements.md#nfr7--observability-centralized-logging) covers the requirement the role satisfies.

---

## Read before you write

Before making any non-trivial change, read:

- [architecture.md](architecture.md) — system shape.
- The [ADRs](adr/) most relevant to your change — especially [0006](adr/0006-webapp-ownership-boundary.md) if touching webapp sites and [0004](adr/0004-ansible-vault-only-secret-store.md) if touching anything secret-shaped.
- The active [sprint file](ansible.md) — what's already in flight.
- `~/projects/coding-standards/coding-standards-ansible.md` — the addendum we conform to.

---

## Common gotchas for new operators

- **Vault password is not on the Droplet.** Don't look there. It's delivered out-of-band by the existing operator.
- **Don't commit your `inventory/hosts.yml` workstation tweaks.** Use a local-only branch or the `host_vars` mechanism if you need workstation-specific overrides.
- **`--ask-vault-pass` is required** for any run that touches a vault value (essentially every site role). Don't skip it.

---

## Where to go next

- For the active sprint: [ansible.md](ansible.md).
- For "I want to add a site": [runbooks/add-wordpress-site.md](runbooks/add-wordpress-site.md) or [runbooks/add-webapp-site.md](runbooks/add-webapp-site.md).
- For "I want to bootstrap a new Droplet": [runbooks/bootstrap.md](runbooks/bootstrap.md).
- For a full conceptual onboarding: [onboarding.md](onboarding.md).
