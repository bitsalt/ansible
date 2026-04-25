# Update WordPress plugins and themes

**As Jeff (operator),** I want to run plugin and theme updates against any WordPress site on the Droplet from the command line without exec'ing into the FPM container, so that updates are scriptable, repeatable, and don't depend on logging into wp-admin.

## Acceptance criteria

1. A documented one-liner using the `wordpress:cli-php8.2` image updates all plugins on a given site:
   ```bash
   docker run --rm \
     --user www-data \
     --volumes-from <site>-wordpress-1 \
     --network container:<site>-wordpress-1 \
     --env-file /opt/sites/<site>/.env \
     wordpress:cli-php8.2 \
     wp plugin update --all --path=/var/www/html
   ```
2. The same pattern works for theme updates (`wp theme update --all`) and for individual plugins (`wp plugin update <slug>`).
3. WordPress core updates do *not* use WP-CLI; they happen by bumping the image tag in the site's var file and rerunning `--tags wordpress`. See `upgrade-wordpress-core.md` for the full per-site and fleet-wide upgrade procedure. The runbook makes this distinction explicit.
4. After a successful plugin update, the bind-mounted `wp-content/plugins/` on the host reflects the new version; restoring from a backup will preserve the update state.
5. The runbook for this operation lives at `docs/runbooks/wordpress-updates.md` (DevOps-owned) and is the single source of truth.

## Notes / edge cases

- The FPM-flavored WordPress images do *not* include `wp` — that is why `wordpress:cli-php8.2` is run as a separate one-shot container with `--volumes-from` and `--network container:` to share the running site's context.
- `WORDPRESS_CONFIG_EXTRA` is `eval`'d at runtime in newer WP images; it does not appear as literal text in `wp-config.php`. This is correct behavior; do not assume a missing config means the env-var didn't apply.
- Plugin update activity that bumps DB schema must be verified against the DO Managed MySQL connection — the WP container's network must not be `internal: true`, or external DNS (and therefore DB connectivity) breaks.
- Operators should read the plugin's release notes before running across all sites; some plugins ship migrations that need a backup-first sequence.
