# Bootstrap a fresh Droplet

**As Jeff (operator),** I want to take a freshly provisioned Ubuntu 24.04 Droplet to a known hardened baseline with one script and one Ansible run, so that the Droplet is reproducible and never depends on tribal knowledge or undocumented manual steps.

## Acceptance criteria

1. Running `bootstrap.sh` as root on a fresh Droplet completes without errors and prints the manual follow-up steps at the end.
2. After `bootstrap.sh`: root SSH login is disabled, password authentication is disabled, SSH listens on the configured non-default port (default 2222).
3. After `bootstrap.sh`: UFW is active and denies all inbound traffic except the SSH port plus 80 and 443.
4. After `bootstrap.sh`: Fail2ban is running and configured.
5. After `bootstrap.sh`: unattended-upgrades is enabled and configured to *not* auto-reboot.
6. After `bootstrap.sh`: `bitsalt` and `ansible` users exist with sudo NOPASSWD and their respective SSH keys.
7. Following the manual steps (deploy-user key generation, DO Monitoring agent), `ansible-playbook site.yml --ask-vault-pass --tags common,docker,traefik` runs cleanly against the new Droplet from the control node.
8. A second consecutive run of the same Ansible command reports `changed=0`.

## Notes / edge cases

- The deploy-user SSH key must be generated on the Droplet and the private key copied to GitHub Secrets, then deleted from the Droplet — this is a manual post-bootstrap step, not automated.
- DO Monitoring agent is enabled in the DO dashboard; this project does not provision it. (Future scope: see `add-daily-backups.md` and FR10 for whether monitoring agent installation should be added to a role.)
- UFW / Fail2ban / unattended-upgrades currently land via `bootstrap.sh`. To support re-convergence on a rebuild, equivalent Ansible roles should exist (currently a known gap — see `status.md`).
- The bootstrap script does not modify the SSH port from a non-default to a different non-default value safely; if the port needs to change post-bootstrap, plan the change carefully to avoid losing connectivity.
