# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Syncthing, and hosted on a hardened OVHcloud Debian 13 VPS.

**Architecture**: Docker containers with shared vault volume — simple, secure, reproducible.

**Setup**: Designed for AI agent assistance (Claude Code, Kimi Code).

---

## 🚀 Quick Start (AI Agent Recommended)

The easiest way to set up is using an AI agent (Claude Code or Kimi Code) on your VPS:

```bash
# On your fresh OVHcloud Debian 13 VPS (as root):
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/vault/99-system/openclaw/skills/vps-setup/scripts/nazar-ai-setup.sh \
    -o /usr/local/bin/nazar-ai-setup && chmod +x /usr/local/bin/nazar-ai-setup

# Then let your AI agent handle the rest:
nazar-ai-setup run
```

**Why AI agent setup?**
- ✅ Checkpoint/resume — safely handles interruptions
- ✅ Pre-flight validation — catches issues before they cause problems  
- ✅ Machine-readable state — AI can track and report progress
- ✅ Idempotent — safe to re-run if something fails

### Manual Setup (If You Prefer)

```bash
# On your fresh OVHcloud Debian 13 VPS (as debian user):
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

See [docker/VPS-GUIDE.md](docker/VPS-GUIDE.md) for detailed manual setup instructions.

---

## What Is This?

Three integrated layers working together:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method
2. **Intelligence Layer** (OpenClaw) — The Nazar AI agent that manages your daily journal and answers questions
3. **Infrastructure Layer** — Docker containers running OpenClaw + Syncthing

```
second-brain/
├── vault/                ← Obsidian vault (PARA structure + agent config)
│   ├── 00-inbox/         ← Quick capture
│   ├── 01-daily-journey/ ← Daily notes
│   ├── 02-projects/      ← Active projects
│   ├── 03-areas/         ← Life areas
│   ├── 04-resources/     ← Reference material
│   ├── 05-archive/       ← Completed items
│   └── 99-system/        ← Agent workspace, skills, templates
├── docker/               ← Docker deployment files
│   ├── docker-compose.yml
│   ├── Dockerfile.openclaw
│   ├── setup.sh
│   ├── setup-security.sh
│   ├── nazar-cli.sh
│   ├── VPS-GUIDE.md
│   ├── SECURITY.md
│   └── MIGRATION.md
└── docs/                 ← User documentation
```

---

## Architecture Overview

### User Model

| User | Purpose | Permissions |
|------|---------|-------------|
| `debian` | System administrator | SSH login, runs Docker containers |
| `1000:1000` | Container user | Inside Docker containers |

### Services

| Service | Container | Purpose |
|---------|-----------|---------|
| OpenClaw Gateway | `nazar-openclaw` | AI agent gateway (port 18789) |
| Syncthing | `nazar-syncthing` | Vault synchronization (port 8384) |

### Data Locations

| Path | Purpose |
|------|---------|
| `~/nazar/vault/` | Obsidian vault (synced) |
| `~/nazar/.openclaw/` | OpenClaw config + workspace |
| `~/nazar/syncthing/config/` | Syncthing database |

---

## Key Features

| Feature | Description |
|---------|-------------|
| **🔒 Secure by Default** | SSH tunnel access + optional Tailscale VPN |
| **📱 Multi-Device Sync** | Syncthing (real-time, conflict-resistant) |
| **🤖 AI Agent** | Nazar manages your daily journal |
| **📓 PARA Method** | Organized by Projects, Areas, Resources, Archive |
| **🐳 Docker** | Containerized, reproducible, easy updates |

---

## Setup Guide

### Recommended: AI Agent Setup

If you have Claude Code or Kimi Code installed on your VPS:

```bash
# Download the AI setup tool
sudo curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/vault/99-system/openclaw/skills/vps-setup/scripts/nazar-ai-setup.sh \
    -o /usr/local/bin/nazar-ai-setup && sudo chmod +x /usr/local/bin/nazar-ai-setup

# Check status
nazar-ai-setup status

# Run full setup
nazar-ai-setup run
```

The AI setup tool provides:
- **Validation** — Checks prerequisites before starting
- **Checkpoints** — Tracks progress, safe to resume if interrupted
- **JSON output** — Use `--json` for machine-readable status
- **Phase control** — Run `nazar-ai-setup run <phase>` to resume from a specific point

See the [VPS Setup Skill](vault/99-system/openclaw/skills/vps-setup/SKILL.md) for AI agent documentation.

### Manual Setup

If you prefer to set up manually:

```bash
# Create debian user first (as root)
adduser debian
usermod -aG sudo debian

# Copy SSH keys
mkdir -p /home/debian/.ssh
cp /root/.ssh/authorized_keys /home/debian/.ssh/
chown -R debian:debian /home/debian/.ssh

# Switch to debian and run setup
su - debian
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

This will:
- Install Docker
- Create `~/nazar/` directory structure
- Configure OpenClaw and Syncthing
- Optionally apply security hardening

### 2. Access Services

```bash
# On your laptop, open SSH tunnel
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@your-vps-ip

# Then open:
# - OpenClaw Gateway: http://localhost:18789
# - Syncthing GUI: http://localhost:8384
```

### 3. Configure Services

Once infrastructure is running, configure services through their own UIs:

1. **Syncthing** — Open the Syncthing GUI (`http://localhost:8384` via tunnel), add your devices, share the vault folder
2. **OpenClaw** — Run the onboarding wizard: `docker compose exec -it openclaw openclaw configure`

---

## Documentation

| Document | Description |
|----------|-------------|
| `vault/99-system/openclaw/skills/vps-setup/SKILL.md` | **AI Agent Setup Guide** — for Claude Code/Kimi Code |
| `docker/VPS-GUIDE.md` | OVHcloud Debian 13 VPS deployment guide (manual) |
| `docker/SECURITY.md` | Security hardening and best practices |
| `docker/MIGRATION.md` | Migration from old systemd setup |
| `docs/troubleshooting.md` | Common infrastructure issues and fixes |

---

## Security Model

Defense-in-depth with 4 layers:

1. **Network:** SSH tunnel (localhost only) or Tailscale VPN — zero public ports
2. **Authentication:** SSH keys only — no passwords, no root login
3. **Container Isolation:** Services run as non-root (UID 1000) inside containers
4. **Secrets:** API keys in `~/nazar/docker/.env`, never in vault

Run `nazar-cli security` to audit your setup.

---

## Why Docker?

| Aspect | Old (Systemd) | New (Docker) |
|--------|---------------|--------------|
| Complexity | Multiple users, systemd services | Single user, containers |
| Isolation | User-based (nazar user) | Container-based |
| Updates | Manual package updates | `docker compose pull` |
| Reproducibility | Environment-dependent | Consistent across hosts |
| Portability | Tied to specific setup | Runs anywhere with Docker |

---

## License

MIT License — feel free to use, modify, and share.

---

_Built with Obsidian, OpenClaw, Syncthing, and Docker._
