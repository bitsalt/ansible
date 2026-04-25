# Onboarding

End-to-end onboarding for a new operator joining bitsalt-ansible. Audience: someone with general DevOps / Ansible experience but zero context on this specific project. If you've been around the project for a while and just need to set up a new control node, [getting-started.md](getting-started.md) is the faster path.

---

## What this project is

bitsalt-ansible provisions a single DigitalOcean Droplet that hosts BitSalt's portfolio of client and internal sites. WordPress and Laravel sites talk to a DO Managed MySQL cluster; Node.js and FastAPI sites talk to a DO Managed PostgreSQL cluster. A shared Traefik reverse proxy fronts every site, terminates TLS via Let's Encrypt, and routes by domain using Docker labels. Ansible is the source of truth for what the Droplet should look like.

For the full system shape, read [architecture.md](architecture.md). For the *why* behind the non-obvious decisions, read the [ADRs](adr/).

---

## Mental model

A few mental hooks that will make the rest faster:

1. **Single Droplet, by design.** No multi-region, no HA. Out of scope. If a future scale requires it, that's a new ADR — don't try to fit it in.
2. **Databases are never in containers.** All DBs are DO Managed clusters. App containers connect over the network. ([ADR 0001](adr/0001-no-db-containers.md).)
3. **Traefik routes by Docker label.** Adding a site means adding a container with the right labels. No editing nginx vhosts. ([ADR 0002](adr/0002-shared-traefik-proxy.md).)
4. **Per-site var file + named-dict pattern.** Each site has its own file under `playbooks/vars/sites/<site>.yml` defining a single named dict (e.g., `taotedev_site`). The dict is added to a stack-specific list in `site.yml`. `enabled: false` parks a site without removing it. ([ADR 0005](adr/0005-per-site-named-dict-vars.md).)
5. **All secrets are in the vault.** `playbooks/group_vars/all/vault.yml`, encrypted with `ansible-vault`. Tasks that render or accept vault values carry `no_log: true`. ([ADR 0004](adr/0004-ansible-vault-only-secret-store.md).)
6. **Webapp ownership boundary.** For Node.js / FastAPI sites, Ansible owns `.env` and the app repo owns `docker-compose.yml`. Don't reintroduce Ansible-templated compose for webapps. ([ADR 0006](adr/0006-webapp-ownership-boundary.md).)
7. **Bootstrap script does what Ansible can't safely do mid-play.** SSH hardening, UFW, Fail2ban, unattended-upgrades all happen in `bootstrap.sh` *before* Ansible runs. ([ADR 0007](adr/0007-pre-ansible-ssh-hardening.md).)
8. **Logging is cross-cutting and opt-in.** A single `logging` role deploys one Vector container that reads every other container's stdout/stderr via the Docker socket and ships to Grafana Cloud Loki. It's off by default (`logging_enabled: false`) so a fresh clone applies cleanly without Loki credentials; flip it on once `vault_logging_loki_endpoint`, `vault_logging_loki_user`, and `vault_logging_loki_token` are populated. Adding a site does not require touching the logging role. ([ADR 0008](adr/0008-centralized-logging-vector-loki.md), [NFR7](requirements.md#nfr7--observability-centralized-logging), [architecture § Logging](architecture.md#logging-cross-cutting); see also [getting-started.md § Logging is opt-in](getting-started.md#logging-is-opt-in).)

---

## Layout in one screen

```
bitsalt-ansible/
├── README.md                       Top-level entry point (read first)
├── bootstrap.sh                    First-boot Droplet hardening
├── requirements.txt                Pinned control-node tooling
├── status.md, docs/refactor.md     Pre-platform tracking, retained as cross-reference
├── .agent-context.md               Compact agent context (Claude Code)
├── .github/workflows/lint.yml      CI lint
├── docs/
│   ├── architecture.md             System architecture
│   ├── requirements.md             What the system must do
│   ├── bitsalt-ansible.md          Sprint file
│   ├── adr/                        Architectural Decision Records
│   ├── interfaces/                 Component / cross-team boundaries
│   ├── runbooks/                   Step-by-step procedures
│   ├── ops/                        Operational reference
│   ├── reference/                  Lookup-shaped docs (site inventory, etc.)
│   └── user-stories/               Per-capability stories
├── playbooks/                      Source of truth — current Ansible structure
│   ├── ansible.cfg, site.yml, requirements.yml
│   ├── inventory/hosts.yml
│   ├── group_vars/all/{vars,vault}.yml
│   ├── vars/sites/<site>.yml       One file per site (named-dict pattern)
│   └── roles/                      common, docker, traefik, wordpress, laravel, webapp, logging
└── v1/                             Legacy structure, retained for reference
```

---

## Set up your control node

Follow [getting-started.md](getting-started.md). It covers:

- Cloning the repo, virtualenv, pinned tooling, Galaxy collections.
- Verifying the inventory and SSH reachability to the Droplet.
- Validating vault access.
- A first dry-run with `--check --diff`.
- Local lint runs.

---

## What "active work" looks like

The single source of truth for in-flight work is the [sprint file](bitsalt-ansible.md). It contains:

- **Current sprint goal** — one sentence describing what done looks like this sprint.
- **Tasks** — active work and migration tasks with status (✅ / 🟡 / ⬜ / ❌).
- **Open Questions** — unresolved items waiting on decisions (other roles propose; PM lands).
- **Decisions log** — what was decided, when, and why (most recent first).
- **Carry-over Log** — items deferred to future sprints, each with a reactivation trigger.

Sprint cadence is 7 days. Sprint reviews happen at the end of each sprint per [`platform/pipelines/sprint-review.md`](../../platform/pipelines/sprint-review.md).

If you find yourself doing work that isn't on the sprint file, either land it (propose via Open Questions and PM moves it onto the active sprint) or push back on whoever asked you to do it.

---

## How to make changes

A small change (typo, lint fix, doc clarification): direct commit on a feature branch is fine.

Anything substantive (new role, new site, infra-shaped change):

1. Pick the role this falls under: BA / Architect / Security / QA / Designer / DevOps / Developer / Tech Writer / Content Writer / PM. (Most infra changes are DevOps.)
2. Read the role file at `~/projects/platform/.claude/agents/<role>.md` for the writes allowlist and stop conditions.
3. Make the change on a feature branch named `<role>/bitsalt-ansible/<slug>`.
4. Commit with a focused message. Don't push — Jeff pushes and opens PRs.
5. Update the sprint file's Open Questions or sprint task list as appropriate.

For the full pipeline shape (BA → Architect → Security → QA → Developer → PM with approval gates), see [`platform/pipelines/new-feature.md`](../../platform/pipelines/new-feature.md).

---

## Common operations

- **Add a WordPress site:** [runbooks/add-wordpress-site.md](runbooks/add-wordpress-site.md).
- **Add a webapp site:** [runbooks/add-webapp-site.md](runbooks/add-webapp-site.md).
- **Bootstrap a fresh Droplet:** [runbooks/bootstrap.md](runbooks/bootstrap.md).
- **Update WordPress plugins/themes:** [runbooks/wordpress-updates.md](runbooks/wordpress-updates.md).
- **Roll back a webapp deploy:** [runbooks/rollback.md](runbooks/rollback.md).
- **Edit the vault:** [runbooks/vault-edit.md](runbooks/vault-edit.md).

For ad-hoc Ansible operations (run commands, role loop pattern, secrets pattern, etc.) see [ops/ansible.md](ops/ansible.md).

---

## When to ask

Ask the existing operator (Jeff) when:

- You can't decrypt the vault (you don't have the password).
- You can't SSH to the Droplet (your key isn't registered).
- A change you want to make would modify a shared-infra concern across multiple sites or stacks (Traefik, Docker daemon, networks).
- The sprint file is silent on something the work seems to require.
- You hit a "this should work but it doesn't" situation that isn't covered in `status.md` lessons or the runbooks.

Don't ask before reading the relevant ADR, runbook, or `status.md` lesson — the answer is often there.

---

## What's deliberately out of scope

So you don't propose them as good ideas:

- Multi-region / HA / multi-Droplet design.
- In-container databases.
- A web UI for site administration (no Nginx Proxy Manager, Portainer, similar).
- CDN / WAF / DDoS mitigation beyond UFW + Fail2ban + Traefik.
- Email delivery infrastructure (per-app concern; uses Mailgun, SES, etc. via env vars).
- Application-level monitoring (per-app concern).
- Direct provisioning of DO resources via Terraform or DO API.

If a real need surfaces for any of these, raise it as a new ADR before building.
