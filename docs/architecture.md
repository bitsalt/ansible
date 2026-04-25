# bitsalt-ansible — Architecture

How the BitSalt site-hosting infrastructure is structured. Non-obvious decisions live in `docs/adr/`; component boundaries live in `docs/interfaces/`. This document is the entry point that ties them together.

---

## Overview

A single DigitalOcean Droplet hosts multiple web sites across several stacks (WordPress, Laravel, Node.js, FastAPI). A shared Traefik reverse proxy fronts every site, terminates TLS via Let's Encrypt, and routes by domain using Docker labels. All databases run on DO Managed clusters — never in containers. All secrets live in an Ansible Vault file. Per-app CI/CD pipelines build and push images to Docker Hub, then SSH into the Droplet as a narrowly-scoped `deploy` user to bring containers up.

The Ansible repo is the source of truth for what the Droplet should look like. Per-site var files describe each site as a named dict; site lists in `site.yml` drive the role loops. The repo conforms to the general coding standards (`~/projects/coding-standards/coding-standards.md`) and the Ansible addendum (`coding-standards-ansible.md`).

---

## Hosting

| Component | Provider / shape |
|---|---|
| Compute | DigitalOcean Droplet, single instance, 4–8 GB RAM (Ubuntu 24.04 LTS) |
| Reverse proxy | Traefik v3.3 in a shared container stack at `/opt/proxy/` |
| MySQL | DO Managed MySQL cluster (WordPress + Laravel) |
| PostgreSQL | DO Managed PostgreSQL cluster (Node.js + FastAPI) |
| Container registry | Docker Hub (see [ADR 0003](adr/0003-docker-hub-registry.md)) |
| Object storage | DO Spaces (planned, for backups per FR9) |
| DNS | Manual records in DO DNS dashboard pointing at Droplet IP |

DO resources (Droplet, Managed clusters, Spaces, DNS) are provisioned manually in the dashboard; bitsalt-ansible operates against what's there. No Terraform or DO API automation today (out of scope per requirements.md).

Single-Droplet design is a deliberate scope constraint, not an architectural goal — multi-region or HA is out of scope absent an explicit ADR. See [requirements.md](requirements.md) "Out of scope."

---

## Server directory layout

```
/opt/
├── proxy/                          Traefik stack (compose, acme.json, socket-proxy.conf)
├── sites/                          One subdirectory per enabled site
│   ├── <wordpress-site>/
│   │   ├── docker-compose.yml      Templated by Ansible (wordpress role)
│   │   ├── .env                    Mode 0600, never committed, sourced from vault
│   │   └── wp-content/             Bind mount, owned uid 33 (www-data)
│   ├── <laravel-site>/
│   │   ├── docker-compose.yml      Templated by Ansible (laravel role)
│   │   ├── .env
│   │   └── storage/                Bind mount
│   └── <webapp-site>/              Node.js / FastAPI / similar
│       ├── docker-compose.yml      Owned by app repo, NOT Ansible (see ADR 0006)
│       └── .env                    Owned by Ansible, sourced from vault
├── backups/                        Local backup spool (FR9, planned)
└── scripts/                        One-off operational scripts
```

Per-site directories are created lazily by the relevant role on first run for that site.

---

## Networking

- **Shared `proxy` Docker network** (external). All site containers join it; Traefik routes via labels.
- **Per-site internal networks** for sensitive interconnects. WordPress in particular uses an `internal` network between FPM and the nginx sidecar, *not* a fully-isolated `internal: true` (which would block external DNS to DO Managed MySQL — see lessons in `status.md`).
- **Docker socket proxy** (nginx:alpine) sits in front of `/var/run/docker.sock` to expose the Docker API to Traefik with API-version path rewriting. Not a raw socket mount. Rationale lives as a design note here rather than its own ADR; revisit if scope grows.
  - Background: Traefik v3.3's Docker SDK sends API version 1.24 to the daemon; the daemon's `MinAPIVersion` is 1.40. The proxy rewrites `/v1.24/` → `/v1.41/` so calls succeed.
  - Security: the proxy can be hardened to allow only the read-only Docker endpoints Traefik needs (services, containers list). Future hardening — capture as a follow-up.
- **Traefik handles SSL** via Let's Encrypt + ACME, storing `acme.json` at `/opt/proxy/acme.json`.
- **UFW** denies all inbound except SSH (configured non-default port, default 2222), 80, 443. **Fail2ban** active on SSH.

---

## Ansible structure

Two parallel structures coexist during the in-progress refactor:
- `playbooks/` — current structure. All new work lands here. This is the source of truth.
- `v1/` — legacy structure, retained for reference until the refactor is fully validated and the `playbooks/` structure has been applied to all sites without regression.

Within `playbooks/`:

