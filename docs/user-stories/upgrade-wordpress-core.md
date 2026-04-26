# Upgrade WordPress core (per-site and fleet-wide)

**As Jeff (operator),** I want to upgrade WordPress core to a newer version on a per-site basis, with the ability to roll out across the fleet site-by-site over hours or days, so that sites can run different core versions concurrently during the rollout window without stepping on each other.

## Acceptance criteria

### Per-site upgrade (the primitive)

1. Upgrading one site is a single edit: change the `wp_image` value (or equivalent override field) in that site's var file under `playbooks/vars/sites/<site>.yml` to the new pinned image tag (e.g., `wordpress:6.9.4-php8.2-fpm` → `wordpress:6.10.0-php8.2-fpm`).
2. Running `ansible-playbook site.yml --ask-vault-pass --tags wordpress --extra-vars "node_site_filter=<site>"` (or the equivalent per-site filter the role supports) upgrades only that site. Other sites' tasks are skipped, not re-run.
3. The container is recreated with the new image (`recreate: auto` detects the image change). Existing bind-mounted `wp-content/` is preserved across the recreate.
4. WordPress's own DB schema migration runs on the first request after the upgrade (visiting `/wp-admin/upgrade.php` or any admin page triggers it). The runbook documents how to trigger it explicitly via WP-CLI to avoid waiting for organic traffic:
   ```bash
   docker run --rm \
     --user www-data \
     --volumes-from <site>-wordpress-1 \
     --network container:<site>-wordpress-1 \
     --env-file /opt/sites/<site>/.env \
     wordpress:cli-php8.2 \
     wp core update-db --path=/var/www/html
   ```
5. After upgrade: site loads at its domain over HTTPS; admin login works; a smoke check of one or two key pages confirms front-end rendering. If anything is wrong, the rollback path (criterion 9) restores the previous version.

### Concurrent-version fleet state

6. Sites can run different `wp_image` values simultaneously without breakage. Each site has its own DB on DO Managed MySQL, its own `wp-content/`, its own container. There is no shared WordPress state at runtime that requires fleet-wide version uniformity.
7. The shared `wordpress_default_image` variable (per `status.md`) is the version sites pick up when they don't override. Sites that need to *lag* the fleet upgrade (e.g., a site with a known-incompatible plugin) override `wp_image` in their own var file *before* the default is bumped. Sites that need to *lead* override on their var file too. Both directions are first-class.
8. The runbook for rollout sequences the work: upgrade one or two low-risk sites first; verify; if good, bump `wordpress_default_image` to roll the rest of the fleet; sites with overrides remain on their pinned versions until updated individually.

### Rollback

9. Reverting a site to the previous core version is the same operation in reverse: change `wp_image` back to the prior tag and rerun. Rollback succeeds *only* if the DB schema migration from criterion 4 has not introduced backwards-incompatible changes (rare in WP point releases; possible across majors). The runbook calls out: for major-version rollbacks, restore from a pre-upgrade DB backup rather than just reverting the image.

### Pre-upgrade checks

10. Before running, the runbook requires:
    - A current backup exists (per `add-daily-backups.md` — and if backups are not yet implemented, take a manual `mysqldump` and tar of `wp-content/` first).
    - Plugin and theme compatibility against the target WP version is verified (release notes, plugin pages, or a test on a staging site).
    - Maintenance window is communicated to the site owner where applicable.
    - For point releases, a low-traffic window is preferred but not required. For major releases, schedule a maintenance window.
11. After running, the runbook requires:
    - Smoke test (front page, one inner page, admin login).
    - DB schema migration confirmed via WP-CLI (`wp core update-db`).
    - Logs (FPM + nginx + Traefik for that site) checked for errors over the next 30 minutes of traffic.

## Notes / edge cases

- The `wordpress:cli-php8.2` image used for WP-CLI must match (or be compatible with) the running site's PHP version. If a site moves from PHP 8.2 to 8.3 as part of the upgrade, the WP-CLI image tag must change in tandem.
- Sites that depend on `WORDPRESS_CONFIG_EXTRA` for things like the SSL flag (`MYSQLI_CLIENT_SSL`) must keep that variable across upgrades — it lives in `.env`, which is rendered fresh by Ansible from the vault, so this is preserved automatically as long as the vault entry is intact.
- Plugin updates and core updates should not be combined into a single change. Plugins update via `update-wordpress-plugins.md`; core updates via this story. Combining them makes triage harder when something breaks.
- Across major WP versions, `wp-content/uploads/` and `wp-content/plugins/` may need permission re-verification (uid 33). The `wordpress` role's `chown -R 33:33` task already handles this; verify on first major-version upgrade.
- Multi-version-concurrent state should not last *indefinitely*. The longer some sites lag, the more compatibility surface accumulates. The runbook should set an expected upper bound (e.g., "no site lags the default by more than two minor releases without an explicit ADR").
- The migration of remaining ~11 client sites (per `migrate-existing-wordpress-site.md`) is independent of this story; migrated sites simply land on whatever `wordpress_default_image` they pick up at migration time, and join the rollout cadence from there.
