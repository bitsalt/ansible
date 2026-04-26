# ADR 0004: Ansible Vault is the only secret store

**Status:** accepted
**Date:** 2026-04-24

## Context

Every site has secrets: DB passwords (one per Managed cluster user), API keys, ACME email, Docker Hub credentials, application-specific values (WordPress auth keys, Laravel APP_KEY, etc.). Some are operator-static; some are per-site; some are global. We need a single durable home for all of them with a clear access model.

## Decision

**`playbooks/group_vars/all/vault.yml`, encrypted with `ansible-vault`, is the only secret store.** All sensitive values are referenced as `vault_<name>` in non-vault files (with documented exceptions for legacy keys like `taotedev_db_password` that don't carry the prefix — kept for backward compatibility, flagged for renaming on a future pass). Tasks that render or accept these values carry `no_log: true` per the Ansible coding-standards addendum §7/§8.

Vault password is delivered to the operator out-of-band and used at runtime via `--ask-vault-pass`. The vault password is never committed and never stored on the Droplet.

## Consequences

**Easier:**
- One file to back up, one file to rotate, one access model to reason about.
- Diffs of `vault.yml` are encrypted in version control — the change history is visible (when and who) but the values are not.
- No external secret-store dependency; the system is self-contained.

**Harder:**
- The vault password is a single point of compromise (if leaked, full vault is exposed). Mitigated by out-of-band delivery and operator discipline.
- Loss of the vault password means manual reissue of every secret — no recovery mechanism by design.
- Editing requires `ansible-vault edit`; collaborators must have the password.
- Re-keying (rotating the vault password itself) is a deliberate, manual operation.

**Reconsider if:**
- A second operator joins the project and credential delegation needs become more granular (per-secret access, audit trail, automatic rotation).
- Compliance needs (e.g., a client engagement) require an external KMS.
- Multi-environment (staging vs. prod) needs make a single vault feel cramped — could split into per-environment vault files.

## Alternatives considered

- **HashiCorp Vault.** Industry-standard, full-featured. Rejected at current scale: operational burden of running and securing Vault outweighs the value over Ansible Vault for a single operator.
- **AWS Secrets Manager / DO Secrets (planned).** External managed service; per-secret ACL; audit trail. Reasonable future option; rejected today because it adds an external dependency (and a recurring cost) without solving a problem we have.
- **Per-site `.env` files committed plain to a private repo.** Common pattern in some shops; rejected because the repo is shared across multiple client sites and "private" is not a strong enough boundary for the credentials involved.
- **Sourced from environment at apply time.** Operator-friendly for local runs, but no durable history and no way to share with an absent operator. Rejected.
