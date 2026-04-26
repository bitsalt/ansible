# Runbook: Add a webapp (Node.js / FastAPI / similar) site

Add a new webapp site to the BitSalt fleet. Differs from WordPress / Laravel because Ansible owns `.env` but the app repo owns `docker-compose.yml`.

**User story:** [add-webapp-site](../user-stories/add-webapp-site.md)
**Related ADR:** [0006 webapp ownership boundary](../adr/0006-webapp-ownership-boundary.md)
**Related interface:** [ci-deploy.md](../interfaces/ci-deploy.md)

---

## Trigger

A new webapp (Node.js, FastAPI, or similar single-port HTTP app) is ready to deploy to the Droplet for the first time. The app already has its own GitHub repo with a build-and-push CI pipeline, or one is being added as part of this work.

## Pre-checks

- [ ] DNS A record for the site domain points at the Droplet IP.
- [ ] DO Managed PostgreSQL has a database created for the site, plus a user with full privileges on that DB.
- [ ] The Droplet IP is in the DO Managed PostgreSQL cluster's trusted-sources list.
- [ ] The app's Docker image has been pushed to Docker Hub at a known tag (commit SHA preferred).
- [ ] You have all required environment values for the app, including DB password, ready to add to the vault.
- [ ] You have decided the site's domain, port (the *internal* port the container listens on), and any non-secret env vars.

## Steps

### 1. Create the site var file

Copy `vars/sites/node-site-1.yml` (or any existing webapp site) to `vars/sites/<new-site>.yml`. Edit the named dict:

```yaml
<site>_site:
  enabled: false   # leave false until the app repo's first deploy lands compose
  site_name: <site-slug>
  site_domain: <site-domain>
  image: <dockerhub-org>/<image>:<tag>
  port: 3000   # whatever the app listens on internally
  env_vars:
    NODE_ENV: production
    DATABASE_URL: "postgres://<user>:{{ vault_<site>_db_password }}@<host>:25060/<db>?sslmode=require"
    # ... other non-secret env vars
  www_redirect: true   # optional
```

Required fields per the role's `meta/argument_specs.yml`: `enabled`, `site_name`, `site_domain`, `image`, `port`, `env_vars`. Missing required fields cause Ansible to fail at entry with a clear error.

### 2. Add secrets to the vault

```bash
cd playbooks
ansible-vault edit group_vars/all/vault.yml
```

Add the site's DB password and any other secret env values:

```yaml
vault_<site>_db_password: <password>
vault_<site>_<other_secret>: <value>
```

### 3. Wire the site into `site.yml`

Edit `playbooks/site.yml`:

- Add the var file to `vars_files`:
  ```yaml
  - vars/sites/<new-site>.yml
  ```
- Add the dict to the appropriate stack list (`nodejs_sites` or `fastapi_sites`):
  ```yaml
  nodejs_sites:
    - "{{ <site>_site }}"
  ```

### 4. First Ansible run (with `enabled: false` still)

```bash
cd playbooks
ansible-playbook site.yml --ask-vault-pass --tags webapp
```

This run is a no-op for the new site (because `enabled: false`). Run it anyway to confirm the var file and vault edits parse cleanly.

### 5. Flip `enabled: true` and run again

Edit the site var file: `enabled: true`. Re-run:

```bash
ansible-playbook site.yml --ask-vault-pass --tags webapp
```

Expected behavior:
- `/opt/sites/<site>/` is created.
- `.env` is rendered at mode 0600 from the vault-sourced values.
- The container-start task **stat-gates on `docker-compose.yml`** — it skips because the file doesn't exist yet. This is correct.

### 6. Trigger the app repo's CI/CD deploy

The app repo's GitHub Actions workflow:
1. Builds the image (if not already done) and pushes to Docker Hub.
2. SSHes into the Droplet as the `deploy` user.
3. Writes `/opt/sites/<site>/docker-compose.yml` (or substitutes the new image tag into an existing one).
4. Runs `docker compose pull && docker compose up -d` in that directory.

The compose file must satisfy the contract in [ci-deploy.md](../interfaces/ci-deploy.md):
- `env_file: .env`
- Joins the `proxy` external network.
- Carries Traefik labels for the site's domain.

### 7. Set up the deploy SSH key (one-time, per app repo)

If this is the first deploy for this app repo, you also need to:

1. SSH into the Droplet as `bitsalt`.
2. Generate a dedicated SSH key for the `deploy` user:
   ```bash
   sudo -u deploy ssh-keygen -t ed25519 -f /home/deploy/.ssh/<repo>_deploy -N ''
   sudo cat /home/deploy/.ssh/<repo>_deploy.pub | sudo tee -a /home/deploy/.ssh/authorized_keys
   ```
3. Copy the *private* key (`/home/deploy/.ssh/<repo>_deploy`) to the app repo's GitHub Secret `DEPLOY_SSH_KEY`.
4. **Delete the private key from the Droplet:**
   ```bash
   sudo rm /home/deploy/.ssh/<repo>_deploy
   ```
5. Set the other GitHub Secrets per [ci-deploy.md § Required GitHub Secrets per app repo](../interfaces/ci-deploy.md#required-github-secrets-per-app-repo).

### 8. Verify

- [ ] `docker ps` on the Droplet shows the new container running.
- [ ] `https://<site-domain>/` loads (allow a few minutes for the cert challenge to complete).
- [ ] App logs (`docker compose logs -f` in `/opt/sites/<site>/`) show no startup errors.

### 9. Confirm idempotence

Re-run Ansible:

```bash
ansible-playbook site.yml --ask-vault-pass --tags webapp
```

Expected: `changed=0` for this site. **Critical:** `--check --diff` should show zero `docker-compose.yml` drift — the role no longer templates compose, so any drift is a real configuration issue (the operator manually edited the file) and must be investigated.

## Rollback

If the site is broken after the first deploy:
1. Set `enabled: false` and re-run `--tags webapp` to stop Ansible from interacting with the site.
2. Have the app repo's CI deploy a previous good image tag.
3. If the issue is in `.env`, revert the vault edit, re-run Ansible to re-render `.env`, then have CI redeploy.

## Post-incident notes

Record any deviations here. Currently empty.

## Common gotchas

- **Ansible run before first CI deploy is *expected* to skip container start.** The stat-gate is intentional. Do not add a fallback that templates compose — that breaks ADR 0006.
- **`compose v2` hashes `env_file`** — when `.env` changes (vault edit + Ansible re-run), the next Ansible run with `recreate: auto` will recreate the container to pick up new env values.
- **DB connection.** The `DATABASE_URL` env var (or the PG-specific equivalent) must include `sslmode=require` for DO Managed PostgreSQL.
- **Trusted sources.** As with WordPress/MySQL: the Droplet IP must be in the cluster's trusted-sources list, or connections silently fail.
