#!/bin/bash
#
# OpenClaw Setup for Nazar
# Configures and starts the OpenClaw gateway
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

log_info "Setting up OpenClaw for nazar user..."

# Ensure config directory exists
mkdir -p /home/nazar/.openclaw
chown -R nazar:nazar /home/nazar/.openclaw

# Check if token needs regeneration
CONFIG_FILE="/home/nazar/.openclaw/openclaw.json"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "GENERATE_NEW_TOKEN\|GENERATE_SECURE_TOKEN\|CHANGE_ME\|your-token-here" "$CONFIG_FILE" 2>/dev/null; then
        log_info "Generating secure gateway token..."
        TOKEN=$(openssl rand -hex 32)
        # Use temp file for sed to avoid issues
        sed -i.bak "s/GENERATE_NEW_TOKEN/$TOKEN/g; s/GENERATE_SECURE_TOKEN/$TOKEN/g; s/CHANGE_ME/$TOKEN/g" "$CONFIG_FILE" 2>/dev/null || true
        rm -f "$CONFIG_FILE.bak"
        chown nazar:nazar "$CONFIG_FILE"
    fi
fi

# Enable and start OpenClaw
log_info "Starting OpenClaw service..."
su - nazar -c "systemctl --user enable openclaw"
su - nazar -c "systemctl --user start openclaw"

sleep 2

# Check status
if su - nazar -c "systemctl --user is-active openclaw" >/dev/null 2>&1; then
    log_success "OpenClaw is running!"
else
    log_warn "OpenClaw may not have started. Check logs with:"
    echo "  sudo -u nazar journalctl --user -u openclaw"
fi

# Get Tailscale info
TAILSCALE_HOST=$(tailscale status --json 2>/dev/null | grep -o '"HostName": "[^"]*"' | head -1 | cut -d'"' -f4 || echo "<hostname>")

echo ""
echo "OpenClaw Status:"
echo "  - Service: systemctl --user status openclaw (as nazar)"
echo "  - Logs: journalctl --user -u openclaw -f (as nazar)"
echo "  - Gateway: https://$TAILSCALE_HOST/ (via Tailscale)"
echo ""
echo "Next steps:"
echo "  1. Run 'sudo -u nazar openclaw configure' to set up models and channels"
echo "  2. Access the gateway at https://$TAILSCALE_HOST/"
echo "  3. Approve devices with 'sudo -u nazar openclaw devices approve <id>'"
echo ""
