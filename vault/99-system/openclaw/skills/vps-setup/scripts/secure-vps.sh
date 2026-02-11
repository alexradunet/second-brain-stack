#!/bin/bash
# secure-vps.sh — Harden a fresh Debian VPS
# Run as root or with sudo. Requires an SSH key already configured for the nazar user.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Must be root
[[ $EUID -eq 0 ]] || error "Run as root: sudo bash $0"

echo "========================================="
echo "  Debian VPS Security Hardening"
echo "========================================="
echo ""

# --- Phase 1: Create nazar user ---
if id "nazar" &>/dev/null; then
    info "User 'nazar' already exists, skipping."
else
    info "Creating user 'nazar'..."
    adduser --disabled-password --gecos "Nazar Service" nazar
    usermod -aG sudo nazar
    echo "nazar ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nazar
    chmod 0440 /etc/sudoers.d/nazar

    # Copy root's SSH keys
    if [ -f /root/.ssh/authorized_keys ]; then
        mkdir -p /home/nazar/.ssh
        cp /root/.ssh/authorized_keys /home/nazar/.ssh/authorized_keys
        chown -R nazar:nazar /home/nazar/.ssh
        chmod 700 /home/nazar/.ssh
        chmod 600 /home/nazar/.ssh/authorized_keys
        info "Copied root SSH keys to nazar user."
    else
        warn "No /root/.ssh/authorized_keys found. You must manually add SSH keys for the nazar user."
    fi
fi

# --- Phase 2: Harden SSH ---
info "Hardening SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

tee /etc/ssh/sshd_config.d/hardened.conf > /dev/null << 'EOF'
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
KbdInteractiveAuthentication no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding yes
AllowUsers nazar
EOF

sshd -t || error "SSH config invalid! Restoring backup."
info "SSH hardened. Will restart after firewall is set up."

# --- Phase 3: Firewall ---
info "Installing and configuring UFW..."
apt-get update -qq
apt-get install -y -qq ufw > /dev/null

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH"
ufw allow 22000/tcp comment "Syncthing-TCP"
ufw allow 22000/udp comment "Syncthing-UDP"
ufw allow 21027/udp comment "Syncthing-Discovery"
ufw --force enable

# Now safe to restart SSH
systemctl restart sshd
info "SSH restarted with hardened config."

# --- Phase 4: Fail2Ban ---
info "Installing Fail2Ban..."
apt-get install -y -qq fail2ban > /dev/null

tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port = ssh
backend = systemd
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# --- Phase 5: Unattended Upgrades ---
info "Configuring automatic security updates..."
apt-get install -y -qq unattended-upgrades apt-listchanges > /dev/null

tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

# --- Done ---
echo ""
echo "========================================="
echo -e "  ${GREEN}VPS hardening complete!${NC}"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Verify you can SSH as nazar: ssh nazar@<vps-ip>"
echo "  2. Install Tailscale:  curl -fsSL https://tailscale.com/install.sh | sh"
echo "  3. Start Tailscale:    sudo tailscale up"
echo "  4. Install Docker:     bash install-docker.sh"
echo ""
echo "Current firewall rules:"
ufw status numbered
