# Migrate an existing WordPress site to the Droplet

**As Jeff (operator),** I want to migrate an existing WordPress site from another host to the Droplet without losing content, breaking active themes/plugins, or causing extended downtime, so that the migration of the remaining ~11 client sites is mechanical and low-risk.

## Acceptance criteria

1. Pre-cutover checklist (documented in `docs/runbooks/migrate-wordpress.md`):
   - DNS TTL on the existing site is reduced to a low value (e.g., 300s) at least one TTL window before cutover.
   - Source server access (SSH or equivalent) is confirmed.
   - DO Managed MySQL has a database created for the site; credentials are in the vault.
   - The Droplet's IP is added to the DO Managed MySQL trusted-sources list.
2. Add the site to this project per `add-wordpress-site.md` with `enabled: false` initially.
3. Database migration: dump the source DB, import to DO Managed MySQL. Verify the actual `wp_table_prefix` matches the value in the site var file before going live (this has bitten us before — see `status.md` lessons learned).
4. Content migration: rsync the source `wp-content/` to `/opt/sites/<site>/wp-content/` with correct ownership:
   ```bash
   rsync -avz --chown=33:33 user@oldserver:/path/to/wp-content/ /opt/sites/<site>/wp-content/
   ```
   Verify no nested `wp-content/wp-content/` directory was created.
5. Flip `enabled: true`, run `--tags wordpress`, verify the site loads at the configured domain (using a local hosts-file override before DNS cutover to test against the Droplet directly).
6. Cutover: change DNS A record to the Droplet IP. Monitor; verify SSL cert issues automatically via Traefik.
7. Post-cutover: confirm the site is reachable globally; raise DNS TTL back to its previous value; document any site-specific quirks in the runbook.

## Notes / edge cases

- Active theme + plugin set must be present in the rsync'd `wp-content`. Do not assume default theme/plugins on the destination — copy whatever was running on the source.
- If the source site uses a non-default DB charset/collation, the target must match, or `wp-config.php` will need explicit overrides.
- Sites that depend on hardcoded server paths (e.g., a plugin storing absolute paths) may need search-replace via `wp search-replace` after import.
- For larger sites, prefer maintenance mode on the source during the dump → import → rsync window to avoid a small content-drift window.
- The migration of remaining ~11 client sites is paced one at a time per `status.md` "Remaining sites (migration)" — do not batch.
