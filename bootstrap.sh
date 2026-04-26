#!/usr/bin/env bash
# =============================================================================
# BitSalt Droplet Bootstrap Script
# Run as root on a fresh DigitalOcean Ubuntu 24.04 Droplet.
#
# BEFORE RUNNING:
#   1. Replace YOUR_ADMIN_SSH_PUBLIC_KEY below with your personal public key
#      (the key you use for day-to-day SSH access as bitsalt).
#   2. Replace YOUR_ANSIBLE_SSH_PUBLIC_KEY below with the public key that
#      your Ansible control node will use (can be the same key during initial
#      setup, swap it out later).
#   3. Set SSH_PORT to your chosen non-standard port.
#
# AFTER RUNNING:
#   - SSH into the Droplet as: ssh -p <SSH_PORT> bitsalt@<droplet-ip>
#   - Verify sudo works: sudo whoami
#   - Then proceed to generate the deploy user SSH key (see comment at bottom).
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION — edit these before running
# =============================================================================

ADMIN_USER="bitsalt"
ANSIBLE_USER="ansible"
SSH_PORT=2222   # Change to your preferred non-standard port

ADMIN_SSH_KEY="YOUR_ADMIN_SSH_PUBLIC_KEY"
ANSIBLE_SSH_KEY="YOUR_ANSIBLE_SSH_PUBLIC_KEY"

# =============================================================================
# Sanity check — must run as root
# =============================================================================

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

if [[ "$ADMIN_SSH_KEY" == "YOUR_ADMIN_SSH_PUBLIC_KEY" ]]; then
  echo "ERROR: Replace YOUR_ADMIN_SSH_PUBLIC_KEY before running." >&2
  exit 1
fi

if [[ "$ANSIBLE_SSH_KEY" == "YOUR_ANSIBLE_SSH_PUBLIC_KEY" ]]; then
  echo "ERROR: Replace YOUR_ANSIBLE_SSH_PUBLIC_KEY before running." >&2
  exit 1
fi

echo "==> Starting BitSalt Droplet bootstrap..."

# =============================================================================
# System update
# =============================================================================

echo "==> Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# =============================================================================
# Create bitsalt admin user
# =============================================================================

echo "==> Creating admin user: $ADMIN_USER"

if id "$ADMIN_USER" &>/dev/null; then
  echo "    User $ADMIN_USER already exists, skipping creation."
else
  useradd -m -s /bin/bash "$ADMIN_USER"
  echo "    User $ADMIN_USER created."
fi

# Add to sudo group
usermod -aG sudo "$ADMIN_USER"

# Lock password login (key-only access)
passwd -l "$ADMIN_USER"

# Deploy SSH key
mkdir -p /home/"$ADMIN_USER"/.ssh
echo "$ADMIN_SSH_KEY" > /home/"$ADMIN_USER"/.ssh/authorized_keys
chmod 700 /home/"$ADMIN_USER"/.ssh
chmod 600 /home/"$ADMIN_USER"/.ssh/authorized_keys
chown -R "$ADMIN_USER":"$ADMIN_USER" /home/"$ADMIN_USER"/.ssh
echo "    SSH key deployed for $ADMIN_USER."

# Allow passwordless sudo for bitsalt
# Ansible will later tighten this to specific commands if needed
cat > /etc/sudoers.d/"$ADMIN_USER" <<EOF
$ADMIN_USER ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/"$ADMIN_USER"
echo "    Sudo configured for $ADMIN_USER."

# =============================================================================
# Create ansible user
# =============================================================================

echo "==> Creating Ansible user: $ANSIBLE_USER"

if id "$ANSIBLE_USER" &>/dev/null; then
  echo "    User $ANSIBLE_USER already exists, skipping creation."
else
  useradd -m -s /bin/bash "$ANSIBLE_USER"
  echo "    User $ANSIBLE_USER created."
fi

usermod -aG sudo "$ANSIBLE_USER"
passwd -l "$ANSIBLE_USER"

mkdir -p /home/"$ANSIBLE_USER"/.ssh
echo "$ANSIBLE_SSH_KEY" > /home/"$ANSIBLE_USER"/.ssh/authorized_keys
chmod 700 /home/"$ANSIBLE_USER"/.ssh
chmod 600 /home/"$ANSIBLE_USER"/.ssh/authorized_keys
chown -R "$ANSIBLE_USER":"$ANSIBLE_USER" /home/"$ANSIBLE_USER"/.ssh

cat > /etc/sudoers.d/"$ANSIBLE_USER" <<EOF
$ANSIBLE_USER ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/"$ANSIBLE_USER"
echo "    SSH key and sudo configured for $ANSIBLE_USER."

