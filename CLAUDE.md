# BitSalt Containerization Project — Claude Code Context

## Project summary

Containerizing all BitSalt Digital LLC hosted client sites using Docker Compose
on a single DigitalOcean Droplet. Ansible manages provisioning. GitHub Actions
handles CI/CD for custom-image sites.

---

## Infrastructure

### Hosting platform
- **Provider:** DigitalOcean
- **Compute:** Single Droplet, 4–8GB RAM (exact size TBD at setup)
- **Databases:** DO Managed MySQL (WordPress + Laravel) and DO Managed PostgreSQL
  (Node.js sites) — no DB containers, all app containers connect to managed clusters
- **Container registry:** Docker Hub
- **Reverse proxy:** Traefik v3.0 running as a shared container, routes by domain,
  handles Let's Encrypt SSL automatically

### Server directory layout
```
/opt/proxy/          — Traefik stack
/opt/sites/          — one subdirectory per client site
  client-a/
    docker-compose.yml
    .env             — mode 0600, never committed
    wp-content/      — bind mount (WordPress only)
  laravel-site/
    docker-compose.yml
    .env
    storage/         — bind mount
  node-site-1/
    docker-compose.yml
    .env
/opt/backups/
/opt/scripts/
```

### Docker network
- Shared external network named `proxy`
- All site containers join it; Traefik routes via labels

---

## Site inventory

| Site | Type | Database | Image source |
|------|------|----------|--------------|
| client-a | WordPress | DO Managed MySQL | Official `wordpress:6.6-php8.2-fpm` |
| (additional WP sites) | WordPress | DO Managed MySQL | Same official image, pinned tag |
| laravel-site | Laravel | DO Managed MySQL | Custom, Docker Hub: `yourdockerhub/laravel-site` |
| node-site-1 | Node.js | DO Managed PostgreSQL | Custom, Docker Hub: `yourdockerhub/node-site-1` |
| node-site-2 | Node.js | DO Managed PostgreSQL | Custom, Docker Hub: `yourdockerhub/node-site-2` |

---

## CI/CD — GitHub Actions

Laravel and Node.js sites deploy automatically on merge to `main`:
1. Build Docker image, tag with `github.sha`
2. Push to Docker Hub
3. SSH into Droplet as `deploy` user, `sed` the image tag in `docker-compose.yml`,
   `docker compose pull && docker compose up -d`
4. Laravel: also runs `php artisan migrate --force`

### GitHub Secrets required per repo
- `DOCKER_USERNAME`
- `DOCKER_PASSWORD`
- `DROPLET_HOST`
- `DEPLOY_SSH_KEY` — private key for the `deploy` user (manually generated,
  private key deleted from Droplet after copying to GitHub)

### Rollback
Each deploy tags with `github.sha`. Revert the tag in `docker-compose.yml`
and run `docker compose up -d`. Maintain `/opt/deployments.txt` with last
known good tag per site.

---

## WordPress update workflow

