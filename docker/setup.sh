#!/bin/bash
#
# Nazar Second Brain - Docker Setup Script
# Single debian user + Docker containers
# OpenClaw + Syncthing with shared vault volume
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
#   Or clone repo and run: sudo bash docker/setup.sh
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
echo "║          Nazar Second Brain - Docker Setup                     ║"
echo "║   OpenClaw + Syncthing • Shared Vault • Single User            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# PHASE 1: Pre-flight Checks
# ============================================================================

CURRENT_USER=$(whoami)
log_info "Running as user: $CURRENT_USER"

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

# Check for Docker
if ! command -v docker &> /dev/null; then
    log_info "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# Check for Docker Compose
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose plugin not found. Please install Docker Compose v2."
    exit 1
fi

log_success "Docker and Docker Compose are available"

# ============================================================================
# PHASE 2: Configuration
# ============================================================================

log_step "Configuration Setup"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Determine working directory
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    WORK_DIR="$SCRIPT_DIR"
    log_info "Using docker directory: $WORK_DIR"
elif [ -f "$PROJECT_ROOT/docker/docker-compose.yml" ]; then
    WORK_DIR="$PROJECT_ROOT/docker"
    log_info "Using project docker directory: $WORK_DIR"
else
    # Download files if not present
    log_info "Downloading Docker configuration files..."
    mkdir -p ~/nazar/docker
    WORK_DIR="$HOME/nazar/docker"
    
    BASE_URL="https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker"
    curl -fsSL "$BASE_URL/docker-compose.yml" -o "$WORK_DIR/docker-compose.yml"
    curl -fsSL "$BASE_URL/Dockerfile.openclaw" -o "$WORK_DIR/Dockerfile.openclaw"
    curl -fsSL "$BASE_URL/.env.example" -o "$WORK_DIR/.env.example"
fi

cd "$WORK_DIR"

# Create .env file if not exists
if [ ! -f ".env" ]; then
    log_info "Creating .env configuration file..."
    
    if [ -f ".env.example" ]; then
        cp .env.example .env
    else
        # Create from template
        cat > .env << 'EOF'
# Nazar Second Brain - Environment Configuration
DEPLOYMENT_MODE=sshtunnel
NAZAR_BASE_PATH=/home/debian/nazar
VAULT_HOST_PATH=/home/debian/nazar/vault
OPENCLAW_CONFIG_PATH=/home/debian/nazar/.openclaw
OPENCLAW_WORKSPACE_PATH=/home/debian/nazar/.openclaw/workspace
SYNCTHING_CONFIG_PATH=/home/debian/nazar/syncthing/config
OPENCLAW_GATEWAY_BIND=127.0.0.1
OPENCLAW_GATEWAY_PORT=18789
CONTAINER_UID=1000
CONTAINER_GID=1000
EOF
    fi
fi

# Interactive configuration
log_info "Let's configure your setup..."
echo ""

# Choose deployment mode
echo "Select deployment mode:"
echo "  1) SSH Tunnel (simplest, access via: ssh -L 18789:localhost:18789 user@vps)"
echo "  2) Tailscale (requires auth key, multi-device access)"
read -p "Choice [1]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-1}

if [ "$MODE_CHOICE" = "2" ]; then
    sed -i 's/DEPLOYMENT_MODE=.*/DEPLOYMENT_MODE=tailscale/' .env
    
    # Get Tailscale auth key
    echo ""
    echo "Tailscale Setup:"
    echo "  1. Go to https://login.tailscale.com/admin/settings/keys"
    echo "  2. Create a new auth key (Reusable, Ephemeral recommended)"
    echo "  3. Paste it below (leave empty to configure later):"
    echo ""
    read -p "Tailscale Auth Key: " AUTHKEY
    
    if [ -n "$AUTHKEY" ]; then
        if grep -q "TAILSCALE_AUTHKEY" .env; then
            sed -i "s|TAILSCALE_AUTHKEY=.*|TAILSCALE_AUTHKEY=$AUTHKEY|" .env
        else
            echo "TAILSCALE_AUTHKEY=$AUTHKEY" >> .env
        fi
    fi
    
    # Update bind address for Tailscale mode
    sed -i 's/OPENCLAW_GATEWAY_BIND=.*/OPENCLAW_GATEWAY_BIND=0.0.0.0/' .env
    
    log_info "Tailscale mode configured"
else
    sed -i 's/DEPLOYMENT_MODE=.*/DEPLOYMENT_MODE=sshtunnel/' .env
    sed -i 's/OPENCLAW_GATEWAY_BIND=.*/OPENCLAW_GATEWAY_BIND=127.0.0.1/' .env
    log_info "SSH tunnel mode configured"
