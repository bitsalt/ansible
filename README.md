# BitSalt Ansible

Provisions and manages the BitSalt hosted client Droplet.

## Prerequisites

On your local Linux desktop:

```bash
pip install ansible
ansible-galaxy collection install -r requirements.yml
```

## First-time setup

1. Edit `inventory/hosts.yml` — set the Droplet IP and SSH port.
2. Edit `group_vars/all/vault.yml` — fill in all `CHANGEME` values.
3. Encrypt the vault file:
   ```bash
   ansible-vault encrypt group_vars/all/vault.yml
   ```
4. Fill in `site.yml` — update image names and domain names to match your actual sites.
5. Add per-site var files under `vars/sites/` for any sites beyond the examples.

## Running

Full provisioning run:
```bash
ansible-playbook site.yml --ask-vault-pass
```

Target a single role:
```bash
ansible-playbook site.yml --ask-vault-pass --tags traefik
ansible-playbook site.yml --ask-vault-pass --tags wordpress
ansible-playbook site.yml --ask-vault-pass --tags laravel
ansible-playbook site.yml --ask-vault-pass --tags nodejs
```

Check mode (dry run):
```bash
ansible-playbook site.yml --ask-vault-pass --check
```

## Adding a new WordPress site

1. Copy `vars/sites/client-a.yml` to `vars/sites/new-client.yml` and fill in values.
2. Add the DB password to `vault.yml`:
   ```bash
   ansible-vault edit group_vars/all/vault.yml
   ```
3. Add the new site dict to the `wordpress_sites` list in `site.yml`.
4. Run:
   ```bash
   ansible-playbook site.yml --ask-vault-pass --tags wordpress
   ```

## Adding a new Node.js site

Same pattern — copy `vars/sites/node-site-1.yml`, add to `nodejs_sites` in `site.yml`, run with `--tags nodejs`.

## Directory structure

```
bitsalt-ansible/
  ansible.cfg
  site.yml                        # top-level orchestrator
  requirements.yml                # collection dependencies
  inventory/
    hosts.yml
  group_vars/
    all/
      vars.yml                    # non-sensitive globals
      vault.yml                   # Ansible Vault — ENCRYPT BEFORE COMMITTING
  vars/
    sites/
      client-a.yml                # one file per site
      laravel-site.yml
      node-site-1.yml
  roles/
    common/                       # base packages, directory structure
    docker/                       # Docker Engine + compose plugin
    traefik/                      # reverse proxy stack
    wordpress/                    # WP sites (looped)
    laravel/                      # Laravel site + queue + scheduler
    nodejs/                       # Node.js sites (looped)
```
