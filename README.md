# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Syncthing, and hosted on a hardened Debian VPS.

**Architecture**: Docker containers with shared vault volume — simple, secure, reproducible.

---

## 🚀 Quick Start

```bash
# On your fresh Debian/Ubuntu VPS (as debian user):
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash

# Follow the on-screen instructions
```

See [docker/VPS-GUIDE.md](docker/VPS-GUIDE.md) for detailed setup instructions.

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

### 1. Deploy on VPS

Run the setup script on a fresh Debian 13 or Ubuntu 22.04+ VPS:

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

### 3. Configure Syncthing

1. Get VPS Device ID from Syncthing GUI
2. Add it to your laptop/phone Syncthing
3. Share your vault folder

### 4. Configure OpenClaw

```bash
# On VPS
docker compose exec -it openclaw openclaw configure
```

---

## Daily Usage

### Management Commands

```bash
# View status
nazar-cli status

# View logs
nazar-cli logs

# Restart services
nazar-cli restart

# Create backup
nazar-cli backup

# Show SSH tunnel command
nazar-cli tunnel

# Run security audit
nazar-cli security
```

### Voice Notes

Send a voice message to your agent via WhatsApp/Telegram → Nazar transcribes it → Saved to today's daily note with timestamp.

---

## Documentation

| Document | Description |
|----------|-------------|
| `docker/VPS-GUIDE.md` | VPS deployment guide (OVHcloud, Hetzner, etc.) |
| `docker/SECURITY.md` | Security hardening and best practices |
| `docker/MIGRATION.md` | Migration from old systemd setup |
| `docs/vault-structure.md` | PARA vault layout and conventions |
| `docs/agent.md` | Nazar agent — workspace, personality, memory |
| `docs/syncthing-setup.md` | Detailed Syncthing configuration |
| `docs/openclaw-config.md` | OpenClaw configuration reference |
| `docs/troubleshooting.md` | Common issues and fixes |

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
