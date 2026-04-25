# ADR 0001: No database containers; all sites use DO Managed clusters

**Status:** accepted
**Date:** 2026-04-24

## Context

BitSalt sites run several stacks (WordPress, Laravel, Node.js, FastAPI), each requiring a relational database. The natural-default approach in Docker Compose is to run a per-site database container alongside the app container. We have to choose whether databases run on the Droplet (in containers) or on a managed service.

Constraints:
- Single Droplet design (4–8 GB RAM); database memory contention with app containers under load is a real risk.
- Backups, upgrades, replication, and tuning consume operator time disproportionate to feature work.
- Multiple DB engine flavors are needed (MySQL for WordPress/Laravel, PostgreSQL for webapps).

## Decision

All databases run on **DigitalOcean Managed clusters** (Managed MySQL for WordPress / Laravel; Managed PostgreSQL for Node.js / FastAPI). No database containers run on the Droplet. App containers connect over the network using credentials sourced from the Ansible Vault.

## Consequences

**Easier:**
- Backups, point-in-time recovery, and replicas are DO's responsibility.
- Droplet RAM is reserved for application workloads; no DB working-set contention.
- Engine version upgrades are handled in the DO dashboard with documented downtime windows.
- Per-cluster trusted-sources gating provides a security layer beyond app credentials.

**Harder:**
- Cost: a Managed cluster has a non-trivial monthly floor vs. a free DB container. Acceptable at current scale.
- Network egress and SSL configuration become per-site setup steps. WordPress in particular requires `MYSQL_CLIENT_FLAGS=MYSQLI_CLIENT_SSL` in `.env`; the Droplet IP must be in the cluster's trusted-sources list. Both are documented gotchas (`status.md`).
- The WP FPM container's network must NOT have `internal: true`, which would cut external DNS to the Managed cluster (`status.md` lesson).

**Reconsider if:**
- Multi-Droplet or HA design is adopted (would change the calculus on shared vs. per-instance DBs).
- A new stack appears that needs a database engine DO doesn't offer as a Managed service (would need a per-case ADR).

## Alternatives considered

- **Per-site DB containers on the Droplet.** Cheaper and self-contained, but introduces backup / replication / upgrade burden, contends with app workloads for RAM, and complicates each site's compose file. Rejected.
- **A single shared DB container per engine on the Droplet.** Same drawbacks as above plus blast radius (one DB outage takes all sites down) and tenant-isolation concerns. Rejected.
- **Self-hosted MySQL/PostgreSQL VM separate from the Droplet.** Solves contention but reintroduces backup/upgrade/replication burden. Effectively a worse Managed cluster. Rejected.
