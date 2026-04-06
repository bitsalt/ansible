# BitSalt Ansible — Project Status

Last updated: 2026-04-06

---

## What has been completed

### Ansible project structure
- Full role structure in place: `common`, `docker`, `traefik`, `wordpress`, `laravel`, `nodejs`
- Per-site var files refactored to use named dicts (e.g. `taotedev_site: {...}`) loaded via `vars_files` and assembled into lists in `site.yml` — clean and scalable to 12+ sites
- `site.yml` restructured from `roles:` loop to `tasks: include_role` with `apply: tags` so `--tags wordpress` correctly executes tasks inside the role
- `enabled` flag added to all site var files — set `false` to skip a site without removing its var file
- Handlers removed from all site roles (wordpress, laravel, nodejs) — replaced with `recreate: always` on the Start tasks, which is more reliable and avoids the `item` undefined bug in handler context

### Docker / Traefik
- `python3-docker` added to the docker role apt install list (required by `community.docker` modules)
- Docker Hub authentication added to the docker role via `community.docker.docker_login` using vault-stored `vault_dockerhub_username` and `vault_dockerhub_token`
- Docker socket proxy introduced (nginx:alpine rewriting `/v1.24/` → `/v1.41/`) to work around Traefik v3.3's Docker SDK sending API version 1.24 to a daemon with MinAPIVersion 1.40
- Traefik updated from v3.0 → v3.3
- `recreate: always` added to the Traefik start task so `--tags traefik` always forces recreation
- `traefik_acme_email` correctly sourced from vault

### WordPress role
- Nginx sidecar added to the WordPress Compose stack — nginx handles HTTP, proxies PHP to FPM on port 9000, carries the Traefik labels
- `wordpress_data` named volume shared between FPM and nginx containers
- `internal` network isolates FPM from the proxy network
- Traefik service label (`traefik.http.services.{{ site_name }}.loadbalancer.server.port=80`) added to resolve "service does not exist" error
- www → apex 301 redirect added to all three Compose templates (wordpress, laravel, nodejs)
- `wordpress_default_image` variable now used in `taotedev_site` dict instead of hardcoded image string

### vault.yml
- Already encrypted
- `taotedev_db_password` correctly named (no vault_ prefix — intentional)
- Docker Hub credentials fields added: `vault_dockerhub_username`, `vault_dockerhub_token`

---

## Current state — taotedev.com

The following containers are running on the Droplet:

| Container | Image | Status |
|-----------|-------|--------|
| `taotedev-wordpress-1` | wordpress:6.9.4-php8.2-fpm | Up |
| `taotedev-nginx-1` | nginx:alpine | Up |
| `proxy-traefik-1` | traefik:v3.3 | Up |
| `proxy-socket-proxy-1` | nginx:alpine | Up |

**taotedev.com is fully live.** WordPress loads, plugins are up to date, and SSL cert is issued via Let's Encrypt/Traefik.

---

## What still needs to be done

### Immediate — taotedev.com
- [x] Resolve gateway timeout (nginx → FPM connection)
- [x] Verify WordPress site loads correctly and wp-content files are in place
- [x] Confirm SSL cert is issued (Let's Encrypt via Traefik)

### Ansible / infrastructure
- [ ] Backup cron role — MySQL + PostgreSQL dumps to DO Spaces, 14-day local / 90-day Spaces retention (deferred from initial scope)
- [ ] UFW / Fail2ban / unattended-upgrades Ansible roles (bootstrap.sh handles initial setup; roles needed for re-convergence on rebuild)
- [ ] node-site-2 vars file — copy node-site-1.yml when ready
- [ ] Real Docker Hub image names substituted into laravel and nodejs site var files
- [ ] `enabled: true` set in laravel and nodejs var files once images are built and pushed

### Remaining sites (migration)
- [ ] Migrate remaining ~11 WordPress sites one at a time (create var file, populate vault, run `--tags wordpress`)
- [ ] Real domain names substituted throughout all placeholder var files
- [ ] Real credentials populated in vault for all sites

### GitHub Actions (laravel + nodejs)
- [ ] Deploy user SSH key generated on Droplet, private key added to GitHub Secrets, deleted from Droplet
- [ ] GitHub Secrets set per repo: `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DROPLET_HOST`, `DEPLOY_SSH_KEY`
- [ ] CI/CD pipeline tested end-to-end for Laravel and Node.js sites

### DO platform
- [ ] DO Monitoring agent enabled, CPU/disk alerts configured in dashboard

---

## Key decisions and lessons learned

- **DO Managed MySQL `internal: true` cuts external DNS** — the WordPress FPM container must NOT be on a Docker network with `internal: true` when it connects to DO Managed MySQL. That flag blocks all external routing including DNS resolution.
- **DO Managed MySQL requires SSL** — add `WORDPRESS_CONFIG_EXTRA=define("MYSQL_CLIENT_FLAGS", MYSQLI_CLIENT_SSL);` to the `.env`. Use double quotes; single quotes are rejected by the WordPress entrypoint.
- **DO Managed MySQL trusted sources** — the Droplet must be added to the DB cluster's trusted sources in the DO dashboard or connections are silently dropped.
- **`wp-content` must be owned by uid 33 (www-data)** — the bind-mounted wp-content dir must be `chown -R 33:33` on the host. Ansible task now uses `owner: "33"` with `recurse: true`.
- **WP-CLI requires the `wordpress:cli-php8.2` image** — FPM images don't include `wp`. Use `--volumes-from` and `--network container:` flags to share the running container's context.
- **`docker compose restart` does not re-read `.env`** — always use `docker compose up -d` to pick up env file changes.
- **`WORDPRESS_CONFIG_EXTRA` is `eval()`d at runtime** — it does not appear as literal text in `wp-config.php`; that is expected behavior in newer WordPress images.
- **Newer WordPress images use `getenv_docker()` in wp-config.php** — env vars like `WORDPRESS_TABLE_PREFIX` are read dynamically at runtime, not substituted as static values. `wp-config.php` will show `getenv_docker('WORDPRESS_TABLE_PREFIX', 'wp_')` — this is correct.
- **Migrated sites: verify DB table prefix** — the `wp_table_prefix` in the site var file must match the prefix actually used in the existing database, not assumed to be the default `wp_`.
- **Migrated sites: rsync wp-content from old server before going live** — the bind-mounted `wp-content` directory on the new server starts empty. Active theme, plugins, and uploads must be copied: `rsync -avz --chown=33:33 user@oldserver:/path/to/wp-content/ /opt/sites/<site>/wp-content/`. Verify no nested `wp-content/wp-content/` directory is created.

## Key decisions made during this session

- **No per-site flat var files** — each site is a named dict in its own var file, assembled into lists in site.yml
- **nginx sidecar required for WordPress FPM** — the official `wordpress:*-fpm` image does not speak HTTP; nginx handles that layer
- **Socket proxy instead of raw Docker socket mount** — nginx rewrites the API version path; more secure and works around the SDK version mismatch
- **Handlers removed** — `item` is undefined in handler context when `include_role` is used in a task-level loop; `recreate: always` on the Start task is the reliable alternative
- **`apply: tags`** on `include_role` is required for `--tags <role>` to execute tasks inside the role