# =============================================================================
# Harden SSH daemon
#
# This is done here — not in Ansible — because:
#   - Disabling root login and password auth before a working non-root
#     user exists will lock you out.
#   - Changing the SSH port mid-Ansible-run breaks the connection.
#
# We make all SSH changes at once, at the end of this script, after
# both users are confirmed working.
# =============================================================================

echo "==> Hardening SSH daemon..."

SSHD_CONFIG="/etc/ssh/sshd_config"

# Back up original config
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%F)"

# Apply hardened settings using a drop-in override file
# This avoids wrestling with sed on the main config
cat > /etc/ssh/sshd_config.d/99-bitsalt-hardening.conf <<EOF
# BitSalt hardening — applied by bootstrap.sh
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
MaxAuthTries 3
LoginGraceTime 30
AllowUsers $ADMIN_USER $ANSIBLE_USER
EOF

echo "    SSH config written. Validating..."
sshd -t
echo "    SSH config is valid."

# =============================================================================
# UFW firewall
# =============================================================================

echo "==> Configuring UFW firewall..."

apt-get install -y -qq ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP (Traefik)'
ufw allow 443/tcp comment 'HTTPS (Traefik)'

# Enable without interactive prompt
ufw --force enable
echo "    UFW enabled. Rules:"
ufw status numbered

# =============================================================================
# Install Fail2ban
# =============================================================================

echo "==> Installing Fail2ban..."

apt-get install -y -qq fail2ban

# Write a local jail config for SSH on the custom port
cat > /etc/fail2ban/jail.d/sshd-bitsalt.conf <<EOF
[sshd]
enabled  = true
port     = $SSH_PORT
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
bantime  = 3600
findtime = 600
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "    Fail2ban enabled and configured for port $SSH_PORT."

# =============================================================================
# Unattended security upgrades
# =============================================================================

echo "==> Configuring unattended security upgrades..."

apt-get install -y -qq unattended-upgrades

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "    Unattended upgrades configured (security patches only, no auto-reboot)."

# =============================================================================
# Restart SSH
# Doing this last so all users and keys are in place before we change the port.
# =============================================================================

echo "==> Restarting SSH daemon..."
systemctl restart ssh
echo "    SSH restarted on port $SSH_PORT."

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================"
echo "  Bootstrap complete."
echo "============================================================"
echo ""
echo "  Admin user : $ADMIN_USER"
echo "  Ansible user: $ANSIBLE_USER"
echo "  SSH port   : $SSH_PORT"
echo ""
echo "  Test your connection BEFORE closing this session:"
echo "    ssh -p $SSH_PORT $ADMIN_USER@<droplet-ip>"
echo ""
echo "  DO NOT close this root session until you have confirmed"
echo "  the above SSH command works in a separate terminal."
echo ""
echo "============================================================"
echo "  MANUAL STEPS REMAINING (cannot be automated):"
echo "============================================================"
echo ""
echo "  1. DEPLOY USER (GitHub Actions):"
echo "     After confirming SSH access as $ADMIN_USER, create the"
echo "     deploy user and its SSH key:"
echo ""
echo "       sudo useradd -m -s /bin/bash deploy"
echo "       sudo passwd -l deploy"
echo "       sudo mkdir -p /home/deploy/.ssh"
echo "       sudo chmod 700 /home/deploy/.ssh"
echo "       sudo ssh-keygen -t ed25519 -f /home/deploy/.ssh/id_ed25519 -N ''"
echo "       sudo cat /home/deploy/.ssh/id_ed25519.pub >> /home/deploy/.ssh/authorized_keys"
echo "       sudo chmod 600 /home/deploy/.ssh/authorized_keys"
echo "       sudo chown -R deploy:deploy /home/deploy/.ssh"
echo ""
echo "     Then copy the private key into GitHub Secrets:"
echo "       sudo cat /home/deploy/.ssh/id_ed25519"
echo "     Paste the output into GitHub → Settings → Secrets → DEPLOY_SSH_KEY"
echo "     Then delete the private key from the Droplet:"
echo "       sudo rm /home/deploy/.ssh/id_ed25519"
echo ""
echo "  2. STATIC IP RESTRICTION (optional but recommended):"
echo "     If your home/office IP is static, restrict SSH to that IP:"
echo "       sudo ufw delete allow $SSH_PORT/tcp"
echo "       sudo ufw allow from <YOUR_IP> to any port $SSH_PORT proto tcp"
echo ""
echo "  3. DIGITALOCEAN MONITORING:"
echo "     Enable the DO monitoring agent and set alerts via the DO dashboard."
echo "     CPU > 80% for 5 min and disk > 85% are good starting thresholds."
echo "     URL: https://cloud.digitalocean.com/droplets/<your-droplet>/graphs"
echo ""
echo "  When the above are complete, proceed to Ansible playbook setup."
echo "============================================================"
