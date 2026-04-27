# ansible — Requirements

Requirements for the BitSalt site-hosting infrastructure. This document captures *what* the system must do; design decisions live in `docs/architecture.md` and `docs/adr/` (Architect-owned).

---

## Context

BitSalt Digital LLC hosts a portfolio of client and internal sites (WordPress, Laravel, Node.js, FastAPI) on a single DigitalOcean Droplet. Before this project, sites were managed individually with mixed conventions and no centralized provisioning. The goal is a single Ansible repo that:

- Stands up a fresh Droplet to a known, hardened baseline.
- Adds, configures, updates, and removes sites consistently across stack types.
- Treats secrets correctly (Ansible Vault for sensitive values, never in plain files).
- Routes all sites through a shared Traefik proxy with automatic Let's Encrypt SSL.
- Connects all WordPress / Laravel sites to DO Managed MySQL and Node.js / FastAPI sites to DO Managed PostgreSQL — no in-container databases.
- Coordinates with per-repo CI/CD for app sites that build their own images (Laravel, Node.js, FastAPI).

The system is currently in production for `taotedev.com`, with three other customer-facing sites (`bitsalt.com`, `frujo.net`, `mybusinessmagnet.tech`) staged or live and roughly eleven additional WordPress sites awaiting migration.

---

## Users / personas

- **Jeff (operator / admin).** Primary user. Adds and maintains sites, runs Ansible, edits the vault, executes one-off WP-CLI / runtime tasks via Bash on the Droplet, schedules and supervises maintenance windows.
- **Site visitors (indirect).** End users of the hosted sites. Not direct users of this project, but the system's correctness affects their experience (uptime, SSL, page load, content delivery).
- **GitHub Actions CI (machine).** Per-repo deploy pipelines for Laravel and Node.js / FastAPI sites SSH into the Droplet as the `deploy` user, pull updated images, and bring up containers. This project owns the environment those pipelines deploy into.

---

## Functional requirements

### FR1 — Droplet bootstrap

The system must bring a fresh Ubuntu 24.04 DO Droplet to a known baseline:
- Create `bitsalt` (admin, sudo NOPASSWD) and `ansible` (control-node, sudo NOPASSWD) users with their SSH keys.
- Disable root SSH login and password authentication; move SSH off port 22 to the configured port (default 2222).
- Configure UFW to deny all inbound except SSH port, 80, 443.
- Install and configure Fail2ban.
- Configure unattended security upgrades without auto-reboot.

### FR2 — Reverse proxy + SSL

The system must run a shared Traefik v3.x reverse proxy that:
- Routes all sites to their containers via Docker labels (no manual nginx config edits).
- Issues and renews Let's Encrypt SSL certificates automatically.
- Operates against the Docker daemon via a socket proxy, not a direct socket mount.
- Sources the ACME email and any other sensitive config from the Ansible Vault.

### FR3 — Site provisioning

The system must provision a site of any supported stack with a single command (`ansible-playbook site.yml --tags <stack>`):
- **WordPress** (`wordpress` role): FPM container + nginx sidecar; bind-mounted `wp-content`; Traefik labels; DO Managed MySQL connection with SSL.
- **Laravel** (`laravel` role): single container, queue worker toggle, scheduler cron, DO Managed MySQL.
- **Webapp** (`webapp` role): generic stateless-HTTP role for Node.js, FastAPI, and similar single-port HTTP apps backed by DO Managed PostgreSQL. Ansible owns the `.env` file; the app repo owns `docker-compose.yml`.

Each site:
- Has its own directory under `/opt/sites/<site>/` with a `.env` file at mode 0600.
- Joins the shared `proxy` network for Traefik routing.
- Is governed by a per-site var file under `playbooks/vars/sites/` using the named-dict pattern, with an `enabled:` flag to skip without removing.
- Renders all secrets from the Ansible Vault (no plaintext credentials in committed files).

### FR4 — Site updates

The system must support routine updates without full re-provisioning:
- **WordPress core:** bump image tag in the site var file and rerun `--tags wordpress`.
- **WordPress plugins / themes:** WP-CLI via the `wordpress:cli-php8.2` image, run from Bash as a one-off command (not Ansible).
- **Laravel:** image tag bump or per-repo CI deploy (which runs `php artisan migrate --force`).
- **Webapp:** per-repo CI deploy (`docker compose pull && up -d`), Ansible only re-runs to pick up `.env` changes.