fi

# Get hostname
read -p "Hostname for this device [nazar]: " HOSTNAME
HOSTNAME=${HOSTNAME:-nazar}
if grep -q "TAILSCALE_HOSTNAME" .env; then
    sed -i "s/TAILSCALE_HOSTNAME=.*/TAILSCALE_HOSTNAME=$HOSTNAME/" .env
else
    echo "TAILSCALE_HOSTNAME=$HOSTNAME" >> .env
fi

log_success "Configuration saved to .env"

# ============================================================================
# PHASE 3: Create Directory Structure
# ============================================================================

log_step "Creating Directory Structure"

# Create host directories for bind mounts
mkdir -p ~/nazar/vault
mkdir -p ~/nazar/.openclaw/workspace
mkdir -p ~/nazar/syncthing/config

# Get values from .env or use defaults
VAULT_PATH=$(grep "^VAULT_HOST_PATH=" .env 2>/dev/null | cut -d= -f2 || echo "$HOME/nazar/vault")
OPENCLAW_CONFIG=$(grep "^OPENCLAW_CONFIG_PATH=" .env 2>/dev/null | cut -d= -f2 || echo "$HOME/nazar/.openclaw")
OPENCLAW_WORKSPACE=$(grep "^OPENCLAW_WORKSPACE_PATH=" .env 2>/dev/null | cut -d= -f2 || echo "$HOME/nazar/.openclaw/workspace")
SYNCTHING_CONFIG=$(grep "^SYNCTHING_CONFIG_PATH=" .env 2>/dev/null | cut -d= -f2 || echo "$HOME/nazar/syncthing/config")

# Create all directories
mkdir -p "$VAULT_PATH"
mkdir -p "$OPENCLAW_CONFIG"
mkdir -p "$OPENCLAW_WORKSPACE"
mkdir -p "$SYNCTHING_CONFIG"

# Set permissions (UID/GID from env or default 1000)
CONTAINER_UID=$(grep "^CONTAINER_UID=" .env 2>/dev/null | cut -d= -f2 || echo "1000")
CONTAINER_GID=$(grep "^CONTAINER_GID=" .env 2>/dev/null | cut -d= -f2 || echo "1000")

# Use current user if matches, otherwise warn
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

if [ "$CURRENT_UID" != "$CONTAINER_UID" ]; then
    log_warn "Current UID ($CURRENT_UID) differs from CONTAINER_UID ($CONTAINER_UID)"
    log_info "Updating .env to use current user UID/GID"
    sed -i "s/CONTAINER_UID=.*/CONTAINER_UID=$CURRENT_UID/" .env
    sed -i "s/CONTAINER_GID=.*/CONTAINER_GID=$CURRENT_GID/" .env
    CONTAINER_UID=$CURRENT_UID
    CONTAINER_GID=$CURRENT_GID
fi

chown -R "$CONTAINER_UID:$CONTAINER_GID" "$VAULT_PATH"
chown -R "$CONTAINER_UID:$CONTAINER_GID" "$OPENCLAW_CONFIG"
chown -R "$CONTAINER_UID:$CONTAINER_GID" "$OPENCLAW_WORKSPACE"
chown -R "$CONTAINER_UID:$CONTAINER_GID" "$SYNCTHING_CONFIG"

log_success "Directory structure created"

# ============================================================================
# PHASE 4: OpenClaw Configuration
# ============================================================================

log_step "OpenClaw Configuration"

OPENCLAW_JSON="$OPENCLAW_CONFIG/openclaw.json"

if [ ! -f "$OPENCLAW_JSON" ]; then
    log_info "Creating initial OpenClaw configuration..."
    
    # Generate secure token
    TOKEN=$(openssl rand -hex 32)
    
    cat > "$OPENCLAW_JSON" << EOF
{
  "name": "nazar",
  "version": "1.0.0",
  "workspace": {
    "path": "/home/node/.openclaw/workspace"
  },
  "sandbox": {
    "mode": "non-main"
  },
  "gateway": {
    "enabled": true,
    "bind": "0.0.0.0",
    "port": 18789,
    "auth": {
      "type": "token",
      "token": "$TOKEN"
    }
  },
  "models": {},
  "channels": {},
  "tools": {
    "allowed": [
      "read_file",
      "write_file",
      "edit_file",
      "shell",
      "web_search",
      "task"
    ],
    "sandbox": {
      "binds": [
        "/vault:/vault:rw"
      ]
    }
  },
  "limits": {
    "maxConcurrentAgents": 4,
    "maxConcurrentSubagents": 8
  }
}
EOF
    
    chown "$CONTAINER_UID:$CONTAINER_GID" "$OPENCLAW_JSON"
    chmod 600 "$OPENCLAW_JSON"
    
    log_success "OpenClaw configuration created"
    echo ""
    echo "  Gateway Token: $TOKEN"
    echo ""
