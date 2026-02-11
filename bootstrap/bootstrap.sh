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
apt-get install -y -qq \
    curl \
    git \
    ufw \
    fail2ban \
    jq \
    openssl \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

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

# Install Node.js 20 LTS
if ! command -v node &> /dev/null; then
    log_info "Installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs
    log_success "Node.js installed: $(node --version)"
else
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        log_warn "Node.js version is < 18. Upgrading..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
        apt-get install -y -qq nodejs
        log_success "Node.js upgraded: $(node --version)"
    else
        log_success "Node.js already installed: $(node --version)"
    fi
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

# Install selected AI assistant
if [ "$INSTALL_AI" = "claude" ]; then
    log_info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code > /dev/null 2>&1
    # Ensure global npm bin is in PATH for the deploy user
    NPM_GLOBAL_BIN=$(npm bin -g)
    if ! grep -q "$NPM_GLOBAL_BIN" /home/$DEPLOY_USER/.bashrc 2>/dev/null; then
        echo "export PATH=\"$NPM_GLOBAL_BIN:\$PATH\"" >> /home/$DEPLOY_USER/.bashrc
    fi
    # Also add for root (current session)
    export PATH="$NPM_GLOBAL_BIN:$PATH"
    # Verify installation
    if command -v claude &> /dev/null; then
        log_success "Claude Code installed: $(claude --version 2>/dev/null || echo 'unknown version')"
    else
        log_warn "Claude Code installed but not in PATH. Run: export PATH=\"$NPM_GLOBAL_BIN:\$PATH\""
    fi
fi

if [ "$INSTALL_AI" = "kimi" ]; then
    log_info "Installing Kimi Code..."
    npm install -g @moonshot-ai/kimi-code > /dev/null 2>&1
    # Ensure global npm bin is in PATH for the deploy user
    NPM_GLOBAL_BIN=$(npm bin -g)
    if ! grep -q "$NPM_GLOBAL_BIN" /home/$DEPLOY_USER/.bashrc 2>/dev/null; then
        echo "export PATH=\"$NPM_GLOBAL_BIN:\$PATH\"" >> /home/$DEPLOY_USER/.bashrc
    fi
    # Also add for root (current session)
    export PATH="$NPM_GLOBAL_BIN:$PATH"
    # Verify installation
    if command -v kimi &> /dev/null; then
        log_success "Kimi Code installed"
    else
        log_warn "Kimi Code installed but not in PATH. Run: export PATH=\"$NPM_GLOBAL_BIN:\$PATH\""
    fi
fi

# Create nazar_deploy directory
DEPLOY_DIR="/home/$DEPLOY_USER/nazar_deploy"
log_info "Creating deploy directory: $DEPLOY_DIR"

mkdir -p "$DEPLOY_DIR"

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

# Clone repository
if [ -n "$REPO_URL" ]; then
    log_info "Cloning repository from $REPO_URL..."
    if git clone "$REPO_URL" "$DEPLOY_DIR" 2>/dev/null; then
        log_success "Repository cloned"
    else
        log_error "Failed to clone repository"
        log_info "You can clone manually later with:"
        log_info "  git clone $REPO_URL $DEPLOY_DIR"
    fi
fi

# Set ownership
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"

# Create setup-complete marker
touch "$DEPLOY_DIR/.bootstrap-complete"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Bootstrap Complete!                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_success "Prerequisites installed"
log_success "Deploy directory created: $DEPLOY_DIR"

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
