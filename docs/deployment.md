# Deployment Guide

How to go from a fresh Debian 13 VPS to a running Nazar instance.

## What Gets Deployed

One Docker container on the VPS plus Git-based vault sync:

1. **nazar-gateway** — OpenClaw + voice tools (Whisper, Piper), vault at `/vault`
2. **vault.git** — Bare Git repo served over SSH for vault synchronization

The gateway bind-mounts the vault working copy at `/srv/nazar/vault/`. Vault sync uses Git over SSH (through Tailscale) — no extra containers or public ports needed.

## Prerequisites

- A Debian 13 VPS (OVH, Hetzner, or similar)
- Root SSH access (initial setup)
- A Tailscale account ([login.tailscale.com](https://login.tailscale.com))
- API keys for your LLM provider(s)

## Option A: Fully Automated (One Script)

### 1. Copy deploy repo to VPS

```bash
scp -r deploy/ root@<vps-ip>:/srv/nazar/deploy/
```

### 2. Run the master provisioning script

```bash
ssh root@<vps-ip>
bash /srv/nazar/deploy/../vault/99-system/openclaw/skills/vps-setup/scripts/provision-vps.sh \
  --deploy-repo /srv/nazar/deploy
```

This runs all phases:
- Creates `nazar` user with sudo + SSH keys
- Hardens SSH (key-only, no root)
- Configures firewall (UFW)
- Installs Fail2Ban + unattended upgrades
- Installs Tailscale (interactive auth step)
- Optionally locks SSH to Tailscale
- Installs Docker
- Creates vault group and Git repos
- Installs auto-commit cron
- Builds and starts the container
- Adds swap if low memory

### 3. Configure secrets

```bash
ssh nazar@<tailscale-ip>
nano /srv/nazar/.env
```

Fill in `ANTHROPIC_API_KEY`, `KIMI_API_KEY`, `WHATSAPP_NUMBER`.

### 4. Restart with secrets

```bash
cd /srv/nazar && docker compose restart
```

## Option B: Step by Step

### 1. Secure the VPS

```bash
ssh root@<vps-ip>
bash secure-vps.sh
```

### 2. Install Tailscale

```bash
bash install-tailscale.sh
# Open the auth URL in your browser
```

### 3. Lock SSH to Tailscale

```bash
# First verify: ssh nazar@<tailscale-ip>
bash lock-ssh-to-tailscale.sh
```

### 4. Install Docker

```bash
bash install-docker.sh
# Log out and back in for docker group
```

### 5. Deploy the stack

```bash
bash /srv/nazar/deploy/scripts/setup-vps.sh
```

### 6. Configure and start

```bash
nano /srv/nazar/.env
cd /srv/nazar && docker compose restart
```

## Option C: Claude Code Guided

SSH into the VPS, install Claude Code, then:

```
Read /srv/nazar/deploy/../vault/99-system/openclaw/skills/vps-setup/SKILL.md
and walk me through setting up this VPS
```

Claude Code will execute each phase interactively, pausing for confirmations.

## Directory Layout on VPS

```
/srv/nazar/                 <- Working directory
├── docker-compose.yml      <- Copied from deploy/
├── .env                    <- Secrets (auto-generated token + your API keys)
├── vault/                  <- Obsidian vault (git working copy)
│   ├── .git/               <- Git repo (origin = vault.git)
│   ├── .gitignore
│   ├── 00-inbox/
│   ├── 01-daily-journey/
│   ├── ...
│   └── 99-system/
├── vault.git/              <- Bare Git repo (push target for clients)
│   └── hooks/post-receive  <- Auto-deploys to vault/ on push
├── scripts/
│   └── vault-auto-commit.sh <- Cron: commits agent writes every 5 min
└── data/
    └── openclaw/           <- OpenClaw config + state
        └── openclaw.json

/opt/openclaw/              <- OpenClaw source (for Docker build)
├── Dockerfile.nazar        <- Custom Dockerfile (copied from deploy/)
└── ...                     <- Official OpenClaw source

/srv/nazar/deploy/          <- Deploy repo (reference copy)
```

## Docker Image Details

`Dockerfile.nazar` builds on `node:22-bookworm`:

- OpenClaw built from source (pnpm)
- Python 3 venv with: `faster-whisper`, `piper-tts`, `pydub`, `av`
- Pre-downloaded models: Whisper `small`, Piper `en_US-lessac-medium`
- System tools: `ffmpeg`, `ripgrep`, `jq`, `git`, `socat`

Build takes 10-15 minutes on a 2-core VPS. The image is ~3GB due to voice models.

## Ports

| Port | Service | Binding | Access |
|------|---------|---------|--------|
| 443 (HTTPS) | OpenClaw Gateway | loopback -> Tailscale Serve | `https://<tailscale-hostname>/` (automatic) |
| 22 (SSH) | Git vault sync | `tailscale0` only | `git clone nazar@<tailscale-ip>:/srv/nazar/vault.git` |

No public ports are needed. All access flows through Tailscale.

## Management Commands

```bash
cd /srv/nazar

# Status
docker compose ps

# Logs
docker compose logs -f nazar-gateway

# Restart
docker compose restart

# Rebuild (after updating Dockerfile)
docker compose build --no-cache nazar-gateway
docker compose up -d

# Stop
docker compose down

# Vault sync log
tail -f /srv/nazar/data/git-sync.log

# OpenClaw CLI (alias set up automatically during provisioning in ~/.bashrc)
# alias openclaw="sudo docker exec -it nazar-gateway node dist/index.js"
openclaw configure                    # Interactive setup wizard
openclaw doctor --fix                 # Health check + auto-fix
openclaw devices list                 # List paired devices
openclaw channels                     # Channel management

# Security audit
bash /srv/nazar/deploy/../vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

## Updating

### Update deploy repo

```bash
cd /srv/nazar/deploy && git pull
```

### Re-run setup (safe to re-run)

```bash
sudo bash scripts/setup-vps.sh
```

### Rebuild image (after Dockerfile changes)

```bash
cd /srv/nazar
docker compose build --no-cache nazar-gateway
docker compose up -d
```

## Verification Checklist

```bash
docker compose ps                                    # Gateway running
curl -sk https://vps-claw.tail697e8f.ts.net/         # Gateway responds via Tailscale Serve
docker compose exec nazar-gateway ls /vault/          # Vault folders visible
docker compose exec nazar-gateway node -e "console.log('ok')"  # Node works
git -C /srv/nazar/vault log --oneline -5             # Git history exists
ls /srv/nazar/vault.git/hooks/post-receive           # Hook installed
crontab -u nazar -l | grep vault-auto-commit         # Cron active
bash audit-vps.sh                                    # All checks pass
```

## First Browser Access

The first time you open the Control UI (`https://<tailscale-hostname>/`) in a browser, the gateway will require **device pairing**. This is expected -- new devices must be approved before they can interact with the gateway.

To approve the device, SSH into the VPS and run:

```bash
# List pending pairing requests
openclaw devices list

# Approve the pending request
openclaw devices approve <request-id>
```

After approval, refresh the browser and the UI will load normally. Subsequent visits from the same browser are remembered.

## Post-Deploy Setup

After verification, complete the initial configuration:

1. **Run onboarding:** `openclaw configure` -- interactive wizard to set up WhatsApp linking, model configuration, and other settings.
2. **Clone the vault** on your laptop/phone (see [Git Sync docs](git-sync.md)).
3. **Run a security audit:** `bash audit-vps.sh`
