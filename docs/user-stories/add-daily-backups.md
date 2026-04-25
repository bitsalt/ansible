# Daily backups to DO Spaces

**As Jeff (operator),** I want all hosted sites' databases and content backed up daily to DO Spaces with documented retention, so that any single-Droplet failure or accidental destructive change can be recovered from within the documented retention window.

> **Status:** Not yet implemented. This story drives FR9 in `requirements.md`.

## Acceptance criteria

1. A new Ansible role (proposed: `roles/backup/`) installs and configures a daily backup cron on the Droplet.
2. The cron produces, for each enabled site:
   - A `mysqldump` of the site's DO Managed MySQL database (WordPress / Laravel sites).
   - A `pg_dump` of the site's DO Managed PostgreSQL database (webapp sites).
   - A tarball of the site's bind-mounted content directory (`wp-content/` for WordPress; equivalent for other stacks where applicable).
3. Backup artifacts are copied to a configured DO Spaces bucket with one prefix per site and per date.
4. Local retention: 14 days under `/opt/backups/<site>/`.
5. Spaces retention: 90 days, enforced via Spaces lifecycle policy or the cron itself (decide via ADR).
6. DB credentials and DO Spaces credentials are read from the vault. Tasks rendering or using these values carry `no_log: true`.
7. A separate, documented restore procedure exercises a full restore of one site from a recent backup into a staging environment as part of acceptance — backups that have not been restored are not real backups.
8. Cron output is logged; failures are visible (email, Slack, or at minimum a log file with rotation that an operator checks).

## Notes / edge cases

- Use DO Spaces' S3-compatible API. `s3cmd` or `awscli` with appropriate config; pin the version chosen.
- Backup artifacts should not include rendered secrets (e.g., dump should not capture `WP_AUTH_KEY` env vars from the running container). DB-only dumps should be naturally clean of these; verify.
- Concurrency: stagger per-site backup start times to avoid simultaneous DB load on the Managed MySQL cluster.
- Consider whether to back up the encrypted vault itself somewhere off-Droplet. The vault lives in the git repo, but loss of the git repo + Droplet simultaneously would be unrecoverable. Out of scope for this story; raise as a separate ADR.
- Restore-test cadence (quarterly?) should be documented and scheduled — not part of this story but should be a follow-up sprint task once backups land.
