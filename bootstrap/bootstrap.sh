#!/bin/bash
#
# Nazar Second Brain - Simplified Bootstrap Script
# 
# Architecture:
#   - debian: System administrator user (sudo access)
#   - nazar:  Service user for OpenClaw + Syncthing (no sudo)
#   - Vault synced via Syncthing (not Git)
#   - OpenClaw runs directly via npm (not Docker)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          Nazar Second Brain - Simplified Setup                 ║"
echo "║          No Docker • Syncthing Sync • Simple & Secure          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# PHASE 1: Pre-flight Checks
# ============================================================================

CURRENT_USER=$(whoami)
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root. Please run: sudo bash bootstrap.sh"
    exit 1
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    log_info "Detected OS: $OS"
else
    log_error "Cannot detect OS"
    exit 1
fi

if [[ ! "$OS" =~ (Debian|Ubuntu) ]]; then
    log_warn "This script is designed for Debian/Ubuntu. Proceed with caution."
fi

# ============================================================================
# PHASE 2: System Update & Base Packages
# ============================================================================

log_info "Updating package lists..."
apt-get update -qq

log_info "Installing base packages..."
apt-get install -y -qq curl git ufw fail2ban jq openssl \
    apt-transport-https ca-certificates gnupg lsb-release

log_success "Base packages installed"

# ============================================================================
# PHASE 3: Create Users
# ============================================================================

# Create debian admin user if not exists
if ! id "debian" &>/dev/null; then
    log_info "Creating admin user 'debian'..."
    useradd -m -s /bin/bash -G sudo debian
    # Allow passwordless sudo for debian
    echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian
    chmod 440 /etc/sudoers.d/debian
fi

# Create nazar service user if not exists
if ! id "nazar" &>/dev/null; then
    log_info "Creating service user 'nazar'..."
    useradd -m -s /bin/bash nazar
    # No sudo access for nazar - security principle
fi

log_success "Users created: debian (admin), nazar (service)"

# ============================================================================
# PHASE 4: SSH Key Setup (copy from root if exists)
# ============================================================================

if [ -f /root/.ssh/authorized_keys ]; then
    log_info "Copying SSH keys to debian user..."
    mkdir -p /home/debian/.ssh
    cp /root/.ssh/authorized_keys /home/debian/.ssh/
    chown -R debian:debian /home/debian/.ssh
    chmod 700 /home/debian/.ssh
    chmod 600 /home/debian/.ssh/authorized_keys
fi

# ============================================================================
# PHASE 5: Install Node.js 22
# ============================================================================

if ! command -v node &> /dev/null || [ "$(node --version | cut -d'v' -f2 | cut -d'.' -f1)" -lt 22 ]; then
    log_info "Installing Node.js 22..."
    rm -f /etc/apt/sources.list.d/nodesource.list
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs
fi

log_success "Node.js installed: $(node --version)"

# ============================================================================
# PHASE 6: Install OpenClaw Globally
# ============================================================================

if ! command -v openclaw &> /dev/null; then
    log_info "Installing OpenClaw..."
    npm install -g openclaw@latest
fi

log_success "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'installed')"

# ============================================================================
# PHASE 7: Install Syncthing
# ============================================================================

if ! command -v syncthing &> /dev/null; then
    log_info "Installing Syncthing..."
    # Add Syncthing repository
    curl -s https://syncthing.net/release-key.txt | gpg --dearmor > /usr/share/keyrings/syncthing-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" > /etc/apt/sources.list.d/syncthing.list
    apt-get update -qq
    apt-get install -y -qq syncthing
fi

log_success "Syncthing installed: $(syncthing --version | head -1)"

# ============================================================================
# PHASE 8: Security Hardening
# ============================================================================

log_info "Applying security hardening..."

# SSH hardening
cat > /etc/ssh/sshd_config.d/nazar.conf << 'EOF'
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
AllowTcpForwarding yes

# Only allow debian and nazar users
AllowUsers debian
EOF

# Validate SSH config
sshd -t || { log_error "SSH config invalid!"; exit 1; }
systemctl restart sshd
log_success "SSH hardened"

# Firewall setup
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
log_success "Firewall enabled (SSH only for now)"

# Fail2Ban
cat > /etc/fail2ban/jail.local << 'EOF'
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
log_success "Fail2Ban enabled"

# Auto-updates
apt-get install -y -qq unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades
log_success "Auto-updates enabled"

# ============================================================================
# PHASE 9: Install Tailscale
# ============================================================================

if ! command -v tailscale &> /dev/null; then
    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

log_success "Tailscale installed"
log_info "To enable Tailscale, run: sudo tailscale up"

# ============================================================================
# PHASE 10: Setup Nazar User Environment
# ============================================================================

