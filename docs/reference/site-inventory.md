# Site inventory

Reference: which sites are configured in the repo, what stack each runs, and what database each connects to. Maintained by hand; cross-check against `playbooks/vars/sites/` when in doubt.

For the per-site var file conventions, see [ADR 0005](../adr/0005-per-site-named-dict-vars.md). For per-stack design notes, see [architecture.md § Per-stack design notes](../architecture.md#per-stack-design-notes).

---

## Configured sites

Sites with a var file at `playbooks/vars/sites/<site>.yml`. The `enabled` column reflects the typical state; check the file itself for the current value before acting.

| Site | Stack | Database engine | Image source | Status |
|---|---|---|---|---|
| taotedev | WordPress | DO Managed MySQL | Official `wordpress:*-php8.2-fpm` | **Live in production** |
| bitsalt | WordPress | DO Managed MySQL | Official `wordpress:*-php8.2-fpm` | Staged / live (customer-facing) |
| bitsalt-staging | WordPress | DO Managed MySQL | Official `wordpress:*-php8.2-fpm` | Staging |
| frujo | WordPress | DO Managed MySQL | Official `wordpress:*-php8.2-fpm` | Staged / live (customer-facing) |
| mybizmag | WordPress | DO Managed MySQL | Official `wordpress:*-php8.2-fpm` | Staged / live (customer-facing) |
| seaislandlife | WordPress | DO Managed MySQL | Official `wordpress:*-php8.2-fpm` | Staged |
| laravel-site | Laravel | DO Managed MySQL | Custom (Docker Hub: TBD; see status.md remaining work) | Placeholder — not yet enabled |
| node-site-1 | Node.js (webapp role) | DO Managed PostgreSQL | Custom (Docker Hub: TBD) | Placeholder — not yet enabled |

---

## Sites awaiting migration

Approximately 11 additional WordPress sites are awaiting migration from prior hosts. They do not yet have var files in this repo. The migration is paced one site at a time per the [migrate-existing-wordpress-site](../user-stories/migrate-existing-wordpress-site.md) user story.

Specific site names are intentionally not enumerated here — they are tracked in client-facing engagement records, not in this repo. Treat the count as authoritative; the names land in `vars/sites/` as each migration runs.

---

## Future / planned sites

| Site | Stack | Notes |
|---|---|---|
| node-site-2 | Node.js (webapp role) | Var file to be created by copying `node-site-1.yml` when needed; carry-over item in the sprint file. |
| Mobile API (FastAPI) | FastAPI (webapp role) | Mentioned in legacy CLAUDE.md as a planned site; no concrete plan yet. |

---

## Customer-facing site set (Traefik blast radius)

The Traefik proxy is shared across every site on the Droplet, so any Traefik restart momentarily affects them all. The currently customer-facing sites — those whose downtime is visible to non-BitSalt users — are:

- `bitsalt.com`
- `frujo.net`
- `mybusinessmagnet.tech`
- `taotedev.com`

These sites drive scheduling decisions for any Traefik-touching change (see sprint file Task B4).

---

## Image source conventions

- **WordPress** sites pull official `wordpress:*-php<X>-fpm` images from Docker Hub. Pinned per-site in the site var file's `wp_image` key, defaulting to `wordpress_default_image` from `group_vars/all/vars.yml` when not overridden. See [upgrade-wordpress-core](../user-stories/upgrade-wordpress-core.md) for upgrade procedure.
- **Laravel and webapp** sites pull custom images from BitSalt's Docker Hub account ([ADR 0003](../adr/0003-docker-hub-registry.md)). Each app repo's CI/CD builds and pushes the image; the image tag is pinned in the site var file (or set at deploy time by app-repo CI for webapp, per [ADR 0006](../adr/0006-webapp-ownership-boundary.md)).

---

## How to update this file

This file is reference material — it changes when the configured site list changes. Update entries when:

- A new site var file is added or an existing one is enabled / disabled.
- A site's stack changes (rare).
- A site is retired.
- A new site moves into the customer-facing set (or a customer-facing site is decommissioned).

Tech Writer is the writer; other roles propose via the sprint file's Open Questions table.
