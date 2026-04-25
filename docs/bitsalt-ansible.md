# bitsalt-ansible — Sprint file

Single source of truth for in-flight work. PM is the only writer; other roles propose changes via the Open Questions table.

**Sprint cadence:** 7 days (per AGENT-PLATFORM.md).
**Sprint window:** 2026-04-21 → 2026-04-28 (current).

---

## Current sprint goal

Complete Task B drift reconciliation: re-baseline `--check --diff` against `community.docker` 5.2.0, schedule and execute the Traefik maintenance window, achieve `changed=0` on a second consecutive apply.

---

## Tasks

### Active sprint (week of 2026-04-21)

- 🟡 **B0: Re-baseline `--check --diff` post-`community.docker` 5.2.0 upgrade.** Capture new baseline at `.checks/baseline.log`. Compare against pre-upgrade baseline; expect `changed=7` (was `changed=9`).
- 🟡 **B1: Investigate drift item #4 — bitsalt-staging `.env` drift** (stale `SITE_DOMAIN=` and `SERVICE_NAME=` lines on disk; template no longer emits them). Confirm root cause; decide remediation (apply will re-render).
- 🟡 **B2: Investigate drift item #5 — two WordPress sites recreate on every apply.** A4 should have addressed this; verify under post-`community.docker` 5.2.0 check-mode fidelity.
- 🟡 **B3: Investigate drift item #6 — `wp-content` chown reports changed every run.** Determine whether `recurse: true` is necessary; consider one-time chmod at site creation.
- ⬜ **B4: Schedule Traefik maintenance window.** Coordinate with site owners of `bitsalt.com`, `frujo.net`, `mybusinessmagnet.tech` (3 customer-facing sites in blast radius). Pick a low-traffic weekend night / dawn slot.
- ⬜ **B5: Execute Task B step 4 — apply `--tags traefik` in the scheduled window.** Verify Traefik recreates cleanly; sites recover.
- ⬜ **B6: Apply remaining roles end-to-end** in order: `common → docker → webapp sites (one at a time with site filter) → wordpress sites`. Verify each site post-apply.
- ⬜ **B7: Verify idempotence.** A second consecutive `ansible-playbook site.yml --ask-vault-pass` reports `changed=0`. If not, identify and fix non-idempotent tasks.

### Phase 2 platform migration tasks (2026-04-24)

- ✅ **M1: Author requirements.md** — BA seeded full requirements (FR1–FR10, NFR1–NFR6, scope, dependencies).
- ✅ **M2: Author user stories** — BA seeded seven stories under `docs/user-stories/`.
- ✅ **M3: Author architecture.md** — Architect seeded full architecture doc.
- ✅ **M4: Author seven ADRs** — Architect produced 0001–0007 covering foundational decisions.
- ✅ **M5: Author CI-deploy interface spec** — Architect produced `docs/interfaces/ci-deploy.md`.
- ✅ **M6: Author runbooks** — DevOps produced six runbooks (`bootstrap`, `add-wordpress-site`, `add-webapp-site`, `wordpress-updates`, `rollback`, `vault-edit`).
- ✅ **M7: Author ops docs** — DevOps produced three ops docs (`ansible.md`, `ci.md`, `users.md`).
- ✅ **M8: Author `.agent-context.md`, sprint file, dashboard row** — PM (this step).
- 🟡 **M9: Tech Writer step** — README, getting-started, onboarding (in flight after M8 lands).

---

## Open Questions

| # | Raised by | Question | Proposed resolution | Status |
|---|---|---|---|---|
| OQ-1 | Architect (handoff note) | Should the Docker socket proxy and nginx-sidecar design notes be promoted to standalone ADRs? | Defer; revisit in Phase 3 retro. They are external-constraint-driven implementation details, not choices with meaningful alternatives. | open |
| OQ-2 | DevOps (handoff note) | Should `wordpress-core-upgrade.md` and `migrate-wordpress.md` runbooks be authored now or just-in-time on first invocation? | Defer to just-in-time. The user stories document the *what*; the runbook is the *how*, best authored against a real run. | open |
| OQ-3 | PM | Should `v1/` be retired now or after the remaining ~11 WordPress site migrations? | Retain `v1/` until at least the first three migrated sites have run cleanly under `playbooks/` end-to-end. Revisit at sprint review. | open |
| OQ-4 | PM | Should `status.md` and `docs/refactor.md` be retired now that their content is in the sprint file + ADRs? | Retain through this sprint as a cross-reference; retire at sprint review once Task B is complete. | open |
| OQ-5 | PM | Coordinate rename of legacy vault key `taotedev_db_password` → `vault_taotedev_db_password` — when? | Defer. Bundle with a future vault-hygiene pass; not blocking any current work. | open |

Other roles append proposals here; PM lands them at the next sprint review or on demand.

---

## Decisions log

New entries at the top.

### 2026-04-24

