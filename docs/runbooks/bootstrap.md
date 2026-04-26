# Runbook: Bootstrap a fresh Droplet

Bring a freshly-provisioned Ubuntu 24.04 DigitalOcean Droplet to the BitSalt baseline.

**User story:** [bootstrap-fresh-droplet](../user-stories/bootstrap-fresh-droplet.md)
**Related ADR:** [0007 pre-Ansible SSH hardening](../adr/0007-pre-ansible-ssh-hardening.md)

---

## Trigger

A new Droplet has been provisioned in the DO dashboard and needs to reach the documented baseline (hardened SSH, UFW, Fail2ban, unattended-upgrades, `bitsalt` and `ansible` users) plus the BitSalt infra layer (Docker, Traefik, the shared `proxy` network).

## Pre-checks

- [ ] Droplet is up and reachable on its DO-assigned IP.
- [ ] You have the root password (DO emails it on creation) or root SSH key available for the first console session.
- [ ] You have your operator SSH public key ready (it'll go to the `bitsalt` user).
- [ ] You have the `ansible` SSH public key ready.
- [ ] You have the Ansible Vault password.

## Steps

### 1. Get `bootstrap.sh` onto the Droplet

Two options:

**Via DO console (preferred for first contact):**
1. Open the DO console for the Droplet.
2. Log in as `root` with the temporary password.
3. Paste the contents of `bootstrap.sh` into a new file on the Droplet (`nano /root/bootstrap.sh`), or `wget` it from a publicly-reachable location.

**Via initial SSH (if root SSH on port 22 is still allowed):**
```bash
scp bootstrap.sh root@<droplet-ip>:/root/bootstrap.sh
ssh root@<droplet-ip>
```

### 2. Run `bootstrap.sh`

```bash
chmod +x /root/bootstrap.sh
/root/bootstrap.sh
```

The script:
- Creates `bitsalt` and `ansible` users with their authorized keys and sudo NOPASSWD.
- Hardens SSH (no root, no password, custom port; default 2222) via `/etc/ssh/sshd_config.d/99-bitsalt-hardening.conf`.
- Configures UFW: deny inbound by default, allow SSH port + 80 + 443.
- Installs and configures Fail2ban.
- Enables unattended security upgrades, no auto-reboot.
- Prints manual follow-up steps.

### 3. Verify SSH still works (critical)

**Before closing the console session,** open a *second* SSH session as `bitsalt` on the new SSH port:

```bash
ssh -p 2222 bitsalt@<droplet-ip>
```

If this succeeds, the SSH hardening worked. If it fails, fix it from the console *before* logging out — once the console session ends and SSH is broken, recovery requires DO console access.

### 4. Manual follow-ups printed by the script

Take care of the items the script prints at the end:

- [ ] Generate the `deploy` user SSH key on the Droplet, copy the private key to GitHub Secrets, then delete it from the Droplet. (See per-app-repo onboarding.)
- [ ] Optionally restrict SSH to your office/home IP via UFW.
- [ ] Enable the DO Monitoring agent in the dashboard. Configure CPU/disk alerts.

### 5. Run Ansible against the new Droplet

From the control node, with the inventory pointing at the new Droplet on the custom port:

```bash
cd ~/projects/bitsalt-ansible/playbooks
ansible-playbook site.yml --ask-vault-pass --tags common,docker,traefik
```

This installs Docker, creates the `proxy` network, and brings up Traefik. It does not yet add any sites.

### 6. Confirm idempotence

Run the same Ansible command a second time. Expected: `changed=0`. If anything reports `changed`, that's a non-idempotent task — investigate before proceeding to add sites.

```bash
ansible-playbook site.yml --ask-vault-pass --tags common,docker,traefik
```

## Rollback

`bootstrap.sh` is not idempotent and not safe to re-run. To recover from a bad bootstrap:
- If SSH was just broken: use the DO console as `root` to revert `/etc/ssh/sshd_config.d/99-bitsalt-hardening.conf` and `systemctl reload sshd`.
- If something more substantive is wrong: destroy and recreate the Droplet. Bootstrap is fast enough that this is usually less risky than partial recovery.

## Post-incident notes

Record any deviations or issues here. Currently empty.

## Related

- Re-converging UFW / Fail2ban / unattended-upgrades on an existing Droplet is not yet possible via Ansible — that's a known gap (see `status.md` "Ansible / infrastructure"). Until those roles exist, treat `bootstrap.sh` as the only source of truth for those concerns and apply changes via re-running the relevant block in the script (carefully).
