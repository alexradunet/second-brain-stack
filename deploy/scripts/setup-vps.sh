#!/bin/bash
set -e

DEPLOY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAZAR_ROOT="${NAZAR_ROOT:-/srv/nazar}"
DEPLOY_USER="${DEPLOY_USER:-debian}"
OPENCLAW_SRC="/opt/openclaw"

echo "=== Nazar VPS Setup ==="
echo "Root: $NAZAR_ROOT | User: $DEPLOY_USER"

# 1. Create directory structure
echo "Creating directory structure..."
mkdir -p "$NAZAR_ROOT"/{vault,data/openclaw,scripts}
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$NAZAR_ROOT"

# 2. Set up vault group (shared access: deploy user + container uid 1000)
echo "Setting up vault group..."
if ! getent group vault >/dev/null 2>&1; then
    groupadd vault
fi
usermod -aG vault "$DEPLOY_USER" 2>/dev/null || true

# Set vault ownership and setgid (new files inherit group)
chown -R "$DEPLOY_USER":vault "$NAZAR_ROOT/vault"
chmod 2775 "$NAZAR_ROOT/vault"
find "$NAZAR_ROOT/vault" -type d -exec chmod 2775 {} +
find "$NAZAR_ROOT/vault" -type f -exec chmod 0664 {} +

# 3. Initialize vault as git repo (if not already)
if [ ! -d "$NAZAR_ROOT/vault/.git" ]; then
    echo "Initializing vault git repo..."
    cd "$NAZAR_ROOT/vault"
    cp "$DEPLOY_DIR/scripts/vault-gitignore" .gitignore
    git init
    git config core.sharedRepository group
    git config user.email "nazar@vps"
    git config user.name "Nazar"
    # Remove legacy Syncthing artifacts
    rm -f .stfolder .stignore
    git add -A
    git commit -m "initial vault commit" --allow-empty
else
    echo "Vault git repo already exists"
fi

# 4. Set up vault git remote
if [ -z "${VAULT_GIT_REMOTE:-}" ]; then
    # Local bare repo mode
    if [ ! -d "$NAZAR_ROOT/vault.git" ]; then
        echo "Creating bare repo..."
        git init --bare --shared=group "$NAZAR_ROOT/vault.git"
        chown -R "$DEPLOY_USER":vault "$NAZAR_ROOT/vault.git"

        # Push vault contents to bare repo
        cd "$NAZAR_ROOT/vault"
        git remote add origin "$NAZAR_ROOT/vault.git" 2>/dev/null || git remote set-url origin "$NAZAR_ROOT/vault.git"
        git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null || {
            # Might be on default branch name — detect and push
            BRANCH=$(git branch --show-current)
            git push -u origin "$BRANCH"
        }

        # Install post-receive hook
        cp "$DEPLOY_DIR/scripts/vault-post-receive-hook" "$NAZAR_ROOT/vault.git/hooks/post-receive"
        chmod +x "$NAZAR_ROOT/vault.git/hooks/post-receive"
        chown "$DEPLOY_USER":vault "$NAZAR_ROOT/vault.git/hooks/post-receive"
        echo "Bare repo created with post-receive hook"
    else
        echo "Bare repo already exists"
    fi
else
    # External git remote mode (GitHub, GitLab, etc.)
    echo "Using external git remote: $VAULT_GIT_REMOTE"
    cd "$NAZAR_ROOT/vault"
    git remote add origin "$VAULT_GIT_REMOTE" 2>/dev/null || git remote set-url origin "$VAULT_GIT_REMOTE"
    echo "Vault remote set to $VAULT_GIT_REMOTE"
fi

# 5. Install auto-commit cron script
echo "Installing auto-commit script..."
cp "$DEPLOY_DIR/scripts/vault-auto-commit.sh" "$NAZAR_ROOT/scripts/vault-auto-commit.sh"
chmod +x "$NAZAR_ROOT/scripts/vault-auto-commit.sh"
chown "$DEPLOY_USER":"$DEPLOY_USER" "$NAZAR_ROOT/scripts/vault-auto-commit.sh"

