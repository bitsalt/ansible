# Runbook: Add a WordPress site

Add a new WordPress site to the BitSalt fleet.

**User story:** [add-wordpress-site](../user-stories/add-wordpress-site.md)
**Related:** [architecture § Per-stack design notes](../architecture.md#per-stack-design-notes)

---

## Trigger

A new WordPress site is being added (greenfield) or migrated to the Droplet. For migrations of an existing site from another host, follow [migrate-wordpress.md](migrate-wordpress.md) (forthcoming) — this runbook covers greenfield only.

## Pre-checks

- [ ] DNS A record for the site domain points at the Droplet IP. Wait for propagation before running.
- [ ] DO Managed MySQL has a database created for the site, plus a user with full privileges on that DB.
- [ ] The Droplet IP is in the DO Managed MySQL cluster's trusted-sources list.
- [ ] You have the new site's DB password ready to add to the vault.
- [ ] You have decided the WP image tag (e.g., `wordpress:6.9.4-php8.2-fpm`) — usually the same as `wordpress_default_image` unless this site needs to lead or lag.

## Steps

### 1. Create the site var file

Copy `vars/sites/taotedev.yml` (or any existing WP site) to `vars/sites/<new-site>.yml`. Edit the named dict to match the new site:

```yaml
<site_var_name>:
  enabled: true
  site_name: <site-slug>
  site_domain: <site-domain>
  wp_image: "{{ wordpress_default_image }}"   # or pin a specific tag
  wp_db_host: <managed-mysql-host>
  wp_db_name: <db-name>
  wp_db_user: <db-user>
  wp_db_password: "{{ vault_<site>_db_password }}"
  wp_table_prefix: wp_
  www_redirect: true
```

The dict variable name (e.g., `taotedev_site`) must be unique per site. Use `<site>_site`.

### 2. Add the DB password to the vault

```bash
cd playbooks
ansible-vault edit group_vars/all/vault.yml
```

Add the new entry:

```yaml
vault_<site>_db_password: <password>
```

Save and close. The vault re-encrypts automatically.

### 3. Wire the site into `site.yml`

Edit `playbooks/site.yml`:

- Add the new site's var file to `vars_files`:
  ```yaml
  - vars/sites/<new-site>.yml
  ```
- Add the site dict to the `wordpress_sites` list:
  ```yaml
  wordpress_sites:
    - "{{ <site>_site }}"
  ```

### 4. Run Ansible

```bash
cd playbooks
ansible-playbook site.yml --ask-vault-pass --tags wordpress
```

The role provisions the site directory, renders `docker-compose.yml` and `.env`, and starts the FPM + nginx-sidecar containers.

### 5. Verify

- [ ] `docker ps` on the Droplet shows `<site>-wordpress-1` and `<site>-nginx-1` running.
- [ ] `https://<site-domain>/` loads with a valid Let's Encrypt cert (allow a few minutes for the cert challenge to complete).
- [ ] WordPress's setup wizard appears (or, for migrated DBs, the site loads as expected).
- [ ] `/opt/sites/<site>/` exists with `.env` at mode 0600 and the `wp-content/` bind mount owned uid 33.

### 6. Confirm idempotence

Re-run with the same tags:

```bash
ansible-playbook site.yml --ask-vault-pass --tags wordpress
```

Expected: `changed=0` for the new site.

## Rollback

If the site provisioned but is broken:
1. Set `enabled: false` in the site's var file.
2. Re-run `--tags wordpress`. The site is skipped on subsequent runs.
3. Manually `docker compose down` in `/opt/sites/<site>/` to stop the containers if needed.
4. Delete the site's DB password from the vault if you'll never re-attempt with the same name.

Full retirement (directory removal, vault entry pruning) is not yet automated — see [requirements.md](../requirements.md) FR8.

## Post-incident notes

Record any deviations here. Currently empty.

## Common gotchas (from `status.md` lessons)

- **`internal: true` cuts external DNS.** The WP FPM container's network must NOT have `internal: true` — that flag blocks all external routing including DNS resolution to DO Managed MySQL. Use `internal: <true|false>` per the network's purpose; the FPM↔nginx network is `internal` to isolate FPM, but FPM still needs to reach the proxy network for outbound DB DNS.
- **DO Managed MySQL requires SSL.** `WORDPRESS_CONFIG_EXTRA=define("MYSQL_CLIENT_FLAGS", MYSQLI_CLIENT_SSL);` must be in `.env` (double quotes). Already templated by the role from vault values.
- **`wp-content` ownership.** The bind-mounted directory must be `chown -R 33:33`. The role's task uses `owner: "33"` with `recurse: true`.
- **`wp_table_prefix` for migrated sites.** Default is `wp_`. Migrated sites must verify the actual prefix used in the source DB before pointing at the Managed cluster.