log_info "Setting up nazar user environment..."

# Create directory structure
mkdir -p /home/nazar/{vault,.config/openclaw,.local/state/syncthing}
chown -R nazar:nazar /home/nazar

# Set up OpenClaw config directory
export HOME=/home/nazar
export USER=nazar

# Initialize OpenClaw config (as nazar user)
su - nazar -c "mkdir -p ~/.openclaw"

# Create initial openclaw.json config
cat > /home/nazar/.openclaw/openclaw.json << 'EOF'
{
  "name": "nazar",
  "workspace": {
    "path": "/home/nazar/vault/99-system/openclaw/workspace"
  },
  "sandbox": {
    "mode": "non-main"
  },
  "gateway": {
    "enabled": true,
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "type": "token",
      "token": "GENERATE_NEW_TOKEN"
    },
    "tailscale": {
      "mode": "serve"
    }
  },
  "models": {},
  "channels": {},
  "tools": {
    "allowed": ["read_file", "write_file", "edit_file", "shell", "web_search", "task"],
    "sandbox": {
      "binds": [
        "/home/nazar/vault:/vault:rw"
      ]
    }
  },
  "limits": {
    "maxConcurrentAgents": 4,
    "maxConcurrentSubagents": 8
  }
}
EOF

# Generate secure token
TOKEN=$(openssl rand -hex 32)
sed -i "s/GENERATE_NEW_TOKEN/$TOKEN/" /home/nazar/.openclaw/openclaw.json
chown -R nazar:nazar /home/nazar/.openclaw

# ============================================================================
# PHASE 11: Create Systemd Services
# ============================================================================

log_info "Creating systemd services..."

# OpenClaw service (user service)
mkdir -p /etc/systemd/user

cat > /etc/systemd/user/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw Gateway (Nazar)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/openclaw gateway --bind loopback --port 18789 --tailscale serve
Restart=always
RestartSec=5
Environment="HOME=%h"
Environment="VAULT_PATH=/home/nazar/vault"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
WorkingDirectory=/home/nazar
# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/nazar/vault /home/nazar/.openclaw

[Install]
WantedBy=default.target
EOF

# Syncthing service (user service)  
cat > /etc/systemd/user/syncthing.service << 'EOF'
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization
Documentation=man:syncthing(1)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --logflags=0
Restart=on-failure
RestartSec=5
SuccessExitStatus=3 4
WorkingDirectory=/home/nazar
Environment="HOME=/home/nazar"
Environment="STNORESTART=1"
# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/nazar/.local/state/syncthing /home/nazar/vault

[Install]
WantedBy=default.target
EOF

# Enable lingering for nazar user (services run without login)
loginctl enable-linger nazar

log_success "Systemd services created"

# ============================================================================
# PHASE 12: Install Voice Tools (Whisper + Piper)
# ============================================================================

log_info "Installing voice processing tools..."

# Install Python and dependencies
apt-get install -y -qq python3 python3-pip python3-venv ffmpeg

# Create voice environment as nazar user
su - nazar -c '
    python3 -m venv ~/.local/venv-voice
    source ~/.local/venv-voice/bin/activate
    pip install -q openai-whisper piper-tts
'

# Download models
mkdir -p /home/nazar/.local/share/whisper /home/nazar/.local/share/piper
chown -R nazar:nazar /home/nazar/.local

log_success "Voice tools installed"

# ============================================================================
# PHASE 13: Create Helper Scripts
# ============================================================================

cat > /home/nazar/.bashrc << 'EOF'
# Nazar user environment

# Aliases
alias oc='openclaw'
alias oc-logs='journalctl --user -u openclaw -f'
alias sync-logs='journalctl --user -u syncthing -f'
alias vault='cd ~/vault'

# Environment
export VAULT_PATH=/home/nazar/vault
export PATH="$HOME/.local/venv-voice/bin:$PATH"

# Welcome message
echo "Welcome, Nazar!"
echo "  Vault: ~/vault"
echo "  OpenClaw: oc configure | oc-logs"
echo "  Syncthing: syncthing cli | sync-logs"
EOF

chown nazar:nazar /home/nazar/.bashrc

# Create admin helper scripts for debian user
mkdir -p /home/debian/bin
cat > /home/debian/bin/nazar-logs << 'EOF'
#!/bin/bash
# View OpenClaw logs
sudo -u nazar journalctl --user -u openclaw -f
EOF

cat > /home/debian/bin/nazar-restart << 'EOF'
#!/bin/bash
# Restart OpenClaw service
sudo -u nazar systemctl --user restart openclaw
EOF