# Install crontab for deploy user (preserving existing entries)
CRON_LINE="*/5 * * * * $NAZAR_ROOT/scripts/vault-auto-commit.sh"
(crontab -u "$DEPLOY_USER" -l 2>/dev/null | grep -v vault-auto-commit; echo "$CRON_LINE") | crontab -u "$DEPLOY_USER" -
echo "Cron installed: vault auto-commit every 5 minutes"

# 6. Clone OpenClaw source (if not already cloned)
if [ ! -d "$OPENCLAW_SRC" ]; then
    echo "Cloning OpenClaw source..."
    git clone https://github.com/openclaw/openclaw.git "$OPENCLAW_SRC"
else
    echo "OpenClaw source already exists at $OPENCLAW_SRC"
fi

# 7. Overlay our custom Dockerfile into the OpenClaw repo
echo "Copying custom Dockerfile..."
cp "$DEPLOY_DIR/Dockerfile.nazar" "$OPENCLAW_SRC/Dockerfile.nazar"

# 8. Copy compose + config to working directory
echo "Copying compose and config files..."
cp "$DEPLOY_DIR/docker-compose.yml" "$NAZAR_ROOT/docker-compose.yml"
cp "$DEPLOY_DIR/openclaw.json" "$NAZAR_ROOT/data/openclaw/openclaw.json"

# If NAZAR_ROOT differs from default, update the sandbox bind path in openclaw.json
if [ "$NAZAR_ROOT" != "/srv/nazar" ]; then
    sed -i "s|/srv/nazar/vault:/vault:rw|$NAZAR_ROOT/vault:/vault:rw|g" "$NAZAR_ROOT/data/openclaw/openclaw.json"
fi

# 9. Create .env from example if not exists
if [ ! -f "$NAZAR_ROOT/.env" ]; then
    cp "$DEPLOY_DIR/.env.example" "$NAZAR_ROOT/.env"
    # Generate gateway token
    TOKEN=$(openssl rand -hex 32)
    sed -i "s/generate-with-openssl-rand-hex-32/$TOKEN/" "$NAZAR_ROOT/.env"
    echo "Generated gateway token."
else
    echo ".env already exists, skipping."
fi
chown "$DEPLOY_USER":"$DEPLOY_USER" "$NAZAR_ROOT/.env"

# 10. Build and start
echo "Building and starting containers..."
cd "$NAZAR_ROOT"
docker compose build
docker compose up -d

# 11. Show status
echo ""
docker compose ps
echo ""
echo "=== Setup Complete ==="
echo "Gateway: https://<tailscale-hostname>/ (access via Tailscale)"
if [ -z "${VAULT_GIT_REMOTE:-}" ]; then
    echo "Vault:   git clone $DEPLOY_USER@<tailscale-ip>:$NAZAR_ROOT/vault.git"
else
    echo "Vault:   $VAULT_GIT_REMOTE"
fi
echo "Config:  $NAZAR_ROOT/.env"
echo ""
echo "Next steps:"
echo "  1. Run 'openclaw configure' to set up models, API keys, and channels"
if [ -z "${VAULT_GIT_REMOTE:-}" ]; then
    echo "  2. Import your vault (if you have one):"
    echo "       cd ~/vault && git init && git remote add origin $DEPLOY_USER@<tailscale-ip>:$NAZAR_ROOT/vault.git"
    echo "       git add -A && git commit -m 'initial vault' && git push -u origin main"
    echo "     Or clone the empty vault: git clone $DEPLOY_USER@<tailscale-ip>:$NAZAR_ROOT/vault.git"
else
    echo "  2. Import your vault (if you have one):"
    echo "       cd ~/vault && git init && git remote add origin $VAULT_GIT_REMOTE"
    echo "       git add -A && git commit -m 'initial vault' && git push -u origin main"
fi
