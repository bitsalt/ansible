# bitsalt-ansible

Ansible repo that provisions and maintains a single-DigitalOcean-Droplet hosting environment for BitSalt's portfolio of WordPress, Laravel, Node.js, and FastAPI sites behind a shared Traefik reverse proxy. All databases run on DO Managed clusters; all secrets live in Ansible Vault.

This repo *is* the deploy mechanism for the infra layer — there is no separate CI deploy of bitsalt-ansible itself. App-site deploys (Laravel, Node.js, FastAPI) live in each app's own repo and SSH into the Droplet under a contract documented at [docs/interfaces/ci-deploy.md](docs/interfaces/ci-deploy.md).

---

## Quick start

If you already have the operator credentials and are joining an in-flight project:

1. **Read** [docs/getting-started.md](docs/getting-started.md) for prerequisites and control-node setup.
2. **Read** the active [sprint file](docs/bitsalt-ansible.md) to see what's in flight.
3. **Skim** [docs/architecture.md](docs/architecture.md) for the system shape and the [ADRs](docs/adr/) for the non-obvious decisions.
4. **Run** the Quick start section in [playbooks/README.md](playbooks/README.md) to apply the playbook.

For the full end-to-end onboarding (no prior context), see [docs/onboarding.md](docs/onboarding.md).

---

## Where things live

| Path | Purpose |
|---|---|
| `playbooks/` | **Source of truth.** All current Ansible work happens here. |
| `v1/` | Legacy structure, retained for reference until the refactor is fully validated. Do not modify. |
| `bootstrap.sh` | First-boot Droplet hardening script. Standalone Bash; runs once per Droplet. |
| `docs/` | All project documentation (this README is the entry point). |
| `docs/architecture.md` | System architecture and component overview. |
| `docs/adr/` | Architectural Decision Records — the non-obvious "why we did it this way" calls. |
| `docs/interfaces/` | Component / cross-team boundary specs. |
| `docs/runbooks/` | Step-by-step procedures for routine operations and incidents. |
| `docs/ops/` | Operational reference: Ansible patterns, CI/CD contracts, user inventory. |
| `docs/requirements.md` | What the system must do (functional + non-functional). |
| `docs/user-stories/` | Per-capability user stories driving the requirements. |
| `docs/bitsalt-ansible.md` | Sprint file (active work, decisions log, open questions). |
| `.agent-context.md` | Compact context for Claude Code agents arriving cold. |
| `.github/workflows/lint.yml` | CI: `ansible-lint` + `yamllint` on push/PR. |
| `requirements.txt` | Pinned control-node tooling (ansible-lint, yamllint). |
| `status.md`, `docs/refactor.md` | Pre-platform tracking. Retained through current sprint as cross-reference; see sprint file Open Questions for retirement. |

---

## Status

- **Phase:** Phase 2 — platform migration just completed; rolling into Task B drift reconciliation.
- **Production state:** `taotedev.com` is fully live. Three other customer-facing sites (`bitsalt.com`, `frujo.net`, `mybusinessmagnet.tech`) are staged or live. ~11 additional WordPress sites await migration.
- **Stability:** Active development. The `playbooks/` structure has been validated against `taotedev.com` end-to-end; remaining work is Task B drift reconciliation and migrations (see sprint file).

---

## License / ownership

Internal to BitSalt Digital LLC. Not currently published.
