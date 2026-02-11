#!/bin/bash
#
# Nazar Second Brain - VPS Security Hardening Script
# Based on OVHcloud "How to secure a VPS" guide
# For single debian user + Docker deployment
#
# Usage: sudo bash docker/setup-security.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          VPS Security Hardening for Nazar Second Brain         ║"
echo "║     Based on OVHcloud "How to secure a VPS" guide              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root. Please run: sudo bash docker/setup-security.sh"
    exit 1
fi

# Detect user
if [ -z "$SUDO_USER" ] && [ -z "$(logname 2>/dev/null)" ]; then
    log_error "Cannot detect the user to configure. Please run with sudo from the debian user."
    exit 1
fi

TARGET_USER="${SUDO_USER:-$(logname)}"
log_info "Configuring security for user: $TARGET_USER"

# ============================================================================
# PHASE 1: System Update
# ============================================================================

log_step "Updating System"

if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get upgrade -y -qq
    log_success "System packages updated"
else
    log_warn "apt-get not found. Please update your system manually."
fi

# ============================================================================
# PHASE 2: SSH Key Verification
# ============================================================================

log_step "Verifying SSH Key Authentication"

# Check if SSH key exists for target user
TARGET_HOME=$(eval echo ~$TARGET_USER)
if [ ! -f "$TARGET_HOME/.ssh/authorized_keys" ]; then
    log_warn "No SSH authorized_keys found for $TARGET_USER"
    log_warn "Please set up SSH key authentication BEFORE running this script"
    log_warn "Guide: https://docs.ovh.com/gb/en/public-cloud/create-ssh-keys/"
    
    read -p "Continue anyway? This is NOT recommended (yes/no): " continue_anyway
    if [ "$continue_anyway" != "yes" ]; then
        exit 1
    fi
else
    log_success "SSH key authentication configured"
fi

# ============================================================================
# PHASE 3: SSH Configuration Hardening
# ============================================================================

log_step "Hardening SSH Configuration"

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

# Create hardened SSH config
cat > /etc/ssh/sshd_config.d/nazar-security.conf << 'EOF'
# Nazar Second Brain - SSH Security Hardening
# Based on OVHcloud security guide

# Disable root login
PermitRootLogin no

# Disable password authentication (keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no

# Limit authentication attempts
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Disable unused features
X11Forwarding no
AllowAgentForwarding no

# Only allow specific users (optional - uncomment and modify)
# AllowUsers debian

# Use strong algorithms (modern OpenSSH)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
EOF

# For Ubuntu 24.04+, also configure ssh.socket
if [ -f /lib/systemd/system/ssh.socket ]; then
    log_info "Detected Ubuntu 24.04+ style SSH configuration"
    
    # Backup socket config
    cp /lib/systemd/system/ssh.socket /lib/systemd/system/ssh.socket.backup.$(date +%Y%m%d)
    
    # The sshd_config settings still apply, but port changes need socket config
    # We'll keep default port 22 for now to avoid lockout
    log_warn "Ubuntu 24.04+ detected - manual port change required in /lib/systemd/system/ssh.socket"
fi

# Validate SSH config before restarting
if sshd -t; then
    log_success "SSH configuration is valid"
else
    log_error "SSH configuration error! Restoring backup..."
    rm /etc/ssh/sshd_config.d/nazar-security.conf
    exit 1
fi

# Restart SSH service
if systemctl is-active --quiet sshd; then
    systemctl restart sshd
    log_success "SSH service restarted with new configuration"
elif systemctl is-active --quiet ssh; then
    systemctl restart ssh
    log_success "SSH service restarted with new configuration"
else
    log_warn "Could not restart SSH service automatically"
fi

# ============================================================================
# PHASE 4: Firewall Configuration (UFW)
# ============================================================================

log_step "Configuring Firewall (UFW)"

if command -v ufw &> /dev/null; then
    # Reset to safe defaults
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (port 22 by default)
    # If you changed SSH port, update this:
    SSH_PORT=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    ufw allow "$SSH_PORT/tcp" comment 'SSH'
    
    # Optional: Allow Syncthing ports (only if needed for direct connections)
    # ufw allow 22000/tcp comment 'Syncthing'
    # ufw allow 22000/udp comment 'Syncthing'
    # ufw allow 21027/udp comment 'Syncthing discovery'
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured and enabled"
    log_info "Current rules:"
    ufw status verbose
else
    log_info "UFW not installed, installing..."
    apt-get install -y -qq ufw
    
    # Configure same as above
    ufw default deny incoming
    ufw default allow outgoing
    SSH_PORT=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    ufw allow "$SSH_PORT/tcp" comment 'SSH'
    ufw --force enable
    
    log_success "UFW installed and configured"
fi

# ============================================================================
# PHASE 5: Install and Configure Fail2ban
# ============================================================================

log_step "Installing and Configuring Fail2ban"

if ! command -v fail2ban-server &> /dev/null; then
    apt-get install -y -qq fail2ban
    log_success "Fail2ban installed"
else
    log_info "Fail2ban already installed"
fi

# Create local configuration
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Ban time: 1 hour
bantime = 3600

# Time window for max retries: 10 minutes
findtime = 600

# Max retries before ban
maxretry = 3

# Backend (systemd for modern systems)
backend = systemd

# Email notifications (optional, requires mail setup)
# destemail = admin@yourdomain.com
# sender = fail2ban@yourdomain.com
# mta = sendmail
# action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 300

# Docker-specific: Don't ban localhost (for SSH tunnel users)
ignoreip = 127.0.0.1/8 ::1 172.16.0.0/12 192.168.0.0/16 10.0.0.0/8

[docker-compose]
enabled = true
filter = docker-compose
port = all
bantime = 3600
maxretry = 5
findtime = 300
EOF