### FR5 — Vault management

The system must keep all sensitive values in `playbooks/group_vars/all/vault.yml`:
- Encrypted with `ansible-vault`.
- Tasks that render or use vault values carry `no_log: true` per the Ansible coding-standards addendum §7/§8.
- Per-site DB passwords, Docker Hub credentials, ACME email, and similar sensitive values are referenced as `vault_*` (or, where naming is intentional, by site-prefixed names).

### FR6 — CI/CD coordination

The system must coexist with per-repo CI/CD for sites that build their own images:
- Provide a `deploy` user with narrow scope (no sudo, no shell beyond what compose deploys need).
- Document the GitHub Secrets required per app repo: `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DROPLET_HOST`, `DEPLOY_SSH_KEY`.
- Stat-gate the `webapp` role's container-start task on the compose file existing, so a new webapp site bootstraps cleanly when the app repo deploys compose later.

### FR7 — Idempotence + change visibility

The system must be safely idempotent:
- A second consecutive `ansible-playbook site.yml` run reports `changed=0`.
- `--check --diff` shows accurate before/after state (requires `community.docker` >= 3.10 for proper check-mode fidelity).
- `recreate: auto` is preferred over `recreate: always` so containers are only recreated when configuration actually changes.

### FR8 — Site retirement

The system must support removing a site cleanly:
- Set `enabled: false` in the site var file to skip the site without removing its config.
- (Future) Provide a `retire` workflow that removes the site directory, optionally backs up `wp-content`/`.env`, and revokes its Traefik routes.

### FR9 — Backup

The system must take regular database and content backups:
- Daily MySQL and PostgreSQL dumps shipped to DO Spaces.
- 14-day local retention; 90-day Spaces retention.
- WordPress `wp-content` directory included in the backup set.
- Restore procedure documented and tested.

> **Status:** *not yet implemented.* Currently a known gap (see `status.md` "Ansible / infrastructure"). Backup cron role must be authored.

### FR10 — Monitoring

The system must have basic Droplet monitoring:
- DO Monitoring agent installed.
- CPU / memory / disk alerts configured in the DO dashboard.
- (Future) Per-site uptime checks, ideally external to the Droplet.

> **Status:** *not yet implemented.* DO Monitoring agent installation deferred to manual configuration in the dashboard.

---

## Non-functional requirements

### NFR1 — Security

- All secrets in Ansible Vault. No `vault_*` value ever rendered to stdout (enforced via `no_log: true` on rendering tasks).
- SSH hardened: no root login, no password auth, custom port, key-only access.
- UFW deny-by-default with explicit port allowlist.
- Fail2ban active.
- Unattended security upgrades enabled (no auto-reboot).
- Per-site Docker networks isolate FPM / app containers from the public proxy network where applicable (e.g., WordPress `internal` network).

### NFR2 — Reproducibility

- The full Droplet state must be reproducible from a fresh Ubuntu 24.04 install plus this repo plus the encrypted vault, in a documented sequence (bootstrap.sh → ansible-playbook).
- Container base images and key Galaxy collections are pinned to a specific version (`requirements.yml`, `requirements.txt`).
- The repo passes `ansible-lint` (production profile) and `yamllint` in CI.

### NFR3 — Coding standards

- Conforms to the general coding standards (`~/projects/coding-standards/coding-standards.md`).
- Conforms to the Ansible addendum (`~/projects/coding-standards/coding-standards-ansible.md`):
  - Roles declare `meta/argument_specs.yml` and `defaults/main.yml`.
  - Tasks rendering or accepting vault values carry `no_log: true`.
  - `recreate: auto` (not `always`) on container-start tasks unless a documented reason requires otherwise.

### NFR4 — Maintainability

- Roles are loop-friendly: `wordpress`, `laravel`, and `webapp` accept a per-site dict via `item` and tolerate `--tags <role>` execution without skipping inner tasks.
- One var file per site, using the named-dict pattern; never flat global vars per site.
- Drift between repo and live is observable via `--check --diff`; a `--check --diff` baseline is regenerated as part of the routine apply workflow.

