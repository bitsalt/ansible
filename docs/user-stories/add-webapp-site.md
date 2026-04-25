# Add a webapp (Node.js / FastAPI / similar) site

**As Jeff (operator),** I want to add a new webapp site to the fleet such that Ansible owns the site directory and `.env` while the app's own repo owns `docker-compose.yml` and the deploy flow, so that per-app deploy decisions are not clobbered by Ansible re-rendering compose files.

## Acceptance criteria

1. Adding a new webapp site requires: copy a template var file (`vars/sites/node-site-1.yml` or similar) to `playbooks/vars/sites/<new-site>.yml`; populate any vault entries; add the dict to `nodejs_sites` (or `fastapi_sites`) in `site.yml` with `enabled: false` until the app repo's first deploy completes.
2. First-time bootstrap is two steps:
   1. Run Ansible (`--tags webapp`) — creates `/opt/sites/<new-site>/`, places `.env`, does *not* fail when `docker-compose.yml` is missing (the container-start task stat-gates on the compose file).
   2. Trigger the app repo's CI/CD deploy — builds the image, pushes to Docker Hub, SSHs into the Droplet as `deploy`, lands `docker-compose.yml`, and brings the container up.
3. Subsequent Ansible runs do not modify `docker-compose.yml` (the role no longer templates it). `--check --diff` shows zero compose-file drift on apply.
4. When `.env` changes, the next Ansible run restarts the container via `recreate: auto` (compose v2 hashes `env_file`).
5. The webapp role's `meta/argument_specs.yml` validates the `item` dict at entry; missing required fields (e.g., `enabled`, `site_name`, `site_domain`, `image`, `port`, `env_vars`) cause a clear failure before any tasks run.
6. The new site is reachable over HTTPS via Traefik routing once the container is up.

## Notes / edge cases

- DB connections use DO Managed PostgreSQL with credentials from the vault.
- The `webapp` role serves any single-port stateless HTTP app that takes config via env vars. If a future site needs a sidecar worker, bind mount, or non-HTTP entrypoint, split a new role rather than complicating `webapp`.
- The GitHub Secrets for the deploy must be set per repo: `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DROPLET_HOST`, `DEPLOY_SSH_KEY`. Document this in the per-repo runbook the app team owns; bitsalt-ansible's runbook references it but does not own it.
- Drift in `docker-compose.yml` between Ansible-templated and live (drift inventory item #3) was resolved 2026-04-24 by the ownership change — `webapp` no longer templates compose. Do not reintroduce.
