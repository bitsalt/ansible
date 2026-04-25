# ADR 0007: Bootstrap script handles SSH hardening before Ansible runs

**Status:** accepted
**Date:** 2026-04-24

## Context

A fresh Ubuntu 24.04 Droplet from DO comes up with permissive SSH defaults: root login enabled, password auth enabled, port 22, no Fail2ban. The desired baseline is the opposite: `bitsalt` and `ansible` users only, key-only auth, custom port, Fail2ban active, UFW deny-by-default.

The natural-default approach is to do all of this in Ansible. But Ansible needs SSH access to run, and *changing* SSH config mid-play (port, allowed users, root login, password auth) frequently breaks the very connection the play is using. Even when the new config is correct, the running SSH session ends up in a state mismatch with the daemon.

## Decision

**A standalone `bootstrap.sh` script, run as root on a fresh Droplet via the DO console (or an initial password SSH session before lockdown), handles all SSH-affecting hardening before Ansible is ever invoked.** Specifically:

- Creates `bitsalt` and `ansible` users with their SSH keys and sudo NOPASSWD.
- Hardens SSH via a drop-in `/etc/ssh/sshd_config.d/99-bitsalt-hardening.conf`: no root login, no password auth, custom port (default 2222).
- Configures UFW to deny all inbound except SSH port + 80 + 443.
- Installs and configures Fail2ban.
- Configures unattended security upgrades (no auto-reboot).
- Prints manual follow-up steps at the end (deploy-user key, DO Monitoring agent).

After `bootstrap.sh`, Ansible can connect cleanly as the `ansible` user on the custom port to do everything else (Docker, Traefik, sites).

## Consequences

**Easier:**
- No mid-play SSH connection-breakage class of failures.
- The script runs once per Droplet lifetime; idempotence is not required (it's not re-run as part of routine ops).
- Bash + standard Ubuntu tooling is universally available; no Ansible bootstrap dependency.

**Harder:**
- Two tools own related concerns: `bootstrap.sh` for first-boot hardening, Ansible for everything else. New SSH-affecting changes have to be made in both places (or just `bootstrap.sh` if they only matter at first boot).
- Re-converging UFW / Fail2ban / unattended-upgrades on an existing Droplet (e.g., after a manual change) is awkward today — `bootstrap.sh` is not safe to re-run, and equivalent Ansible roles for these concerns don't exist yet (known gap; see `status.md` "Ansible / infrastructure" remaining work). The fix is to add Ansible roles that *re-converge* (not bootstrap) UFW / Fail2ban / unattended-upgrades, leaving `bootstrap.sh` as the first-boot tool only.

**Reconsider if:**
- A way to SSH-harden cleanly mid-play emerges (e.g., a documented Ansible pattern using `wait_for_connection` after sshd reload that we can prove against). The current pattern is conservative but works.
- Multi-Droplet provisioning makes running `bootstrap.sh` by hand on each box impractical. Would push toward automation in DO user-data or a one-shot Ansible play with explicit reconnect handling.

## Alternatives considered

- **Do it all in Ansible from minute one.** Tried-and-failed pattern in many shops; SSH config changes mid-play race against the running session. Rejected.
- **Cloud-init / DO user-data script.** Same logical content as `bootstrap.sh`, runs at first boot without any human touching the console. Reasonable alternative; rejected today because the manual follow-up steps (deploy user key, DO dashboard config) require operator interaction anyway, so the savings of full unattended bootstrap are limited.
- **Ansible with a separate "first-boot" inventory entry on default port + password auth, then a "post-bootstrap" inventory on hardened port + key auth.** Adds two-state complexity for marginal benefit. Rejected.
