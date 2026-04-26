# ADR 0002: Shared Traefik reverse proxy

**Status:** accepted
**Date:** 2026-04-24

## Context

Multiple sites share a single Droplet on ports 80 and 443. We need a reverse proxy that:
- Routes traffic to the right container by domain.
- Issues and renews Let's Encrypt SSL certificates without manual operator action.
- Operates declaratively (no per-site config edits when adding a site).
- Survives container restarts and Droplet reboots cleanly.

## Decision

**Traefik v3.x runs as a single shared container stack at `/opt/proxy/`.** Site containers join the shared `proxy` Docker network and declare routing intent via Docker labels; Traefik watches the Docker socket (via a socket proxy — see Architecture § Networking) and configures itself. ACME (Let's Encrypt) state lives at `/opt/proxy/acme.json`.

## Consequences

**Easier:**
- Adding a site requires no proxy config edits — labels on the site's container are enough.
- SSL is automatic and renewed without operator intervention.
- All routing is declarative and self-documenting via container labels visible in `docker ps`.

**Harder:**
- Single point of failure: a Traefik restart briefly affects every site. Mitigated by `recreate: auto` (per Ansible addendum §4) so unnecessary restarts are avoided; planned restarts are scheduled in low-traffic windows. Customer-facing sites currently sharing this blast radius: `bitsalt.com`, `frujo.net`, `mybusinessmagnet.tech`, `taotedev.com` (live).
- Traefik version upgrades have surfaced compatibility issues (e.g., the v3.3 SDK API-version-mismatch with the daemon, requiring the socket proxy). Acceptable cost; the proxy itself is now stable.
- Acme.json is a single file that must be backed up; loss forces full cert reissue.

**Reconsider if:**
- Site count or traffic outgrows single-Droplet capacity (multi-Droplet would change routing topology).
- A site needs proxy features Traefik doesn't offer cleanly (e.g., heavy WAF rules — currently out of scope per requirements.md).

## Alternatives considered

- **Nginx Proxy Manager.** UI-driven; depends on a SQLite state file + admin web UI for configuration. Rejected: introduces a UI as a dependency for declarative work; harder to capture in version control; adds an admin attack surface.
- **Raw nginx with hand-written vhost files.** Most flexible, no daemon-API dependency. Rejected: per-site config edits don't fit the named-dict-driven Ansible approach; SSL automation requires bolting on certbot or equivalent.
- **Caddy.** Excellent automatic SSL story; declarative Caddyfile or labels. Rejected primarily because Traefik's Docker label model fit our compose-driven approach more naturally and the team had prior Traefik experience. Reasonable alternative if Traefik issues persist.
