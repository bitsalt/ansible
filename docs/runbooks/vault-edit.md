# Runbook: Edit the Ansible Vault

Add, change, or remove a secret in `playbooks/group_vars/all/vault.yml`.

**Related ADR:** [0004 Ansible Vault is the only secret store](../adr/0004-ansible-vault-only-secret-store.md)
**Related ops doc:** [ansible.md § Secrets pattern](../ops/ansible.md#secrets-pattern)

---

## Trigger

A secret needs to change: a new site's DB password, a credential rotation, the Docker Hub token expired, etc.

## Pre-checks

- [ ] You have the vault password (delivered out-of-band, never on disk).
- [ ] You're working in a clean checkout — no uncommitted changes that might collide.
- [ ] You know the exact key name to add or change (e.g., `vault_<site>_db_password`). Do not invent new naming patterns; match existing entries.

## Steps

### 1. Edit the vault

```bash
cd ~/projects/ansible/playbooks
ansible-vault edit group_vars/all/vault.yml
```

`ansible-vault` decrypts the file into a temp location, opens it in `$EDITOR`, and re-encrypts on save.

### 2. Make the edit

The file contains plain YAML once decrypted. Add or modify the entry:

```yaml
vault_<site>_db_password: <new-password>
```

For new entries, follow the existing naming convention: `vault_<scope>_<purpose>` (e.g., `vault_dockerhub_token`, `vault_traefik_acme_email`, `vault_<site>_db_password`).

**Save and close.** `ansible-vault` re-encrypts automatically. If the editor exits without saving, the file is unchanged.

### 3. Verify the file is still encrypted

```bash
head -1 group_vars/all/vault.yml
```

Expected output starts with: `$ANSIBLE_VAULT;1.1;AES256` (or similar header). If you see plain YAML, the file is unencrypted — re-encrypt immediately:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### 4. Commit

```bash
cd ..
git add playbooks/group_vars/all/vault.yml
git commit -m "vault: add/update <key>"
```

The encrypted file's diff is unreadable but commits cleanly. Commit message describes the *change*, not the *value*.

### 5. Apply the change

If the new value affects running infrastructure (most common case for DB password changes), re-run Ansible:

```bash
cd playbooks
ansible-playbook site.yml --ask-vault-pass --tags <relevant-tag>
```

For `.env`-rendered values, `recreate: auto` will recreate the affected container so it picks up the new env. Verify the container restarted and the app continues to work.

## Rollback

The vault is in git. To revert a vault edit:

```bash
git revert <commit-sha>   # if already pushed
# or
git reset HEAD~1          # if not yet pushed
```

If the bad value has already been *applied* (containers restarted, `.env` rendered with the new value), you also need:
1. Re-run Ansible with the reverted vault to re-render `.env`.
2. Containers will recreate to pick up the previous value.

For credential rotations specifically: rolling back means the old credential is in use again. If the rotation was driven by a compromise, do not roll back — fix forward.

## Post-incident notes

Record any deviations here. Currently empty.

## Common gotchas

- **Don't paste vault values into chat, logs, or commit messages.** Use placeholders (e.g., "rotated `vault_<site>_db_password`") in any human-readable artifact.
- **Vault password rotation is its own procedure.** Re-keying the vault (changing the password) is `ansible-vault rekey`. Coordinate with anyone else who has the password.
- **The `taotedev_db_password` key (without `vault_` prefix) is intentional legacy.** Don't rename it during a routine edit; that's a coordinated repo change.
- **No `no_log: true` review needed for vault edits.** That requirement applies to *role tasks* that render or accept vault values, not to vault file edits themselves. (Per Ansible coding-standards addendum §7/§8.)
