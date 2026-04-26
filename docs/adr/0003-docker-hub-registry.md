# ADR 0003: Docker Hub as image registry

**Status:** accepted
**Date:** 2026-04-24

## Context

Custom-image sites (Laravel, Node.js, FastAPI) need a registry that:
- Receives images pushed by per-repo CI/CD (GitHub Actions).
- Allows the Droplet to pull images during deploys, authenticated with credentials in the vault.
- Charges acceptably at our scale.

## Decision

**Docker Hub** is the image registry for all custom-image sites. Authentication uses `community.docker.docker_login` in the Ansible `docker` role with `vault_dockerhub_username` and `vault_dockerhub_token` from the vault. Per-repo CI/CD logs in to Docker Hub with separate credentials configured in the repo's GitHub Secrets (`DOCKER_USERNAME`, `DOCKER_PASSWORD`).

## Consequences

**Easier:**
- Universally available, no extra DO product to provision.
- GitHub Actions has well-documented integration patterns.
- Free tier covers our public-image needs; paid plans available if image counts or pull rates outgrow the free tier.

**Harder:**
- Pull rate limits on the free tier (not currently a constraint, but visible).
- Two registries effectively in play (Docker Hub for custom images, plus pulls of upstream images like `wordpress:*-fpm`, `nginx:alpine`, `traefik:v3.3` from the same registry) — meaning the same rate limit window applies.
- Custom images are public by default unless paid-tier private repos are used. Today's images do not contain secrets at build time, but this constraint must be respected on every build.

**Reconsider if:**
- Pull rate limits start affecting deploys (move to a paid plan, mirror, or DO Container Registry).
- A custom image must contain build-time secrets (would require private repos or a different registry).
- Multi-region or HA topology adds latency considerations that favor a regional registry.

## Alternatives considered

- **DO Container Registry.** Same provider as everything else; private by default; per-region. Rejected: extra cost for capacity we don't need, and no compelling integration advantage over Docker Hub at our scale.
- **GitHub Container Registry (`ghcr.io`).** Tighter integration with the per-repo CI; per-repo permissions model. Reasonable alternative; chose Docker Hub for simpler cross-repo permissions and the team's existing familiarity. Reconsider if cross-repo permission management becomes a real friction.
- **Self-hosted registry on the Droplet.** Avoids external dependency but adds backup, TLS, and storage burden for marginal benefit. Rejected.
