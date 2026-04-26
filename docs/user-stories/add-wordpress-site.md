# Add a WordPress site

**As Jeff (operator),** I want to add a new WordPress site to the fleet by creating one var file and editing the vault, so that adding a site does not require touching role internals or copying boilerplate compose files.

## Acceptance criteria

1. Adding a new WordPress site requires three edits: copy a template var file under `playbooks/vars/sites/<new-site>.yml` and fill in values; add the corresponding `vault_<new-site>_db_password` (or equivalent) to `playbooks/group_vars/all/vault.yml`; add the new site dict to the `wordpress_sites` list in `site.yml`.
2. Running `ansible-playbook site.yml --ask-vault-pass --tags wordpress` provisions the new site without affecting any existing site (other sites' tasks are skipped, not re-run).
3. After provisioning: `/opt/sites/<new-site>/` exists with `docker-compose.yml` (templated), `.env` at mode 0600, and a bind-mounted `wp-content/` directory with correct ownership (`uid 33`, recursive where needed).
4. After provisioning: a WordPress FPM container, an nginx sidecar container, and Traefik routing are all running. The new site is reachable over HTTPS via Let's Encrypt within a few minutes (DNS must already point at the Droplet).
5. The site's database connection uses DO Managed MySQL with the `MYSQL_CLIENT_FLAGS=MYSQLI_CLIENT_SSL` extra config, sourced from the vault.
6. Setting `enabled: false` in the site var file and re-running `--tags wordpress` skips the site without removing its config.
7. Argument-spec validation (per coding-standards-ansible §5/§14) refuses to provision the site if any required field is missing from the var file, with a clear error.

## Notes / edge cases

- New site DNS must be pointed at the Droplet IP *before* running, or Let's Encrypt's challenge will fail. The runbook should explicitly call out this prerequisite.
- The Droplet's IP must be in the DO Managed MySQL trusted-sources list, or DB connections will be silently dropped.
- `wp_table_prefix` defaults to `wp_`. Migrated sites must verify the actual prefix used in the existing database (see `migrate-existing-wordpress-site.md`).
- A WordPress site can be removed by setting `enabled: false` and pruning the site dict from `site.yml`; full retirement (directory removal, vault entry pruning) is not yet automated — see FR8 in requirements.md.
