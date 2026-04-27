# Interface: app-repo CI/CD ↔ Droplet deploy

The contract between an app repo's CI/CD pipeline (typically GitHub Actions) and the Droplet hosted by this `ansible` project. Applies to **webapp sites only** (Node.js, FastAPI, similar). WordPress and Laravel sites do not currently use this contract; their image-tag bumps happen via Ansible re-runs.

References: coding-standards `coding-standards.md` §14 (API / Interface Design); [ADR 0006](../adr/0006-webapp-ownership-boundary.md).

---

## Purpose

A site's CI/CD pipeline must be able to deploy a new version of the app without an Ansible run, while this project retains ownership of `.env` and the surrounding environment. This interface specifies what each side provides and what each side requires.

---

## Responsibilities

### ansible provides

- **`/opt/sites/<site>/`** directory with mode 0755, owned by the operator-equivalent user.
- **`/opt/sites/<site>/.env`** at mode 0600, rendered from the vault, regenerated on Ansible apply when vault values change.
- **The shared `proxy` Docker network** is up and Traefik is running. Site containers join `proxy` to be reachable.
- **The `deploy` user** on the Droplet, narrowly scoped: no sudo, login shell limited to what compose deploys need, SSH key-only authentication on the configured custom port.
- **Docker and the `community.docker` Python module** are installed; the daemon is running.
- **Outbound network access** to Docker Hub for image pulls and to the appropriate DO Managed PostgreSQL cluster for DB connections (Droplet IP added to the cluster's trusted-sources list).

### App repo CI/CD provides

- **A built and pushed image on Docker Hub** at a stable tag for that deploy (commit SHA preferred).
- **`/opt/sites/<site>/docker-compose.yml`** — the compose file is owned by the app repo, not by Ansible. The compose file must:
  - Reference the new image tag for that deploy.
  - Use `env_file: .env` to pick up Ansible-rendered config.
  - Join the `proxy` external network for Traefik routing.
  - Declare appropriate Traefik labels (router, service, certresolver) per the project's labeling convention.
- **A deploy step that `docker compose pull && up -d`** in `/opt/sites/<site>/`. SSHed in as the `deploy` user.
- **Idempotent deploys** — running the same SHA twice should be a no-op or a clean re-up, not a partial state.

---

## Inputs and outputs

### Input from CI to Droplet (per deploy)

| Field | Source | Notes |
|---|---|---|
| `image_tag` | App repo CI (commit SHA) | Substituted into `/opt/sites/<site>/docker-compose.yml`. |
| Compose file content | App repo CI | Whole file written; replaces prior version. |
| Deploy user SSH key | GitHub Secret `DEPLOY_SSH_KEY` | Authenticates the SSH session into the Droplet. |

### Implicit inputs already on the Droplet

| Field | Source | Notes |
|---|---|---|
| `.env` content | Ansible (vault-sourced) | App reads via `env_file: .env`. App repo does not control its content. |
| `proxy` network | Ansible (`docker` role) | Created on first apply; persists across runs. |
| `traefik` config | Ansible (`traefik` role) | Picks up new sites by label automatically; no per-deploy edits. |

### Outputs

- **Site is reachable** at its configured domain over HTTPS within a few minutes of deploy (Traefik labels detected; cert issued or already present).
- **`docker compose ps`** in `/opt/sites/<site>/` shows the new container running with the new image tag.
- **No drift in `--check --diff`** for this site's `.env` (vault-rendered values still match what's on disk).

---

## Error shapes

- **Compose file missing on first deploy.** Ansible has run but the app repo hasn't deployed yet. Site directory has `.env` but no `docker-compose.yml`. Ansible's container-start task stat-gates on the file and skips cleanly. The CI deploy fixes this by landing the compose file.
- **Compose file references an image not yet pushed.** `docker compose pull` fails. Deploy aborts; previous container keeps running.
- **`.env` references a vault value that's missing.** Ansible apply fails before rendering; CI deploy is unaffected (it only runs after Ansible has converged).
- **Traefik labels malformed.** Site comes up but is not reachable. Visible in Traefik dashboard / logs; not visible in `docker ps`. Operator-diagnostic, not contract-level.
- **Drift in `docker-compose.yml`** — historical issue (drift inventory item #3, resolved 2026-04-24). The webapp role no longer templates compose; the app repo is the only writer. Drift now means the operator manually edited compose on the Droplet, which is not a sanctioned operation.

---

## Invariants

- The `deploy` user is **not** sudo-capable. Privileged operations are not part of this interface.
- The `.env` file is **not** edited by CI. Any required new env var must be added to the vault first (Ansible run), then the new image deployed.
- The compose file is **not** edited by Ansible. Any required new compose-level setting (volume, network, label) is added by the app repo.
- The `proxy` network is **not** removed by CI. Compose's `external: true` declaration ensures CI can reference it without redefining.

---

## Versioning

This interface is informal — there is no version field on the contract today. Material changes (e.g., a new deploy-time secret moves from CI Secrets to vault, or vice versa) require:

1. An ADR documenting the change.
2. A coordinated update to ansible (new vault entry / role behavior) **and** to each app repo's CI/CD pipeline.
3. A stop-the-world transition: do not deploy mid-rollout.

If multiple stable shapes of this contract become necessary (e.g., legacy webapps that can't migrate to a new pattern), introduce explicit versioning at that point.

---

## Required GitHub Secrets per app repo

Documented here as the authoritative list; per-app repo READMEs should reference this rather than restating:

| Secret | Purpose |
|---|---|
| `DOCKER_USERNAME` | Docker Hub login for build & push. |
| `DOCKER_PASSWORD` | Docker Hub credential (token, not password, in practice). |
| `DROPLET_HOST` | SSH target host for the deploy step. |
| `DEPLOY_SSH_KEY` | Private key for the `deploy` user. |

The deploy SSH key is generated *on the Droplet* (key never leaves the box during creation), the public key registered for the `deploy` user, the private key copied to the GitHub Secret, then the private key deleted from the Droplet. This is a manual, per-app-repo, one-time setup step — see runbook (DevOps, forthcoming).
