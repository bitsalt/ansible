# Operations: CI/CD

GitHub Actions workflows for bitsalt-ansible itself and the contract for app-repo CI/CD that deploys to the Droplet.

**Related ADR:** [0003 Docker Hub registry](../adr/0003-docker-hub-registry.md)
**Related interface:** [ci-deploy.md](../interfaces/ci-deploy.md)

---

## Workflows in this repo

### `lint.yml`

Located at `.github/workflows/lint.yml`. Runs on push and PR.

- **Purpose:** Run `ansible-lint` (production profile) and `yamllint` against `playbooks/`. Fail the workflow on any lint error.
- **Triggers:** push to any branch, pull request to any branch.
- **Required secrets:** none.
- **Versions:** `ansible-lint` and `yamllint` are pinned in `requirements.txt` (see file for exact versions).
- **Runtime:** under a minute.

Lint must pass green before merge. If a lint rule is being silenced, the ignore must carry a written rationale.

There are no other workflows in this repo today. Application of the playbook to production is operator-run; deploys (for app sites) live in *each app's own repo*.

---

## App-repo CI/CD contract

Each app site (Node.js, FastAPI) has its own GitHub repo with its own deploy workflow. The contract for those workflows is specified in [`docs/interfaces/ci-deploy.md`](../interfaces/ci-deploy.md). Read that for the authoritative version. Summary:

- **Build** the image, tag with `github.sha`.
- **Push** to Docker Hub (authenticated via `DOCKER_USERNAME` + `DOCKER_PASSWORD`).
- **SSH** into the Droplet as `deploy` (key from `DEPLOY_SSH_KEY` GitHub Secret) on the configured custom port.
- **Update `docker-compose.yml`** in `/opt/sites/<site>/` with the new image tag, then `docker compose pull && up -d`.
- **For Laravel:** also run `php artisan migrate --force`.

The deploy step does *not* edit `.env` (Ansible's surface) or anything outside `/opt/sites/<site>/`.

---

## Required GitHub Secrets per app repo

| Secret | Purpose |
|---|---|
| `DOCKER_USERNAME` | Docker Hub login for build & push. |
| `DOCKER_PASSWORD` | Docker Hub credential (token, not password, in practice). |
| `DROPLET_HOST` | SSH target host for the deploy step. The Droplet IP or DNS name. |
| `DEPLOY_SSH_KEY` | Private key for the `deploy` user on the Droplet. |

The `DEPLOY_SSH_KEY` is generated *on the Droplet* (key never leaves the box during creation), the public key is placed in `/home/deploy/.ssh/authorized_keys`, the private key is copied to the GitHub Secret, then the private key is deleted from the Droplet. See [add-webapp-site.md § Step 7](../runbooks/add-webapp-site.md) for the per-app-repo setup.

---

## Rollback

Rolling back an app deploy is operator-driven, not CI-driven. See [rollback.md](../runbooks/rollback.md). Each deploy tags the image with `github.sha`, so any prior good SHA is recoverable as long as it's still on Docker Hub (Docker Hub retention is effectively indefinite at our scale).

A rolling deployment log is maintained at `/opt/deployments.txt` (when in use) — last known good tag per site, manually updated.

---

## Future workflows (not yet implemented)

- **Per-Ansible-PR `--check --diff` workflow.** Run a dry-run apply against a staging Droplet (or a snapshot) to catch drift early. Requires either a permanent staging Droplet or ephemeral provisioning. Out of scope today.
- **Backup verification workflow.** Once backups land (FR9), a periodic restore-test workflow against a staging environment would verify backups are usable. Out of scope until backups exist.