else
    log_info "OpenClaw configuration already exists"
fi

# ============================================================================
# PHASE 5: Build and Start Services
# ============================================================================

log_step "Building and Starting Services"

# Build and start
docker compose up -d --build

# Wait for services to be healthy
log_info "Waiting for services to be healthy..."
sleep 5

# Check service status
docker compose ps

# ============================================================================
# PHASE 6: Post-Setup Information
# ============================================================================

log_step "Setup Complete!"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  Setup Complete!                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get deployment mode
DEPLOYMENT_MODE=$(grep "^DEPLOYMENT_MODE=" .env 2>/dev/null | cut -d= -f2 || echo "sshtunnel")

if [ "$DEPLOYMENT_MODE" = "tailscale" ]; then
    log_info "Checking Tailscale status..."
    docker compose exec tailscale tailscale status 2>/dev/null || log_warn "Tailscale still connecting..."
fi

# Get Syncthing Device ID
log_info "Syncthing Device ID:"
docker compose exec syncthing syncthing cli show system 2>/dev/null | grep "myID" || log_warn "Syncthing still initializing..."

echo ""
echo "Next Steps:"
echo ""

if [ "$DEPLOYMENT_MODE" = "sshtunnel" ]; then
    echo "1. Access OpenClaw Gateway (from your laptop):"
    echo "   ssh -N -L 18789:localhost:18789 $CURRENT_USER@$(hostname -I | awk '{print $1}')"
    echo "   Then open: http://localhost:18789"
    echo ""
    echo "2. Access Syncthing GUI (from your laptop):"
    echo "   ssh -N -L 8384:localhost:8384 $CURRENT_USER@$(hostname -I | awk '{print $1}')"
    echo "   Then open: http://localhost:8384"
else
    echo "1. Access OpenClaw Gateway:"
    echo "   https://$HOSTNAME/ (via Tailscale)"
    echo ""
    echo "2. Access Syncthing GUI:"
    echo "   http://$HOSTNAME:8384 (via Tailscale)"
fi

echo ""
echo "3. Configure OpenClaw:"
echo "   docker compose exec openclaw openclaw configure"
echo ""
echo "4. Get gateway token:"
echo "   docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | grep token"
echo ""
echo "5. Add your devices to Syncthing:"
echo "   - Share vault folder from your laptop/phone"
echo "   - Accept on this VPS via Syncthing GUI"
echo ""
echo "6. Helper commands:"
echo "   alias nazar-cli='$WORK_DIR/nazar-cli.sh'"
echo "   nazar-cli status      # Show service status"
echo "   nazar-cli logs        # View logs"
echo "   nazar-cli restart     # Restart services"
echo "   nazar-cli backup      # Create backup"
echo ""
echo "Directory Structure:"
echo "  Vault:       $VAULT_PATH"
echo "  OpenClaw:    $OPENCLAW_CONFIG"
echo "  Syncthing:   $SYNCTHING_CONFIG"
echo ""
echo "Management Commands:"
echo "  cd $WORK_DIR"
echo "  docker compose up -d      # Start"
echo "  docker compose down       # Stop"
echo "  docker compose logs -f    # Logs"
echo ""

# ============================================================================
# PHASE 7: Optional Security Hardening
# ============================================================================

log_step "Security Hardening (Optional)"

echo ""
echo "Would you like to apply security hardening?"
echo "This implements OVHcloud VPS security best practices:"
echo "  - SSH keys only (disables password auth)"
echo "  - Firewall (UFW) configuration"
echo "  - Fail2ban intrusion prevention"
echo "  - Automatic security updates"
echo ""
read -p "Apply security hardening? (yes/no): " APPLY_SECURITY

if [ "$APPLY_SECURITY" = "yes" ]; then
    if [ -f "$WORK_DIR/setup-security.sh" ]; then
        sudo bash "$WORK_DIR/setup-security.sh"
    else
        log_info "Downloading security setup script..."
        curl -fsSL "https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh" | sudo bash
    fi
else
    log_warn "Security hardening skipped. Run manually later with:"
    echo "  curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh | sudo bash"
fi

# Save completion marker
echo "Docker setup completed: $(date -Iseconds)" > ~/nazar/.setup-complete
