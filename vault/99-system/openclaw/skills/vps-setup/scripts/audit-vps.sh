#!/bin/bash
# audit-vps.sh — Security and health audit for Nazar VPS
# Run as root or with sudo. Safe to run anytime — read-only checks.
#
# Current architecture: systemd user services (openclaw, syncthing)
# running under the 'nazar' user, vault synced via Syncthing over Tailscale.
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓${NC} $*"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}!${NC} $*"; ((WARN++)); }

echo ""
echo "═══════════════════════════════════════"
echo "  Nazar VPS Security & Health Audit"
echo "═══════════════════════════════════════"
echo ""

# ── SSH ──
echo "SSH Configuration:"
# Support both config filenames (bootstrap uses nazar.conf, legacy uses hardened.conf)
SSH_CONF=""
if [ -f /etc/ssh/sshd_config.d/nazar.conf ]; then
    SSH_CONF="/etc/ssh/sshd_config.d/nazar.conf"
elif [ -f /etc/ssh/sshd_config.d/hardened.conf ]; then
    SSH_CONF="/etc/ssh/sshd_config.d/hardened.conf"
fi

if [ -n "$SSH_CONF" ]; then
    if grep -q "PermitRootLogin no" "$SSH_CONF" 2>/dev/null; then
        pass "Root login disabled"
    else
        fail "Root login NOT disabled"
    fi

    if grep -q "PasswordAuthentication no" "$SSH_CONF" 2>/dev/null; then
        pass "Password auth disabled (key-only)"
    else
        fail "Password auth still enabled"
    fi

    if grep -q "AllowUsers debian" "$SSH_CONF" 2>/dev/null; then
        pass "SSH restricted to 'debian' user"
    else
        warn "SSH not restricted to specific users"
    fi
else
    fail "No SSH hardening config found (expected nazar.conf or hardened.conf)"
fi
echo ""

# ── Firewall ──
echo "Firewall:"
if sudo ufw status | grep -q "Status: active"; then
    pass "UFW firewall active"
else
    fail "UFW firewall NOT active"
fi

if sudo ufw status | grep -q "tailscale0.*22"; then
    pass "SSH locked to Tailscale interface"
elif sudo ufw status | grep -q "22/tcp.*ALLOW.*Anywhere"; then
    warn "SSH open on public interface (consider locking to Tailscale)"
else
    warn "SSH rule not found"
fi

if ! sudo ufw status | grep -q "18789"; then
    pass "Gateway port (18789) not exposed publicly"
else
    fail "Gateway port (18789) exposed publicly — should be 127.0.0.1 only"
fi

# Syncthing communicates over Tailscale, no UFW ports needed
if sudo ufw status | grep -q "22000\|21027"; then
    warn "Syncthing ports (22000/21027) still open in UFW — remove them (Syncthing uses Tailscale)"
else
    pass "No Syncthing ports in UFW (correct — Syncthing uses Tailscale)"
fi
echo ""

# ── Fail2Ban ──
echo "Fail2Ban:"
if systemctl is-active --quiet fail2ban; then
    pass "Fail2Ban running"
    BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    if [ -n "$BANNED" ]; then
        echo "       Currently banned IPs: $BANNED"
    fi
else
    fail "Fail2Ban not running"
fi
echo ""

# ── Auto-Updates ──
echo "Automatic Updates:"
if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
    pass "Unattended upgrades enabled"
else
    fail "Unattended upgrades NOT enabled"
fi
echo ""

# ── Tailscale ──
echo "Tailscale:"
if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        pass "Tailscale connected (IP: $TS_IP)"
    else
        fail "Tailscale installed but not connected"
    fi
else
    fail "Tailscale not installed"
fi
echo ""

# ── Users ──
echo "Users:"
if id "nazar" &>/dev/null; then
    pass "nazar service user exists"
else
    fail "nazar service user not found"
fi

if id "debian" &>/dev/null; then
    pass "debian admin user exists"
else
    fail "debian admin user not found"
fi

# Check nazar has no sudo
if sudo -l -U nazar 2>&1 | grep -q "not allowed\|may not run"; then
    pass "nazar user has no sudo access"
else
    warn "nazar user may have sudo access — review permissions"
fi

# Check nazar password locked
if passwd -S nazar 2>/dev/null | grep -q "L"; then
    pass "nazar user password locked"
else
    warn "nazar user password not locked"
fi

# Check home directory permissions
NAZAR_PERMS=$(stat -c "%a" /home/nazar 2>/dev/null || echo "")
if [ "$NAZAR_PERMS" = "700" ]; then
    pass "nazar home directory restricted (700)"
else
    warn "nazar home directory permissions: $NAZAR_PERMS (expected 700)"
fi
echo ""

