#!/bin/bash
#
# Nazar VPS Bootstrap Script
# Run this on a fresh VPS to prepare for AI-assisted setup
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/nazar-second-brain/main/bootstrap/bootstrap.sh | bash
#   OR
#   bash bootstrap/bootstrap.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Nazar Second Brain - VPS Bootstrap                   ║"
echo "║         AI-Assisted Setup Preparation                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VERSION=$VERSION_ID
else
    log_error "Cannot detect OS"
    exit 1
fi

log_info "Detected OS: $OS $VERSION"

if [[ ! "$OS" =~ (Debian|Ubuntu) ]]; then
    log_warn "This script is designed for Debian/Ubuntu. Proceed with caution."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Set deploy user
if id "debian" &>/dev/null; then
    DEPLOY_USER="debian"
elif id "ubuntu" &>/dev/null; then
    DEPLOY_USER="ubuntu"
else
    log_info "Creating deploy user 'nazar'..."
    useradd -m -s /bin/bash -G sudo nazar
    DEPLOY_USER="nazar"
fi

log_info "Deploy user: $DEPLOY_USER"

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Install prerequisites
log_info "Installing prerequisites..."

# Check which packages are already installed
PACKAGES="curl git ufw fail2ban jq openssl apt-transport-https ca-certificates gnupg lsb-release"
MISSING_PACKAGES=""

for pkg in $PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    fi
done

if [ -n "$MISSING_PACKAGES" ]; then
    log_info "Installing missing packages:$MISSING_PACKAGES"
    apt-get install -y -qq $MISSING_PACKAGES
else
    log_info "All prerequisite packages already installed"
fi

log_success "Prerequisites installed"

# Check architecture (must be x86_64 or arm64)
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    log_warn "Architecture $ARCH may not be fully supported. x86_64 or arm64 recommended."
fi

# Add swap if low memory (< 2GB) - needed for Docker builds
TOTAL_MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$TOTAL_MEM" -lt 2048 ] && [ ! -f /swapfile ]; then
    log_info "Low memory detected (${TOTAL_MEM}MB). Adding 2GB swap for Docker builds..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_success "Swap enabled"
fi

# Install Node.js 22 LTS (required by OpenClaw)
NEED_NODE_INSTALL=false
if ! command -v node &> /dev/null; then
    NEED_NODE_INSTALL=true
    log_info "Node.js not found. Installing Node.js 22 LTS..."
else
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 22 ]; then
        NEED_NODE_INSTALL=true
        log_warn "Node.js version is $NODE_VERSION (< 22). Upgrading..."
    else
        log_success "Node.js 22+ already installed: $(node --version)"
    fi
fi

if [ "$NEED_NODE_INSTALL" = true ]; then
    # Remove old NodeSource repo if exists (to allow clean upgrade)
    rm -f /etc/apt/sources.list.d/nodesource.list
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs
    log_success "Node.js installed: $(node --version)"
fi

# Check for Claude Code or Kimi Code
log_info "Checking for AI assistant CLI..."

INSTALL_AI=""
if ! command -v claude &> /dev/null && ! command -v kimi &> /dev/null; then
    echo ""
    echo "Which AI assistant would you like to install?"
    echo "  1) Claude Code (Anthropic)"
    echo "  2) Kimi Code (Moonshot AI)"
    echo "  3) Skip (I'll install manually)"
    read -p "Select (1-3): " choice
    
    case $choice in
        1)
            INSTALL_AI="claude"
            ;;
        2)
            INSTALL_AI="kimi"
            ;;
        3)
            log_info "Skipping AI assistant installation"
            ;;
        *)
            log_warn "Invalid choice. Skipping."
            ;;
    esac
else
    if command -v claude &> /dev/null; then
        log_success "Claude Code already installed"
    fi
    if command -v kimi &> /dev/null; then
        log_success "Kimi Code already installed"
    fi
fi

# Install selected AI assistant (or update if already installed)
install_ai_assistant() {
    local AI_NAME=$1
    local AI_PACKAGE=$2
    
    if command -v $AI_NAME &> /dev/null; then
        log_info "$AI_NAME already installed. Updating..."
        npm update -g $AI_PACKAGE > /dev/null 2>&1 || npm install -g $AI_PACKAGE > /dev/null 2>&1
        log_success "$AI_NAME updated: $($AI_NAME --version 2>/dev/null || echo 'unknown version')"
    else
        log_info "Installing $AI_NAME..."
        npm install -g $AI_PACKAGE > /dev/null 2>&1
        log_success "$AI_NAME installed"
    fi
    
    # Ensure global npm bin is in PATH for the deploy user
    NPM_GLOBAL_BIN=$(npm bin -g)
    if ! grep -q "$NPM_GLOBAL_BIN" /home/$DEPLOY_USER/.bashrc 2>/dev/null; then
        echo "export PATH=\"$NPM_GLOBAL_BIN:\$PATH\"" >> /home/$DEPLOY_USER/.bashrc
    fi
    # Also add for root (current session)
    export PATH="$NPM_GLOBAL_BIN:$PATH"
}