```
playbooks/
├── ansible.cfg
├── site.yml                        Top-level orchestrator
├── requirements.yml                Galaxy collections (community.docker pinned)
├── inventory/
│   └── hosts.yml                   Single host: droplet, ansible user, custom SSH port
├── group_vars/all/
│   ├── vars.yml                    Non-sensitive globals
│   └── vault.yml                   Encrypted with ansible-vault (ADR 0004)
├── vars/sites/
│   └── <site>.yml                  One file per site, named-dict pattern (ADR 0005)
└── roles/
    ├── common/                     Base packages, /opt/* directory structure
    ├── docker/                     Docker Engine, compose plugin, proxy network, Docker Hub login
    ├── traefik/                    Traefik stack + socket proxy, acme.json
    ├── wordpress/                  Looped via site.yml; per-site WP + nginx-sidecar
    ├── laravel/                    Single-site (currently); queue worker toggle, scheduler cron
    └── webapp/                     Looped via site.yml; generic single-port HTTP role
```

Every role declares `meta/argument_specs.yml` and `defaults/main.yml` (Ansible addendum §5/§14). Every task that renders or accepts a vault value carries `no_log: true` (addendum §7/§8).

The `site.yml` file uses `tasks: include_role` with `apply: tags`, not `roles:`, so `--tags <role>` correctly executes tasks inside the role (this is non-obvious — captured in `status.md` lessons learned).

---

## Per-stack design notes

### WordPress

Each WordPress site runs three containers:
- **WordPress FPM** (`wordpress:<version>-php<X>-fpm`) — the FPM-only image flavor; does *not* speak HTTP.
- **nginx sidecar** (`nginx:alpine`) — handles HTTP, proxies PHP requests to FPM on port 9000, carries the Traefik labels.
- *(shared)* **Traefik** routes HTTP/S to the nginx sidecar.

The FPM-only image flavor is intentional — it gives us PHP version control without nginx baked in. The sidecar is necessary because that image doesn't serve HTTP; this is a design note, captured here rather than as a separate ADR. Volumes:
- `wordpress_data` named volume shared between FPM and nginx.
- `wp-content/` bind-mounted from `/opt/sites/<site>/wp-content/`, owned uid 33.

DB connections target DO Managed MySQL with SSL: `WORDPRESS_CONFIG_EXTRA=define("MYSQL_CLIENT_FLAGS", MYSQLI_CLIENT_SSL);` in `.env` (double-quoted; single quotes are rejected by the WP entrypoint per `status.md`).

### Laravel

Single-site role currently. One container per site, queue worker toggleable, scheduler cron optional. DB connection to DO Managed MySQL.

### Webapp (Node.js / FastAPI / similar)

Generic role for single-port HTTP apps backed by DO Managed PostgreSQL. **Ansible owns `.env`; the app repo owns `docker-compose.yml`.** This is the webapp ownership boundary — see [ADR 0006](adr/0006-webapp-ownership-boundary.md). Stat-gates on the compose file existing so a fresh site bootstraps cleanly when the app repo's deploy lands compose later.

If a future webapp needs structural deviation (sidecar worker, bind mount, non-HTTP entrypoint), split a new role at that point rather than over-generalizing `webapp`.

---

## Component boundaries

The most consequential cross-team boundary is **app-repo CI/CD ↔ the Droplet**, where an app repo's GitHub Actions pipeline reaches into the bitsalt-ansible-managed environment. The contract is specified at:

- [`docs/interfaces/ci-deploy.md`](interfaces/ci-deploy.md)

Other boundaries (Ansible ↔ Droplet over SSH; site container ↔ Traefik labels; site container ↔ Managed DB) are governed by Ansible-templated configuration and the role files themselves; explicit interface specs may be authored if and when they're consumed by another role or repo.

---

## Architectural decisions

| ADR | Title |
|---|---|
| [0001](adr/0001-no-db-containers.md) | No database containers; all sites use DO Managed clusters |
| [0002](adr/0002-shared-traefik-proxy.md) | Shared Traefik reverse proxy, not per-site or alternative tools |
| [0003](adr/0003-docker-hub-registry.md) | Docker Hub as image registry |
| [0004](adr/0004-ansible-vault-only-secret-store.md) | Ansible Vault is the only secret store |
| [0005](adr/0005-per-site-named-dict-vars.md) | Per-site var file using the named-dict pattern |
| [0006](adr/0006-webapp-ownership-boundary.md) | Webapp ownership boundary: Ansible owns `.env`, app repo owns `docker-compose.yml` |
| [0007](adr/0007-pre-ansible-ssh-hardening.md) | Bootstrap script handles SSH hardening before Ansible runs |

---

## Standards and conformance

- General coding standards: `~/projects/coding-standards/coding-standards.md`.
- Ansible addendum: `~/projects/coding-standards/coding-standards-ansible.md`. Conformance status tracked in `docs/refactor.md` (Tasks A1–A4); A1–A3 complete, A4 complete with an explicit-rationale exception for the Traefik handler.
- Per-stack PHP / framework / language standards apply per-app where relevant; out of scope for this infra repo.
