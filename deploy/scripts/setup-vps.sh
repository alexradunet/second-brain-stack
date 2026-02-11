#!/bin/bash
set -e

DEPLOY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAZAR_ROOT="/srv/nazar"
OPENCLAW_SRC="/opt/openclaw"

echo "=== Nazar VPS Setup ==="

# 1. Create directory structure
echo "Creating directory structure..."
mkdir -p "$NAZAR_ROOT"/{vault,data/openclaw,data/syncthing}
chown -R 1000:1000 "$NAZAR_ROOT"

# 2. Clone OpenClaw source (if not already cloned)
if [ ! -d "$OPENCLAW_SRC" ]; then
    echo "Cloning OpenClaw source..."
    git clone https://github.com/openclaw/openclaw.git "$OPENCLAW_SRC"
else
    echo "OpenClaw source already exists at $OPENCLAW_SRC"
fi

# 3. Overlay our custom Dockerfile into the OpenClaw repo
echo "Copying custom Dockerfile..."
cp "$DEPLOY_DIR/Dockerfile.nazar" "$OPENCLAW_SRC/Dockerfile.nazar"

# 4. Copy compose + config to working directory
echo "Copying compose and config files..."
cp "$DEPLOY_DIR/docker-compose.yml" "$NAZAR_ROOT/docker-compose.yml"
cp "$DEPLOY_DIR/openclaw.json" "$NAZAR_ROOT/data/openclaw/openclaw.json"

# 5. Create .env from example if not exists
if [ ! -f "$NAZAR_ROOT/.env" ]; then
    cp "$DEPLOY_DIR/.env.example" "$NAZAR_ROOT/.env"
    # Generate gateway token
    TOKEN=$(openssl rand -hex 32)
    sed -i "s/generate-with-openssl-rand-hex-32/$TOKEN/" "$NAZAR_ROOT/.env"
    echo "Generated gateway token."
    echo "Edit $NAZAR_ROOT/.env with your API keys before starting."
else
    echo ".env already exists, skipping."
fi
chown nazar:nazar "$NAZAR_ROOT/.env"

# 6. Build and start
echo "Building and starting containers..."
cd "$NAZAR_ROOT"
docker compose build
docker compose up -d

# 7. Show status
echo ""
docker compose ps
echo ""
echo "=== Setup Complete ==="
echo "Gateway:   http://127.0.0.1:18789 (access via Tailscale)"
echo "Syncthing: http://127.0.0.1:8384  (access via Tailscale)"
echo "Config:    $NAZAR_ROOT/.env"
echo ""
echo "Next steps:"
echo "  1. Edit $NAZAR_ROOT/.env with your API keys"
echo "  2. Connect Syncthing to sync your vault"
echo "  3. docker compose restart (after editing .env)"
