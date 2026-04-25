# Operations: Droplet user inventory

Users that exist on the Droplet, what each is for, and how access is managed. Operational reference; the user inventory may evolve as roles or integrations change.

**Related ADR:** [0007 pre-Ansible SSH hardening](../adr/0007-pre-ansible-ssh-hardening.md)

---

## User inventory

| User | Purpose | Sudo | Created by | Notes |
|---|---|---|---|---|
| `bitsalt` | Day-to-day admin / SSH / one-off operations | Yes (NOPASSWD) | `bootstrap.sh` | Operator's personal SSH key. |
| `ansible` | Ansible control-node SSH target | Yes (NOPASSWD) | `bootstrap.sh` | Ansible-specific SSH key. |
| `deploy` | GitHub Actions SSH deploys for app repos | **No** | Manual (post-bootstrap) | Narrowly scoped; per-app-repo SSH key managed by hand. |
| `root` | Disabled for SSH; accessible only via DO console | (root) | (system) | SSH login disabled by `bootstrap.sh`. |

Plus the standard system / service users created by Ubuntu and Docker (`syslog`, `messagebus`, `_apt`, etc.). Those are not in scope for this document.

---

## Access model

- **`bitsalt`** — Jeff's personal account. NOPASSWD sudo because the operator already has full control via SSH key + console fallback; password prompts during long ops are friction without value. SSH key only; no password auth. Used for routine SSH, one-off Bash commands (WP-CLI), incident response.
- **`ansible`** — Ansible runs as this user. NOPASSWD sudo for the same reason as `bitsalt`. Restricted to SSH key auth from the control node. The key is the operator's responsibility; on a new control node, the key must be installed and added to `/home/ansible/.ssh/authorized_keys`.
- **`deploy`** — App repo CI/CD logs in as this user. **Not sudo-capable.** Login is restricted to what `docker compose` deploys need under `/opt/sites/<repo's site>/`. Each app repo has its own SSH key (per-repo `DEPLOY_SSH_KEY` GitHub Secret). The private key is generated on the Droplet, the public key is added to `/home/deploy/.ssh/authorized_keys`, the private key is then copied off and deleted from the Droplet — see [add-webapp-site.md § Step 7](../runbooks/add-webapp-site.md).

---

## SSH configuration

- Custom port (default 2222 from `bootstrap.sh`); root login disabled; password authentication disabled.
- Hardening lives in `/etc/ssh/sshd_config.d/99-bitsalt-hardening.conf` (drop-in style; the main `sshd_config` is unchanged).
- Fail2ban is active on SSH.
- UFW allows only the custom SSH port + 80 + 443 inbound.

---

## Adding a new user

Adding a new operator (e.g., a contractor):

1. Generate or collect their SSH public key.
2. SSH in as `bitsalt`.
3. `sudo useradd -m -s /bin/bash <name>`
4. `sudo mkdir -p /home/<name>/.ssh && sudo chown <name>:<name> /home/<name>/.ssh && sudo chmod 700 /home/<name>/.ssh`
5. Add their public key to `/home/<name>/.ssh/authorized_keys` (mode 600, owner `<name>:<name>`).
6. Decide on sudo:
   - **No sudo** for narrow-purpose accounts (default for contractors / deploy-style users).
   - `sudo usermod -aG sudo <name>` for an additional admin (rare; usually just expand `bitsalt`'s key set).
7. Document the addition here.

This is not Ansible-driven today. If user management starts churning, a `users` Ansible role becomes appropriate.

---

## Removing a user

```bash
sudo deluser --remove-home <name>
```

Plus: rotate any vault entries, GitHub Secrets, or external systems that referenced the user. Document the removal here.

---

## Audit / review

The user list should be reviewed as part of sprint-level work (PM step) when:
- A contractor or collaborator's engagement ends.
- A credential rotation is in progress.
- An incident suggests over-broad access.

There is no automated audit today; the table above is the source of truth.

---

## Open items

- A `users` Ansible role for re-converging the user inventory (currently `bootstrap.sh` is the only writer at first boot, with manual changes after). Tracked alongside the other re-convergence gaps in `status.md`.
- Per-user audit logging is the system's default `auth.log`; no centralized aggregation today. Out of scope.
