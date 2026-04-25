# Runbook: WordPress plugin and theme updates

Update WordPress plugins and themes on a deployed site via WP-CLI. Core updates are handled by [wordpress-core-upgrade.md](wordpress-core-upgrade.md) (forthcoming) — image tag bump, not WP-CLI.

**User story:** [update-wordpress-plugins](../user-stories/update-wordpress-plugins.md)

---

## Trigger

Plugin or theme updates are available on a WordPress site, or a known security update needs to land. Routine cadence is operator's call; security-flagged updates take priority.

## Pre-checks

- [ ] A current backup exists (per FR9 / [add-daily-backups](../user-stories/add-daily-backups.md) — until backups are automated, take a manual `mysqldump` and a tar of `wp-content/` first).
- [ ] You have read the plugin's release notes for any plugin that ships DB migrations.
- [ ] The site is on a recent enough WP core version to be compatible with the target plugin/theme version. If not, run [wordpress-core-upgrade.md](wordpress-core-upgrade.md) first.
- [ ] You're SSHed into the Droplet as `bitsalt`.

## Steps

### 1. Identify the running container

```bash
docker ps --filter "name=<site>-wordpress-1" --format "{{.Names}}"
```

If nothing returns, the site is not running. Stop and investigate.

### 2. Update all plugins (most common case)

```bash
docker run --rm \
  --user www-data \
  --volumes-from <site>-wordpress-1 \
  --network container:<site>-wordpress-1 \
  --env-file /opt/sites/<site>/.env \
  wordpress:cli-php8.2 \
  wp plugin update --all --path=/var/www/html
```

Output lists each plugin updated with old → new version.

### 3. Update a specific plugin

```bash
docker run --rm \
  --user www-data \
  --volumes-from <site>-wordpress-1 \
  --network container:<site>-wordpress-1 \
  --env-file /opt/sites/<site>/.env \
  wordpress:cli-php8.2 \
  wp plugin update <plugin-slug> --path=/var/www/html
```

### 4. Update themes

Same pattern, swap `plugin` for `theme`:

```bash
docker run --rm \
  --user www-data \
  --volumes-from <site>-wordpress-1 \
  --network container:<site>-wordpress-1 \
  --env-file /opt/sites/<site>/.env \
  wordpress:cli-php8.2 \
  wp theme update --all --path=/var/www/html
```

### 5. Run pending DB migrations (if a plugin shipped one)

```bash
docker run --rm \
  --user www-data \
  --volumes-from <site>-wordpress-1 \
  --network container:<site>-wordpress-1 \
  --env-file /opt/sites/<site>/.env \
  wordpress:cli-php8.2 \
  wp core update-db --path=/var/www/html
```

### 6. Verify

- [ ] `https://<site-domain>/` loads, no obvious breakage on the homepage.
- [ ] One or two key inner pages render correctly.
- [ ] If the plugin is admin-facing, log in to `/wp-admin/` and confirm the relevant area works.

## Rollback

WP-CLI does not have a built-in rollback. If a plugin update breaks the site:
1. **Quick path:** restore `wp-content/plugins/<plugin>/` from the pre-update backup; the previous version is back in place.
2. **DB-impacting updates:** restore the DB from the pre-update `mysqldump` *before* further changes, then revert plugin files.
3. If multiple plugins were updated and one is the culprit, deactivate them via WP-CLI (`wp plugin deactivate <slug>`) one at a time to isolate.

## Post-incident notes

Record any deviations here. Currently empty.

## Common gotchas (from `status.md` lessons)

- **The FPM image lacks `wp`.** That's why we run `wordpress:cli-php8.2` as a separate one-shot container — the `--volumes-from` and `--network container:` flags share the running site's context.
- **The cli image PHP version must match the running site.** If a site moves from PHP 8.2 to 8.3, the WP-CLI image tag must change in tandem. Track this when planning a core upgrade.
- **`docker compose restart` does not re-read `.env`.** After any Ansible-driven `.env` change, use `docker compose up -d` to pick up new values, not `restart`.
- **`WORDPRESS_CONFIG_EXTRA` is `eval()`d at runtime.** It does not appear as literal text in `wp-config.php`. That is correct behavior in newer WP images.
- **`getenv_docker()` in wp-config.php.** Newer WP images read env vars dynamically at runtime via `getenv_docker()`. `wp-config.php` will show calls like `getenv_docker('WORDPRESS_TABLE_PREFIX', 'wp_')` — this is correct, not stale config.

## Related

- [wordpress-core-upgrade.md](wordpress-core-upgrade.md) — for WP core version bumps (image-tag based, not WP-CLI).
- [add-daily-backups](../user-stories/add-daily-backups.md) — backups should always exist before an update.