- **Core updates:** bump image tag in `docker-compose.yml`, `docker compose pull && up -d`
- **Plugin/theme updates:** WP-CLI via the `wordpress:cli` image (FPM images don't include `wp`)
  ```bash
  docker run --rm \
    --user www-data \
    --volumes-from <site>-wordpress-1 \
    --network container:<site>-wordpress-1 \
    --env-file /opt/sites/<site>/.env \
    wordpress:cli-php8.2 \
    wp plugin update --all --path=/var/www/html
  ```

---

## Users on the Droplet

| User | Purpose | Sudo | Notes |
|------|---------|------|-------|
| `bitsalt` | Admin / day-to-day SSH | Yes (NOPASSWD) | Personal SSH key |
| `ansible` | Ansible control node SSH | Yes (NOPASSWD) | Ansible SSH key |
| `deploy` | GitHub Actions SSH deploys | No | Narrowly scoped; key managed manually |

- Root SSH login disabled
- Password authentication disabled
- SSH port changed from 22 (port set in bootstrap.sh, default 2222)
- `deploy` user SSH key: generated on Droplet, private key copied to GitHub
  Secrets then deleted from Droplet

---

## Bootstrap script

File: `bootstrap.sh`
- Run as root on a fresh DO Ubuntu 24.04 Droplet
- Creates `bitsalt` and `ansible` users with SSH keys and sudo
- Hardens `sshd_config` via drop-in `/etc/ssh/sshd_config.d/99-bitsalt-hardening.conf`
- Configures UFW (deny all inbound except SSH port, 80, 443)
- Installs and configures Fail2ban
- Configures unattended security upgrades (no auto-reboot)
- Prints manual steps for deploy user key and DO monitoring at completion

**Manual steps after bootstrap (not automatable):**
1. Generate `deploy` user SSH key, copy private key to GitHub Secrets, delete
   private key from Droplet
2. Optionally restrict SSH to static home/office IP via UFW
3. Enable DO Monitoring agent and set CPU/disk alerts in DO dashboard

---

## Ansible project

File: `bitsalt-ansible.tar.gz`

### Structure
```
bitsalt-ansible/
  ansible.cfg
  site.yml                      — top-level orchestrator
  requirements.yml              — community.docker >= 3.10.0
  inventory/
    hosts.yml                   — single host: droplet, ansible user, custom SSH port
  group_vars/
    all/
      vars.yml                  — non-sensitive globals
      vault.yml                 — Ansible Vault (MUST be encrypted before committing)
  vars/
    sites/
      client-a.yml              — per-site var file (WordPress example)
      laravel-site.yml          — Laravel site vars
      node-site-1.yml           — Node.js site vars
  roles/
    common/                     — base packages, /opt/* directory structure
    docker/                     — Docker Engine, compose plugin, proxy network
    traefik/                    — Traefik stack, acme.json, templated compose file
    wordpress/                  — looped over wordpress_sites list in site.yml
    laravel/                    — single site, queue worker toggle, scheduler cron
    nodejs/                     — looped over nodejs_sites list in site.yml
```

### Role loop pattern
WordPress and Node.js roles loop via `site.yml`:
```yaml
- role: wordpress
  tags: [wordpress]
  loop: "{{ wordpress_sites }}"
  loop_control:
    loop_var: item
    label: "{{ item.site_name }}"
```
Requires Ansible 2.15+. If older, restructure to `include_role` inside a
task-level loop.

### Secrets pattern
- All sensitive values in `group_vars/all/vault.yml`, prefixed `vault_`
- Referenced in `vars.yml` and templates as `{{ vault_<name> }}`
- Per-site DB passwords: `vault_client_a_db_password`, etc.
- Encrypt: `ansible-vault encrypt group_vars/all/vault.yml`
- Edit: `ansible-vault edit group_vars/all/vault.yml`

### Adding a new WordPress site
1. Copy `vars/sites/client-a.yml` → `vars/sites/new-client.yml`, fill in values
2. Add DB password to vault: `ansible-vault edit group_vars/all/vault.yml`
3. Add site dict to `wordpress_sites` list in `site.yml`
4. Run: `ansible-playbook site.yml --ask-vault-pass --tags wordpress`

### Common run commands
```bash
# Full provisioning
ansible-playbook site.yml --ask-vault-pass

# Single role
ansible-playbook site.yml --ask-vault-pass --tags traefik

# Dry run
ansible-playbook site.yml --ask-vault-pass --check
```

---

## Work completed

- [x] Architecture design (Traefik + Docker Compose on single DO Droplet)
- [x] Per-app-type Compose stack design (WordPress, Laravel, Node.js)
- [x] GitHub Actions deploy pipeline design (Laravel + Node.js)
- [x] DO vs AWS cost comparison (DO wins significantly at this scale)
- [x] Droplet hardening plan
- [x] Bootstrap script (`bootstrap.sh`)
- [x] Full Ansible project (all roles, templates, vault structure, site.yml)

## Work remaining / natural next steps

- [ ] Backup cron role (MySQL + PostgreSQL dumps to DO Spaces, 14-day local
      retention, 90-day Spaces retention) — was deferred from initial Ansible scope
- [ ] UFW / Fail2ban / unattended-upgrades Ansible roles — bootstrap script
      handles initial setup, but Ansible roles would allow re-convergence on rebuild
- [ ] Migration execution — migrate sites one at a time per Phase 6 of the plan
- [ ] node-site-2 vars file — copy node-site-1.yml, uncomment in site.yml
- [ ] Real domain names and Docker Hub image names substituted throughout
- [ ] Vault populated with real credentials and encrypted
- [ ] DO Monitoring alerts configured in dashboard
- [ ] Deploy user SSH key generated and added to GitHub Secrets

---

## Key decisions made

- No DB containers — all sites connect to DO Managed clusters
- Traefik (not Nginx Proxy Manager) — label-driven, no UI dependency
- Docker Hub for image registry (not DO Container Registry)
- Ansible Vault for all secrets
- One vars file per site (not group_vars or inline)
- Both `docker-compose.yml` and `.env` templated by Ansible
- Deploy user managed manually (not by Ansible) — key must flow through
  GitHub Secrets by hand
- Bootstrap script handles SSH hardening before Ansible runs to avoid
  connection breakage mid-play
