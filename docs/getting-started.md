# Getting started

How to set up a fresh control node for bitsalt-ansible work and reach a state where you can run the playbook against the Droplet. Audience: an operator who has just cloned the repo and has the relevant credentials available.

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
git clone <bitsalt-ansible-repo-url> ~/projects/bitsalt-ansible
cd ~/projects/bitsalt-ansible

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

## Read before you write

Before making any non-trivial change, read:

- [architecture.md](architecture.md) — system shape.
- The [ADRs](adr/) most relevant to your change — especially [0006](adr/0006-webapp-ownership-boundary.md) if touching webapp sites and [0004](adr/0004-ansible-vault-only-secret-store.md) if touching anything secret-shaped.
- The active [sprint file](bitsalt-ansible.md) — what's already in flight.
- `~/projects/coding-standards/coding-standards-ansible.md` — the addendum we conform to.

---

## Common gotchas for new operators

- **Vault password is not on the Droplet.** Don't look there. It's delivered out-of-band by the existing operator.
- **Don't edit `v1/`.** That's the legacy structure; it's retained for reference, not active.
- **Don't commit your `inventory/hosts.yml` workstation tweaks.** Use a local-only branch or the `host_vars` mechanism if you need workstation-specific overrides.
- **`--ask-vault-pass` is required** for any run that touches a vault value (essentially every site role). Don't skip it.

---

## Where to go next

- For the active sprint: [bitsalt-ansible.md](bitsalt-ansible.md).
- For "I want to add a site": [runbooks/add-wordpress-site.md](runbooks/add-wordpress-site.md) or [runbooks/add-webapp-site.md](runbooks/add-webapp-site.md).
- For "I want to bootstrap a new Droplet": [runbooks/bootstrap.md](runbooks/bootstrap.md).
- For a full conceptual onboarding: [onboarding.md](onboarding.md).