if [ "$INSTALL_AI" = "claude" ]; then
    install_ai_assistant "claude" "@anthropic-ai/claude-code"
fi

if [ "$INSTALL_AI" = "kimi" ]; then
    install_ai_assistant "kimi" "@moonshot-ai/kimi-code"
fi

# Create nazar_deploy directory
DEPLOY_DIR="/home/$DEPLOY_USER/nazar_deploy"

if [ -d "$DEPLOY_DIR/.git" ]; then
    log_info "Repository already exists at $DEPLOY_DIR"
    log_info "Pulling latest changes..."
    cd "$DEPLOY_DIR"
    git pull origin $(git symbolic-ref --short HEAD) 2>/dev/null || log_warn "Could not pull updates (may need manual resolution)"
else
    log_info "Creating deploy directory: $DEPLOY_DIR"
    mkdir -p "$DEPLOY_DIR"
fi

# Warn about API keys needed
log_info "Note: You'll need API keys for LLM providers (Anthropic, OpenAI, etc.)"
log_info "      during the 'openclaw configure' step later."

# Ask for repository URL
echo ""
echo "Where should we clone the Nazar repository from?"
echo "  1) GitHub (public repo)"
echo "  2) Custom URL"
echo "  3) Skip (I'll clone manually)"
read -p "Select (1-3): " repo_choice

case $repo_choice in
    1)
        read -p "Enter your GitHub username: " github_user
        REPO_URL="https://github.com/$github_user/second-brain-stack.git"
        ;;
    2)
        read -p "Enter repository URL: " REPO_URL
        ;;
    3)
        REPO_URL=""
        log_info "Skipping clone. You'll need to clone manually."
        ;;
esac

# Clone or update repository
if [ -n "$REPO_URL" ]; then
    if [ -d "$DEPLOY_DIR/.git" ]; then
        log_info "Repository exists. Checking for updates..."
        cd "$DEPLOY_DIR"
        git fetch origin
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/$(git symbolic-ref --short HEAD))
        if [ "$LOCAL" != "$REMOTE" ]; then
            log_info "Updates available. Pulling..."
            git pull origin $(git symbolic-ref --short HEAD)
            log_success "Repository updated"
        else
            log_info "Repository is up to date"
        fi
    else
        log_info "Cloning repository from $REPO_URL..."
        if git clone "$REPO_URL" "$DEPLOY_DIR" 2>/dev/null; then
            log_success "Repository cloned"
        else
            log_error "Failed to clone repository"
            log_info "You can clone manually later with:"
            log_info "  git clone $REPO_URL $DEPLOY_DIR"
        fi
    fi
fi

# Set ownership
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"

# Create/update setup-complete marker with timestamp
echo "Bootstrap completed: $(date -Iseconds)" > "$DEPLOY_DIR/.bootstrap-complete"

# Determine if this is a first run or update
if [ -f "$DEPLOY_DIR/.bootstrap-complete" ] && git -C "$DEPLOY_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    RUN_TYPE="update"
else
    RUN_TYPE="fresh"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
if [ "$RUN_TYPE" = "update" ]; then
    echo "║              Bootstrap Update Complete!                      ║"
else
    echo "║                   Bootstrap Complete!                        ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_success "Prerequisites installed/updated"
log_success "Deploy directory ready: $DEPLOY_DIR"

if command -v claude &> /dev/null || [ "$INSTALL_AI" = "claude" ]; then
    echo ""
    log_info "To start the AI-assisted setup, run:"
    echo ""
    echo -e "  ${GREEN}su - $DEPLOY_USER${NC}"
    echo -e "  ${GREEN}cd nazar_deploy${NC}"
    echo -e "  ${GREEN}claude${NC}"
    echo ""
    echo "Then paste this prompt:"
    echo ""
    echo -e "  ${YELLOW}I'm a new user. Please read the project context and guide me${NC}"
    echo -e "  ${YELLOW}through setting up this VPS for the Nazar Second Brain system.${NC}"
fi

if command -v kimi &> /dev/null || [ "$INSTALL_AI" = "kimi" ]; then
    echo ""
    log_info "To start the AI-assisted setup with Kimi Code, run:"
    echo ""
    echo -e "  ${GREEN}su - $DEPLOY_USER${NC}"
    echo -e "  ${GREEN}cd nazar_deploy${NC}"
    echo -e "  ${GREEN}kimi${NC}"
    echo ""
    echo "Then paste this prompt:"
    echo ""
    echo -e "  ${YELLOW}I'm a new user. Please read the project context and guide me${NC}"
    echo -e "  ${YELLOW}through setting up this VPS for the Nazar Second Brain system.${NC}"
fi

echo ""
log_info "Next steps:"
echo "  1. Switch to the deploy user: su - $DEPLOY_USER"
echo "  2. Navigate to the deploy directory: cd ~/nazar_deploy"
echo "  3. Launch your AI assistant: claude (or kimi)"
echo "  4. Ask the AI to guide you through setup"
echo ""
log_info "Refer to bootstrap/AI_BOOTSTRAP.md for the AI assistant's guide"
echo ""