### NFR5 — Operational sustainability

- Common operations (add a site, update a plugin, restart Traefik, populate the vault) are documented in runbooks (DevOps-owned, under `docs/runbooks/`).
- Migration of an existing site from another host follows a documented checklist (rsync wp-content, table prefix verification, DNS cutover).

### NFR6 — Cost

- Single Droplet at 4–8 GB RAM is the operating envelope. Architectural decisions that would require multi-Droplet or paid container registries (vs. Docker Hub) are out of scope absent an explicit ADR.

### NFR7 — Observability (centralized logging)

The system must support centralized aggregation of container logs so that operational issues spanning multiple sites, or surviving past a container's local log rotation, are diagnosable without per-container `docker logs` SSH sessions.

- **Coverage.** Stdout/stderr from every site container on the Droplet is captured cross-cuttingly, without per-site wiring. Adding a site does not require touching the logging configuration.
- **Opt-in, default off.** The capability is off by default so a fresh clone of the repo applies cleanly before log-destination credentials are populated. Operators opt in explicitly once credentials exist in the vault.
- **Vault-sourced credentials.** Credentials for the log destination live only in the Ansible Vault. Missing credentials must fail loudly at role entry rather than producing a silently-misconfigured pipeline. Tokens carry `no_log: true` per NFR1 / FR5.
- **Multi-deployment separation.** A configurable deployment label is emitted on every stream so a single log-destination tenant can host prod, staging, and any future hosts without their streams colliding.
- **PII redaction backstop.** The shipping pipeline scrubs the most common credential / header leak patterns (e.g., `Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`) before egress. This is a defensive net, not the primary defense — apps remain responsible for not logging sensitive values upstream.
- **Implementation reference.** Currently realized by the `logging` role (Vector → Grafana Cloud Loki); design rationale and alternatives in [ADR 0008](adr/0008-centralized-logging-vector-loki.md). The requirement is destination-agnostic — a future change of shipper or sink is a config-level change, not a requirement change.

> **Status:** *implemented, default off.* Role landed 2026-04-24; opt-in by setting `logging_enabled: true` once vault carries the Loki values.

---

## Out of scope

- Multi-region or HA deployment. Single Droplet is the design.
- In-container databases. All sites use DO Managed MySQL or DO Managed PostgreSQL.
- A web UI for site administration (no Nginx Proxy Manager, Portainer, or similar). Operations happen via Ansible + SSH + Bash.
- CDN, WAF, or DDoS mitigation beyond what Traefik + UFW + Fail2ban provide.
- Email delivery infrastructure for hosted sites. Each app handles its own (e.g., Mailgun, SES) via env vars.
- Application-level monitoring (APM, error tracking). Out of scope for the infra repo; per-app concern.
- Compliance-grade or audit-grade logging (guaranteed delivery, regulatory retention, tamper-evident integrity). NFR7 is diagnostic-grade — log loss during a shipper outage or destination outage is acceptable. If contractual or regulatory requirements emerge, NFR7 must be revisited (see ADR 0008 "Reconsider if").
- Any direct provisioning of DO resources via Terraform or DO API. The Droplet, Managed DBs, Spaces buckets, and DNS records are provisioned manually in the DO dashboard. Bitsalt-ansible operates against what's there.

---

## Dependencies

- **DigitalOcean account** with: Droplet (Ubuntu 24.04), Managed MySQL cluster, Managed PostgreSQL cluster, Spaces bucket (for backups, when FR9 lands), DNS records pointing at the Droplet IP.
- **Docker Hub account** with credentials for image pulls and pushes (per-repo CI for app sites).
- **GitHub repo per app site** (Laravel / Node.js / FastAPI) with deploy workflows, plus Secrets configured per FR6.
- **Ansible 2.15+** on the control node. `community.docker` collection ≥ 3.10 (currently pinned to 5.2.0 in `requirements.yml`). `python3-docker` on the Droplet.
- **Ansible Vault password** delivered to the operator out-of-band (not committed).
- **Coding-standards repo** at `~/projects/coding-standards/` for the general standards and Ansible addendum.