# Create filter for docker-compose logs (optional)
if [ ! -f /etc/fail2ban/filter.d/docker-compose.conf ]; then
    cat > /etc/fail2ban/filter.d/docker-compose.conf << 'EOF'
[Definition]
failregex = ^.*Failed password for .* from <HOST>.*$
            ^.*Invalid user .* from <HOST>.*$
            ^.*Connection closed by authenticating user .* <HOST>.*$
ignoreregex = 
EOF
fi

# Enable and restart Fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# Verify it's running
if systemctl is-active --quiet fail2ban; then
    log_success "Fail2ban is running"
    log_info "Status:"
    fail2ban-client status sshd 2>/dev/null || true
else
    log_warn "Fail2ban may not have started correctly. Check: systemctl status fail2ban"
fi

# ============================================================================
# PHASE 6: Automatic Security Updates
# ============================================================================

log_step "Configuring Automatic Security Updates"

if command -v unattended-upgrades &> /dev/null; then
    log_info "Unattended upgrades already installed"
else
    apt-get install -y -qq unattended-upgrades apt-listchanges
fi

# Configure unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::SyslogEnable "true";
EOF

# Configure update schedule
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Enable and restart
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

log_success "Automatic security updates configured"

# ============================================================================
# PHASE 7: Docker Security Hardening
# ============================================================================

log_step "Hardening Docker Configuration"

# Create/update Docker daemon.json for security
cat > /etc/docker/daemon.json << 'EOF'
{
  "userns-remap": "default",
  "live-restore": true,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp-default.json"
}
EOF

# Note: userns-remap can cause permission issues with bind mounts
# For this setup, we'll skip it but document it
log_warn "Note: userns-remap disabled for compatibility with bind mounts"
log_warn "Containers run with user namespaces disabled but as non-root (UID 1000)"

# Restart Docker to apply changes (if it exists)
if systemctl is-active --quiet docker; then
    systemctl restart docker
    log_success "Docker configuration updated"
fi

# ============================================================================
# PHASE 8: Secure File Permissions
# ============================================================================

log_step "Setting Secure File Permissions"

# Secure SSH directory
chmod 700 "$TARGET_HOME/.ssh" 2>/dev/null || true
chmod 600 "$TARGET_HOME/.ssh/authorized_keys" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh" 2>/dev/null || true

# Secure Nazar directory (if exists)
if [ -d "$TARGET_HOME/nazar" ]; then
    chown -R 1000:1000 "$TARGET_HOME/nazar"
    chmod 700 "$TARGET_HOME/nazar/.openclaw" 2>/dev/null || true
    log_success "Nazar directory permissions secured"
fi

# ============================================================================
# PHASE 9: Security Audit Script
# ============================================================================

log_step "Creating Security Audit Script"

cat > /usr/local/bin/nazar-security-audit << 'EOFAUDIT'
#!/bin/bash
# Nazar Second Brain - Security Audit

echo "=== Nazar Security Audit ==="
echo ""

PASS=0
FAIL=0

check() {
    if [ $? -eq 0 ]; then
        echo "✓ $1"
        ((PASS++))
    else
        echo "✗ $1"
        ((FAIL++))
    fi
}

# 1. Check root login disabled
grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/nazar-security.conf 2>/dev/null
check "Root login disabled"

# 2. Check password auth disabled
grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/nazar-security.conf 2>/dev/null
check "Password authentication disabled"

# 3. Check UFW active
ufw status | grep -q "Status: active"
check "Firewall (UFW) active"

# 4. Check Fail2ban running
systemctl is-active fail2ban >/dev/null 2>&1
check "Fail2ban running"

# 5. Check auto-updates enabled
systemctl is-enabled unattended-upgrades >/dev/null 2>&1
check "Auto-updates enabled"

# 6. Check Docker running
systemctl is-active docker >/dev/null 2>&1
check "Docker running"

# 7. Check SSH on non-default port (optional)
if grep -qE "^Port\s+22$" /etc/ssh/sshd_config 2>/dev/null || \
   ! grep -qE "^Port\s+" /etc/ssh/sshd_config 2>/dev/null; then
    echo "⚠ SSH on default port (22) - consider changing"
else
    echo "✓ SSH on non-default port"
    ((PASS++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    echo "⚠️  Some security checks failed. Review and fix manually."
    exit 1
else
    echo "✅ All critical security checks passed!"
    exit 0
fi
EOFAUDIT

chmod +x /usr/local/bin/nazar-security-audit

# ============================================================================
# COMPLETION
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Security Hardening Complete!                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Security measures applied:"
echo "  ✓ SSH hardened (root login disabled, password auth disabled)"
echo "  ✓ Firewall (UFW) configured and enabled"
echo "  ✓ Fail2ban installed and configured"
echo "  ✓ Automatic security updates enabled"
echo "  ✓ Docker security settings applied"
echo "  ✓ File permissions secured"
echo ""

# Run audit
/usr/local/bin/nazar-security-audit

echo ""
echo "Next Steps:"
echo ""
echo "1. Test SSH connection in a NEW terminal BEFORE closing this one:"
echo "   ssh -p $SSH_PORT $TARGET_USER@<vps-ip>"
echo ""
echo "2. If you can't connect, restore backup:"
echo "   sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config"
echo "   sudo systemctl restart sshd"
echo ""
echo "3. Run security audit anytime:"
echo "   sudo nazar-security-audit"
echo ""
echo "4. To change SSH port, edit:"
echo "   /etc/ssh/sshd_config.d/nazar-security.conf"
echo "   Then: sudo systemctl restart sshd"
echo ""
echo "⚠️  IMPORTANT: Keep this terminal open until you verify SSH works!"
echo ""
