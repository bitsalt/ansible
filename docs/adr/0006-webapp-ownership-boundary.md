# ADR 0006: Webapp ownership boundary — Ansible owns `.env`, app repo owns `docker-compose.yml`

**Status:** accepted
**Date:** 2026-04-24

## Context

Webapp sites (Node.js, FastAPI) are built and deployed by per-repo CI/CD pipelines (GitHub Actions): build image → push to Docker Hub → SSH into the Droplet as `deploy` → edit the image tag in `docker-compose.yml` → `docker compose pull && up -d`. The `webapp` Ansible role originally also templated `docker-compose.yml`. This caused recurring drift: every Ansible apply re-rendered compose, clobbering the image-tag pin the CI deploy had just landed.

The drift was visible in `--check --diff` baselines (drift inventory item #3 in `docs/refactor.md`). Each apply effectively threatened the live deploy of any webapp site.

## Decision

**Ansible owns `.env` for webapp sites; the app repo owns `docker-compose.yml` and the deploy flow.**

- The `webapp` role no longer templates `docker-compose.yml`. The role's container-start task stat-gates on the file existing, so a fresh site bootstraps cleanly when the app repo's first deploy lands compose later.
- First-time bootstrap is two steps: (1) Ansible run creates the site directory and renders `.env` — container start is skipped because compose is missing; (2) app repo CI deploys, lands `docker-compose.yml`, brings up the container.
- Subsequent Ansible runs restart the container via `recreate: auto` when `.env` changes (compose v2 hashes `env_file`).

**`wordpress` and `laravel` roles are unaffected.** They have no per-app CI today and retain full Ansible ownership of their compose files.

## Consequences

**Easier:**
- App repos can make per-deploy compose decisions (image tag pinning, restart policies, resource limits) without fighting Ansible.
- `--check --diff` is now a reliable signal — drift in a webapp's compose file means a real configuration issue, not Ansible's normal behavior.
- The CI/CD ↔ Droplet contract becomes explicit (see `docs/interfaces/ci-deploy.md`).

**Harder:**
- The first-time bootstrap sequence is two steps, not one. An operator who misses step 2 ends up with a site directory and `.env` but no running container. The runbook (DevOps-owned) calls this out.
- Compose-level concerns that *should* be globally consistent (e.g., a standard healthcheck pattern, restart policy) are now per-repo decisions. Drift in those concerns is a coordination problem, not a tooling problem.
- If two webapp repos diverge in incompatible ways (e.g., one uses a network the other doesn't), the operator notices it as runtime breakage rather than at apply time.

**Reconsider if:**
- A future class of webapp emerges that genuinely needs Ansible-owned compose (e.g., a shared sidecar pattern across multiple webapps). Could be addressed by a new role rather than reverting this decision.
- Compose-level drift between webapp repos becomes a recurring source of incidents — would suggest re-adding a minimal Ansible-templated compose with clear "you may extend, you may not contradict" zones.

## Alternatives considered

- **Keep Ansible templating compose; use `git stash`-like workarounds in CI to preserve image tags.** Rejected: fragile, error-prone, and fights the per-repo deploy flow rather than embracing it.
- **App repo owns both `.env` and `docker-compose.yml`.** Rejected: `.env` contains vault-sourced secrets; the credential boundary belongs in Ansible. Splitting it (Ansible writes a partial `.env`, app repo writes the rest) was considered but added complexity for marginal benefit.
- **Apply the same boundary to WordPress and Laravel.** Rejected: those stacks have no per-app CI today; Ansible's compose ownership is uncontested. If WP/Laravel sites ever grow per-repo CI, revisit.
