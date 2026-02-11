# Nazar Deploy

Docker deployment stack for the Nazar AI assistant (OpenClaw gateway + Git-based vault sync).

## Architecture

One container, Git-based vault sync:

- **nazar-gateway** — OpenClaw with voice tools (Whisper STT + Piper TTS)
- **vault.git** — Bare Git repo served over SSH for vault synchronization

The gateway bind-mounts the vault working copy. Vault sync uses Git over SSH (through Tailscale) — no extra containers or public ports. A cron job auto-commits agent writes every 5 minutes.

## Quick Start

```bash
# On your VPS
git clone <this-repo> /srv/nazar/deploy
cd /srv/nazar/deploy/deploy
sudo bash scripts/setup-vps.sh

# Run setup wizard
openclaw configure

# Clone vault on your laptop
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/vault
```

## Configuration

`setup-vps.sh` reads these environment variables (all optional, sensible defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `NAZAR_ROOT` | `/srv/nazar` | Base directory for the installation |
| `DEPLOY_USER` | `debian` | OS user that owns files and runs cron jobs |
| `VAULT_GIT_REMOTE` | *(unset)* | External git remote for the vault (e.g. `git@github.com:you/vault.git`). If unset, a local bare repo is created at `$NAZAR_ROOT/vault.git` |

Example — deploy under a different user and path:

```bash
sudo NAZAR_ROOT=/opt/nazar DEPLOY_USER=nazar bash scripts/setup-vps.sh
```

Example — use GitHub as the vault remote instead of a local bare repo:

```bash
sudo VAULT_GIT_REMOTE=git@github.com:youruser/vault.git bash scripts/setup-vps.sh
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Gateway container definition |
| `Dockerfile.nazar` | OpenClaw + voice tools image |
| `openclaw.json` | Agent config (sandbox, gateway, tools) |
| `.env.example` | Secrets template |
| `.nazar_aliases` | Bash aliases for easy command shortcuts |
| `scripts/setup-vps.sh` | VPS bootstrap script (creates vault group, git repos, cron, starts container) |
| `scripts/vault-post-receive-hook` | Git hook template (auto-deploys to working copy on push) |
| `scripts/vault-auto-commit.sh` | Cron script template (commits agent writes every 5 min) |
| `scripts/vault-gitignore` | .gitignore template for the vault |

## Ports

| Port | Service | Access |
|------|---------|--------|
| 443 (HTTPS) | OpenClaw Gateway | `https://<tailscale-hostname>/` (automatic via integrated Tailscale Serve) |
| 22 (SSH) | Git vault sync | `git clone debian@<tailscale-ip>:/srv/nazar/vault.git` (Tailscale only) |

No public ports needed. All access flows through Tailscale.

## Device Pairing

The OpenClaw gateway requires explicit device approval for security.

### First Access from New Browser/Device

1. Open `https://<tailscale-hostname>/` in your browser
2. You'll see "pairing required" or get disconnected with code 1008
3. SSH into VPS and approve your device:

```bash
ssh debian@<tailscale-ip>

# Using aliases
dopenclaw devices list              # Show pending requests
dopenclaw devices approve <id>      # Approve by request ID
drestart                            # Restart gateway to apply

# Or manually approve via files
sudo cat /srv/nazar/data/openclaw/devices/pending.json
# Move request from pending.json to paired.json, then restart
```

### Device Files Location

```
/srv/nazar/data/openclaw/devices/
├── pending.json    # New devices waiting approval
└── paired.json     # Approved devices
```

## Management

### Using Aliases (Recommended)

The setup creates bash aliases for common operations:

```bash
# OpenClaw CLI (runs inside container)
dopenclaw doctor           # Health check
dopenclaw doctor --fix     # Auto-fix issues
dopenclaw configure        # Configure API keys/channels
dopenclaw devices list     # List connected devices
dopenclaw devices approve <id>  # Approve pending device

# Docker compose shortcuts
dnazar ps                  # Container status
dnazar logs -f             # Follow logs
dnazar restart             # Restart gateway
dnazar up -d               # Start services
dnazar down                # Stop services

# Shorthand aliases
dps                        # Same as dnazar ps
dlogs                      # Same as dnazar logs -f
drestart                   # Same as dnazar restart
```

### Using Docker Compose Directly

```bash
cd /srv/nazar/deploy

# Status and logs
docker compose ps
docker compose logs -f openclaw-gateway

# Container lifecycle
docker compose restart openclaw-gateway
docker compose down
docker compose up -d
docker compose build --no-cache

# Execute commands inside container
docker compose exec openclaw-gateway npx openclaw doctor
docker compose exec openclaw-gateway npx openclaw configure

# Shell access
docker compose exec openclaw-gateway bash
```

### Vault Sync Monitoring

```bash
# View sync log
tail -f /srv/nazar/data/git-sync.log

# Check vault status
cd /srv/nazar/vault && git status

# Manual sync
cd /srv/nazar/vault && git pull origin main

# Trigger auto-commit
/srv/nazar/scripts/vault-auto-commit.sh
```