# ── Systemd Services ──
echo "Services (systemd user — nazar):"
if su - nazar -c "systemctl --user is-active openclaw" 2>/dev/null | grep -q "active"; then
    pass "openclaw.service is running"
else
    fail "openclaw.service is NOT running"
fi

if su - nazar -c "systemctl --user is-enabled openclaw" 2>/dev/null | grep -q "enabled"; then
    pass "openclaw.service is enabled (starts on boot)"
else
    warn "openclaw.service is NOT enabled"
fi

if su - nazar -c "systemctl --user is-active syncthing" 2>/dev/null | grep -q "active"; then
    pass "syncthing.service is running"
else
    fail "syncthing.service is NOT running"
fi

if su - nazar -c "systemctl --user is-enabled syncthing" 2>/dev/null | grep -q "enabled"; then
    pass "syncthing.service is enabled (starts on boot)"
else
    warn "syncthing.service is NOT enabled"
fi

# Check lingering enabled (services run without login)
if loginctl show-user nazar 2>/dev/null | grep -q "Linger=yes"; then
    pass "Lingering enabled for nazar (services survive logout)"
else
    warn "Lingering not enabled for nazar — services may stop on logout"
fi
echo ""

# ── OpenClaw Config ──
echo "OpenClaw Configuration:"
OC_CONFIG="/home/nazar/.openclaw/openclaw.json"
if [ -f "$OC_CONFIG" ]; then
    pass "openclaw.json exists"

    OC_PERMS=$(stat -c "%a" /home/nazar/.openclaw 2>/dev/null || echo "")
    if [ "$OC_PERMS" = "700" ]; then
        pass "Config directory restricted (700)"
    else
        warn "Config directory permissions: $OC_PERMS (expected 700)"
    fi

    if grep -qE "GENERATE_NEW_TOKEN|GENERATE_SECURE_TOKEN|CHANGE_ME|your-token-here" "$OC_CONFIG" 2>/dev/null; then
        fail "Config still has placeholder token — run setup-openclaw.sh"
    else
        pass "Gateway token is set (no placeholders)"
    fi
else
    fail "openclaw.json not found at $OC_CONFIG"
fi
echo ""

# ── Vault ──
echo "Vault:"
if [ -d /home/nazar/vault ]; then
    VAULT_OWNER=$(stat -c '%U:%G' /home/nazar/vault)
    FOLDER_COUNT=$(ls -d /home/nazar/vault/*/ 2>/dev/null | wc -l)
    if [ "$FOLDER_COUNT" -gt 0 ]; then
        pass "Vault populated ($FOLDER_COUNT folders, owner: $VAULT_OWNER)"
    else
        warn "Vault exists but empty (set up Syncthing to sync content)"
    fi

    if [ "$VAULT_OWNER" = "nazar:nazar" ]; then
        pass "Vault owned by nazar:nazar"
    else
        warn "Vault ownership: $VAULT_OWNER (expected nazar:nazar)"
    fi
else
    fail "Vault directory not found at /home/nazar/vault/"
fi
echo ""

# ── Secrets ──
echo "Secrets:"
if [ -d /home/nazar/vault ]; then
    VAULT_LEAKS=$(grep -rl "sk-ant-api\|sk-ant-admin" /home/nazar/vault/ 2>/dev/null | head -3)
    if [ -n "$VAULT_LEAKS" ]; then
        fail "Possible API keys found in vault files:"
        echo "$VAULT_LEAKS" | while read f; do echo "       $f"; done
    else
        pass "No API keys detected in vault files"
    fi
fi
echo ""

# ── System ──
echo "System:"
TOTAL_MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
AVAIL_MEM=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
DISK_USE=$(df -h / | awk 'NR==2 {print $5}')

echo "       Memory: ${AVAIL_MEM}MB available / ${TOTAL_MEM}MB total"
echo "       Disk:   ${DISK_USE} used"

if swapon --show | grep -q "/"; then
    SWAP_SIZE=$(swapon --show --bytes | awk 'NR==2 {print int($3/1024/1024)}')"MB"
    pass "Swap enabled ($SWAP_SIZE)"
elif [ "$TOTAL_MEM" -lt 2048 ]; then
    warn "No swap and <2GB RAM — consider adding swap"
else
    pass "No swap needed (${TOTAL_MEM}MB RAM)"
fi

UPTIME=$(uptime -p)
echo "       Uptime:  $UPTIME"
echo ""

# ── Summary ──
echo "═══════════════════════════════════════"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}"
echo "═══════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo -e "\n  ${RED}Action required — fix the failed checks above.${NC}"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "\n  ${YELLOW}Review the warnings above.${NC}"
    exit 0
else
    echo -e "\n  ${GREEN}All checks passed!${NC}"
    exit 0
fi