- **Phase 2 platform migration of bitsalt-ansible complete.** Full set of platform docs landed: requirements (BA), architecture + 7 ADRs + 1 interface spec (Architect), 6 runbooks + 3 ops docs (DevOps), this sprint file + `.agent-context.md` + dashboard row (PM). README and getting-started forthcoming from Tech Writer.
- **Webapp ownership boundary established** — Ansible owns `.env` for webapp sites; the app repo owns `docker-compose.yml` and the deploy flow. Drives ADR 0006 and `docs/interfaces/ci-deploy.md`. Resolved drift inventory item #3.
- **A4 (`recreate: auto` over `recreate: always`) complete.** Commit `8bba511`. Traefik handler retained at `always` with explicit block-comment rationale (compose v2 cannot detect changes to bind-mounted file content; socket-proxy.conf edits would be missed under `auto`).
- **A3 complete across all 6 roles** (`webapp`, `wordpress`, `laravel`, `traefik`, `common`, `docker`). Each declares `meta/argument_specs.yml` and `defaults/main.yml`. Post-A3 baseline `ok=53 changed=9`. Argument-spec validation refuses to run when required fields are missing.
- **`community.docker` upgraded to 5.2.0** (commit `364d33c`). Pinned in `requirements.yml`. KB lesson at `community.docker/check-mode-fidelity-pre-3-10.md`. Post-upgrade baseline: `ok=53 changed=7`. Dry-run mode warnings gone.
- **A2 (ansible-lint + yamllint + CI hook) complete.** Commit `c4bffe3`. Linters exit 0 against `playbooks/`. CI workflow at `.github/workflows/lint.yml` runs on push/PR. Versions pinned in `requirements.txt`.
- **A1 (`no_log: true` on tasks rendering vault values) complete.** Commit `927b264`. Rule: any task whose module arguments or rendered output include a `vault_*` variable carries `no_log: true`.

### 2026-04-23

- **Ansible coding-standards addendum authored** at `~/projects/coding-standards/coding-standards-ansible.md`. Codifies how the core coding standards (§1–§16) map onto Ansible. Drove Tasks A1–A4.

### 2026-04-06

- **taotedev.com fully live in production.** WordPress loads, plugins up to date, SSL via Let's Encrypt/Traefik. First customer-facing site validated end-to-end on the new infra.

---

## Carry-over Log

Items deferred from earlier work that aren't on the active sprint. Each carries the trigger that should bring it back into a sprint.

- **Backup cron role (FR9 / `add-daily-backups` user story).** *Trigger:* before migrating any additional WordPress sites; takes manual pre-migration backups instead until landed. *Source:* status.md "Ansible / infrastructure."
- **UFW / Fail2ban / unattended-upgrades Ansible roles** for re-convergence after a rebuild. *Trigger:* before the first Droplet rebuild scenario, or as a sprint goal once Task B is complete. *Source:* status.md.
- **Migration of remaining ~11 WordPress sites.** *Trigger:* Task B complete + backup role landed (or manual backup discipline). Pace: one at a time. *Source:* status.md "Remaining sites (migration)."
- **Real Docker Hub image names** substituted into `vars/sites/laravel-site.yml` and `vars/sites/node-site-1.yml`. *Trigger:* Laravel and Node.js apps reach a state where their CI builds and pushes images. *Source:* status.md.
- **Set `enabled: true`** in laravel and nodejs site var files. *Trigger:* paired with the Docker Hub image name task above.
- **node-site-2 vars file** (copy from node-site-1 when ready). *Trigger:* a second Node.js site is identified for deploy.
- **Real domain names + credentials** populated in vault for all sites with placeholder values. *Trigger:* per-site, as part of each migration's pre-checks.
- **Per-app-repo `deploy` SSH key generation** + GitHub Secrets setup. *Trigger:* per-app-repo, when bringing the app's CI/CD online.
- **DO Monitoring agent enabled and alerts configured.** *Trigger:* operator decision; non-blocking.
- **`wordpress-core-upgrade.md` runbook.** *Trigger:* first WP core upgrade across the fleet.
- **`migrate-wordpress.md` runbook.** *Trigger:* first migration of an existing WP site to the Droplet.
- **Retirement of `v1/` directory.** *Trigger:* after the first three migrated sites validate cleanly under `playbooks/`. See OQ-3.
- **Retirement of `status.md` and `docs/refactor.md`.** *Trigger:* end of current sprint, after Task B completes. See OQ-4.
- **Coordinated rename `taotedev_db_password` → `vault_taotedev_db_password`.** *Trigger:* future vault-hygiene pass. See OQ-5.
- **Promote socket-proxy and nginx-sidecar design notes to ADRs (or not).** *Trigger:* Phase 3 retro. See OQ-1.

---

## Sprint reviews

(No sprint review entries yet. The first runs at the end of the current sprint window, 2026-04-28.)
