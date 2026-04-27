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
ansible-playbook site.yml --ask-vault-pass --tags fastapi
ansible-playbook site.yml --ask-vault-pass --tags webapp    # both nodejs + fastapi
```

Check mode (dry run):
```bash
ansible-playbook site.yml --ask-vault-pass --check
```

## Adding a new WordPress site

1. Copy `vars/sites/taotedev.yml` to `vars/sites/new-client.yml`. Rename the dict key to match (e.g. `new_client_site`) and fill in values.
2. Add the DB password to `vault.yml`:
   ```bash
   ansible-vault edit group_vars/all/vault.yml
   ```
3. In `site.yml`, add the var file to `vars_files` and add `"{{ new_client_site }}"` to the `wordpress_sites` list.
4. Run:
   ```bash
   ansible-playbook site.yml --ask-vault-pass --tags wordpress
   ```

## Adding a new Node.js site

Same pattern — copy `vars/sites/node-site-1.yml`, rename the dict key, add the var file to `vars_files` in `site.yml`, add `"{{ new_site }}"` to `_nodejs_site_candidates`, run with `--tags nodejs`.

## Adding a new FastAPI site

Node.js and FastAPI sites share the `webapp` role (a generic stateless-HTTP-container pattern). Only the list membership differs.

1. Create `vars/sites/<api-name>.yml` defining a dict with `enabled`, `site_name`, `site_domain`, `image`, `port`, and an `env_vars` map. Reference any secrets as `{{ vault_<name> }}`.
2. Add credentials/secrets to `vault.yml`.
3. In `site.yml`: add the var file to `vars_files`, add `"{{ <dict_name> }}"` to `_fastapi_site_candidates`.
4. Run: `ansible-playbook site.yml --ask-vault-pass --tags fastapi`

## Directory structure

```
ansible/
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
      taotedev.yml                # one file per site (defines <sitename>_site dict)
      laravel-site.yml
      node-site-1.yml
  roles/
    common/                       # base packages, directory structure
    docker/                       # Docker Engine + compose plugin
    traefik/                      # reverse proxy stack
    wordpress/                    # WP sites (looped)
    laravel/                      # Laravel site + queue + scheduler
    webapp/                       # Node.js + FastAPI sites (looped)
```