cat > /home/debian/bin/nazar-status << 'EOF'
#!/bin/bash
# Check Nazar service status
echo "=== OpenClaw ==="
sudo -u nazar systemctl --user status openclaw --no-pager
echo ""
echo "=== Syncthing ==="
sudo -u nazar systemctl --user status syncthing --no-pager
EOF

chmod +x /home/debian/bin/*
chown -R debian:debian /home/debian/bin

# Add to PATH
echo 'export PATH="$HOME/bin:$PATH"' >> /home/debian/.bashrc

# ============================================================================
# PHASE 14: Final Setup
# ============================================================================

# ============================================================================
# PHASE 15: Security Hardening
# ============================================================================

log_info "Applying additional security hardening..."

# Lock nazar user password (no password login allowed)
passwd -l nazar 2>/dev/null || true

# Restrict nazar user home directory permissions
chmod 700 /home/nazar

# Create security directories
mkdir -p /home/nazar/.openclaw/devices
chmod 700 /home/nazar/.openclaw

# Set proper ownership
chown -R nazar:nazar /home/nazar
chown -R debian:debian /home/debian

# ============================================================================
# PHASE 16: Create Security Audit Script
# ============================================================================

cat > /home/debian/bin/nazar-audit << 'EOFAUDIT'
#!/bin/bash
# Security audit for Nazar Second Brain

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
grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/nazar.conf 2>/dev/null
check "Root login disabled"

# 2. Check password auth disabled
grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/nazar.conf 2>/dev/null
check "Password authentication disabled"

# 3. Check nazar has no sudo
sudo -l -U nazar 2>&1 | grep -q "not allowed" 
check "nazar user has no sudo access"

# 4. Check nazar password locked
passwd -S nazar 2>/dev/null | grep -q "L"
check "nazar user password locked"

# 5. Check firewall active
ufw status | grep -q "Status: active"
check "UFW firewall active"

# 6. Check fail2ban running
systemctl is-active fail2ban >/dev/null 2>&1
check "Fail2Ban running"

# 7. Check auto-updates enabled
systemctl is-enabled unattended-upgrades >/dev/null 2>&1
check "Auto-updates enabled"

# 8. Check Tailscale connected
tailscale status >/dev/null 2>&1
check "Tailscale connected"

# 9. Check home directory permissions
stat -c "%a" /home/nazar | grep -q "700"
check "nazar home directory restricted (700)"

# 10. Check OpenClaw config permissions
stat -c "%a" /home/nazar/.openclaw 2>/dev/null | grep -q "700"
check "OpenClaw config directory restricted (700)"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    echo "⚠️  Some security checks failed. Review and fix manually."
    exit 1
else
    echo "✅ All security checks passed!"
    exit 0
fi
EOFAUDIT

chmod +x /home/debian/bin/nazar-audit
chown debian:debian /home/debian/bin/nazar-audit

# Run initial audit
log_info "Running security audit..."
bash /home/debian/bin/nazar-audit || log_warn "Some security checks failed - review manually"

# Mark bootstrap complete
echo "Bootstrap completed: $(date -Iseconds)" > /home/debian/.nazar-bootstrap
echo "Bootstrap completed: $(date -Iseconds)" > /home/nazar/.bootstrap-complete

# ============================================================================
# COMPLETION
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  Bootstrap Complete!                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "Users created: debian (admin), nazar (service)"
log_success "Services ready: OpenClaw, Syncthing"
log_success "Security: SSH hardened, Firewall active, Fail2Ban enabled"
echo ""
echo "Next Steps:"
echo ""
echo "1. Start Tailscale:"
echo "   sudo tailscale up"
echo ""
echo "2. Clone this repository as debian user:"
echo "   su - debian"
echo "   git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar"
echo ""
echo "3. Copy vault to nazar user:"
echo "   sudo cp -r ~/nazar/vault/* /home/nazar/vault/"
echo "   sudo chown -R nazar:nazar /home/nazar/vault"
echo ""
echo "4. Start services:"
echo "   sudo -u nazar systemctl --user enable --now syncthing"
echo "   sudo -u nazar systemctl --user enable --now openclaw"
echo ""
echo "5. Configure OpenClaw:"
echo "   sudo -u nazar openclaw configure"
echo ""
echo "6. Set up Syncthing:"
echo "   - Access http://<tailscale-ip>:8384"
echo "   - Add your devices"
echo "   - Share ~/vault folder"
echo ""
echo "Access Points:"
echo "  - Gateway: https://<tailscale-hostname>/"
echo "  - Syncthing: http://<tailscale-ip>:8384"
echo "  - SSH: ssh debian@<tailscale-ip>"
echo ""
echo "Security Hardening (Optional):"
echo "  sudo bash ~/nazar/system/scripts/setup-all-security.sh"
echo "  # Includes: audit logging, file integrity, canary tokens, encrypted backups"
echo ""
