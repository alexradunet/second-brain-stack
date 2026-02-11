#!/bin/bash
# audit-vps.sh — Security and health audit for Nazar VPS
# Run as root or with sudo. Safe to run anytime — read-only checks.
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
if grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/hardened.conf 2>/dev/null; then
    pass "Root login disabled"
else
    fail "Root login NOT disabled"
fi

if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/hardened.conf 2>/dev/null; then
    pass "Password auth disabled (key-only)"
else
    fail "Password auth still enabled"
fi

if grep -q "AllowUsers nazar" /etc/ssh/sshd_config.d/hardened.conf 2>/dev/null; then
    pass "SSH restricted to 'nazar' user"
else
    warn "SSH not restricted to specific users"
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

# Syncthing ports should NOT be open anymore
if sudo ufw status | grep -q "22000\|21027"; then
    warn "Syncthing ports (22000/21027) still open in UFW — remove them"
else
    pass "No Syncthing ports open (correct — using git sync)"
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

# ── Docker ──
echo "Docker:"
if command -v docker &>/dev/null; then
    pass "Docker installed ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ','))"
else
    fail "Docker not installed"
fi

if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    pass "Docker Compose available"
else
    fail "Docker Compose not available"
fi
echo ""

# ── Containers ──
echo "Nazar Containers:"
if [ -f /srv/nazar/docker-compose.yml ]; then
    GW_STATUS=$(docker inspect --format='{{.State.Status}}' nazar-gateway 2>/dev/null || echo "not found")

    if [ "$GW_STATUS" = "running" ]; then
        pass "nazar-gateway: running"
    else
        fail "nazar-gateway: $GW_STATUS"
    fi

    # Syncthing should NOT be running
    ST_STATUS=$(docker inspect --format='{{.State.Status}}' nazar-syncthing 2>/dev/null || echo "not found")
    if [ "$ST_STATUS" = "not found" ]; then
        pass "nazar-syncthing: removed (correct — using git sync)"
    else
        warn "nazar-syncthing still exists ($ST_STATUS) — remove it"
    fi
else
    warn "No docker-compose.yml at /srv/nazar/ (stack not deployed yet)"
fi
echo ""

# ── Vault Git Sync ──
echo "Vault Git Sync:"
if [ -d /srv/nazar/vault/.git ]; then
    pass "Vault is a git repo"

    # Check shared repository config
    SHARED=$(git -C /srv/nazar/vault config --get core.sharedRepository 2>/dev/null || echo "")
    if [ "$SHARED" = "group" ] || [ "$SHARED" = "1" ]; then
        pass "core.sharedRepository=group"
    else
        warn "core.sharedRepository not set to group (currently: '$SHARED')"
    fi

    # Check remote points to bare repo
    REMOTE=$(git -C /srv/nazar/vault remote get-url origin 2>/dev/null || echo "")
    if [ "$REMOTE" = "/srv/nazar/vault.git" ]; then
        pass "Remote origin points to bare repo"
    elif [ -n "$REMOTE" ]; then
        warn "Remote origin: $REMOTE (expected /srv/nazar/vault.git)"
    else
        fail "No remote origin configured"
    fi

    # Check working copy status
    if git -C /srv/nazar/vault diff --quiet 2>/dev/null && git -C /srv/nazar/vault diff --cached --quiet 2>/dev/null; then
        pass "Working copy clean"
    else
        warn "Working copy has uncommitted changes (auto-commit cron will pick them up)"
    fi
else
    fail "Vault is NOT a git repo"
fi

if [ -d /srv/nazar/vault.git ]; then
    pass "Bare repo exists"
    if [ -x /srv/nazar/vault.git/hooks/post-receive ]; then
        pass "Post-receive hook installed"
    else
        fail "Post-receive hook missing or not executable"
    fi
else
    fail "Bare repo /srv/nazar/vault.git not found"
fi

# Check auto-commit cron
if crontab -u nazar -l 2>/dev/null | grep -q vault-auto-commit; then
    pass "Auto-commit cron installed"
else
    fail "Auto-commit cron not installed for nazar user"
fi

# Check vault group
if getent group vault >/dev/null 2>&1; then
    pass "vault group exists"
    if id -nG nazar 2>/dev/null | grep -qw vault; then
        pass "nazar user in vault group"
    else
        fail "nazar user NOT in vault group"
    fi
else
    fail "vault group does not exist"
fi
echo ""

# ── Secrets ──
echo "Secrets:"
if [ -f /srv/nazar/.env ]; then
    pass ".env file exists"
    if grep -q "sk-ant-\.\.\." /srv/nazar/.env; then
        warn ".env still has placeholder API keys — edit them"
    else
        pass ".env has non-placeholder values"
    fi
else
    warn ".env not found (stack not configured yet)"
fi

# Check vault for leaked secrets
VAULT_LEAKS=$(grep -rl "sk-ant-api\|sk-ant-admin" /srv/nazar/vault/ 2>/dev/null | head -3)
if [ -n "$VAULT_LEAKS" ]; then
    fail "Possible API keys found in vault files:"
    echo "$VAULT_LEAKS" | while read f; do echo "       $f"; done
else
    pass "No API keys detected in vault files"
fi
echo ""

# ── Vault ──
echo "Vault:"
if [ -d /srv/nazar/vault ]; then
    VAULT_OWNER=$(stat -c '%U:%G' /srv/nazar/vault)
    FOLDER_COUNT=$(ls -d /srv/nazar/vault/*/ 2>/dev/null | wc -l)
    if [ "$FOLDER_COUNT" -gt 0 ]; then
        pass "Vault populated ($FOLDER_COUNT folders, owner: $VAULT_OWNER)"
    else
        warn "Vault exists but empty (clone vault content via git)"
    fi
else
    warn "Vault directory not found"
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
