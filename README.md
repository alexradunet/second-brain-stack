# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Syncthing, and hosted on a hardened Debian VPS behind Tailscale.

---

## 🚀 Quick Start

```bash
# On your fresh Debian/Ubuntu VPS (as root):
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash

# Then follow the on-screen instructions
```

---

## What Is This?

Three integrated layers working together:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method
2. **Intelligence Layer** (OpenClaw) — The Nazar AI agent that manages your daily journal and answers questions
3. **Infrastructure Layer** — Simple, secure services running directly on the VPS (no Docker)

```
second-brain/
├── vault/                ← Obsidian vault (PARA structure + agent config)
│   ├── 00-inbox/         ← Quick capture
│   ├── 01-daily-journey/ ← Daily notes (YYYY/MM-MMMM/YYYY-MM-DD.md)
│   ├── 02-projects/      ← Active projects
│   ├── 03-areas/         ← Life areas
│   ├── 04-resources/     ← Reference material
│   ├── 05-archive/       ← Completed items
│   └── 99-system/        ← Agent workspace, skills, templates
├── nazar/                ← Service user configuration
│   ├── config/           ← OpenClaw configuration templates
│   └── scripts/          ← Setup helpers
├── system/               ← System administration scripts
│   ├── scripts/          ← Admin helper scripts
│   └── docs/             ← Admin documentation
├── bootstrap/            ← Bootstrap files for initial setup
└── docs/                 ← User documentation
```

---

## Architecture Overview

### User Model

| User | Purpose | Permissions |
|------|---------|-------------|
| `debian` | System administrator | sudo access, SSH login |
| `nazar` | Service user | No sudo, runs OpenClaw + Syncthing |

### Services

| Service | Runs As | Purpose |
|---------|---------|---------|
| OpenClaw Gateway | `nazar` | AI agent gateway (port 18789, Tailscale serve) |
| Syncthing | `nazar` | Vault synchronization (port 8384) |

### Data Locations

| Path | Purpose | Owner |
|------|---------|-------|
| `/home/nazar/vault/` | Obsidian vault | `nazar:nazar` |
| `/home/nazar/.openclaw/` | OpenClaw config + state | `nazar:nazar` |
| `/home/nazar/.local/state/syncthing/` | Syncthing data | `nazar:nazar` |

---

## Key Features

| Feature | Description |
|---------|-------------|
| **🔒 Secure by Default** | Tailscale VPN + hardened SSH + no public ports |
| **🎙️ Voice Processing** | Whisper STT + Piper TTS for voice notes |
| **📱 Multi-Device Sync** | Syncthing (real-time, conflict-resistant) |
| **🤖 AI Agent** | Nazar manages your daily journal and answers questions |
| **📓 PARA Method** | Organized by Projects, Areas, Resources, Archive |
| **🚀 Simple** | No Docker, direct Node.js/Python execution |

---

## Setup Guide

### 1. Bootstrap the VPS

Run the bootstrap script on a fresh Debian 13 or Ubuntu 22.04+ VPS:

```bash
# As root
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash
```

This will:
- Create `debian` (admin) and `nazar` (service) users
- Install Node.js 22, OpenClaw, Syncthing, Tailscale
- Harden SSH and configure firewall
- Set up systemd user services

### 2. Configure Tailscale

```bash
sudo tailscale up
# Authenticate in your browser when prompted
```

### 3. Deploy the Vault

Clone this repository and copy the vault:

```bash
# As debian user
su - debian
git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar-deploy
cd ~/nazar-deploy

# Copy vault to nazar user
sudo cp -r vault/* /home/nazar/vault/
sudo chown -R nazar:nazar /home/nazar/vault
```

### 4. Start Syncthing

```bash
sudo bash nazar/scripts/setup-syncthing.sh
```

Then access the Syncthing GUI at `http://<tailscale-ip>:8384` to:
1. Set admin username/password
2. Add your devices (laptop, phone)
3. Share the vault folder

### 5. Start OpenClaw

```bash
sudo bash nazar/scripts/setup-openclaw.sh

# Configure models and channels
sudo -u nazar openclaw configure
```

Access the gateway at `https://<tailscale-hostname>/`

---

## Daily Usage

### From Your Devices

1. **Install Syncthing** on laptop and phone
2. **Add the VPS device** (get ID from VPS: `sudo -u nazar syncthing cli show system`)
3. **Share your vault folder** with the VPS
4. **Open in Obsidian** — changes sync instantly

### Voice Notes

Send a voice message to your agent via WhatsApp/Telegram → Nazar transcribes it → Saved to today's daily note with timestamp.

### Admin Commands (as debian user)

```bash
# View logs
nazar-logs          # OpenClaw logs
journalctl --user -u syncthing -f  # Syncthing logs (as nazar)

# Restart services
nazar-restart       # Restart OpenClaw
sudo -u nazar systemctl --user restart syncthing

# Check status
nazar-status        # Service status
```

---

## Documentation

| Document | Description |
|----------|-------------|
| `docs/vault-structure.md` | PARA vault layout and conventions |
| `docs/agent.md` | Nazar agent — workspace, personality, memory |
| `docs/syncthing-setup.md` | Detailed Syncthing configuration |
| `docs/openclaw-config.md` | OpenClaw configuration reference |
| `docs/troubleshooting.md` | Common issues and fixes |
| `system/docs/admin-guide.md` | System administration guide |

---

## Security Model

Defense-in-depth with 5 layers:

1. **Network:** Tailscale VPN + UFW firewall — zero public ports
2. **Authentication:** SSH keys only — no passwords, no root login
3. **User Isolation:** `nazar` user runs services with no sudo access
4. **Secrets:** API keys in `~/.openclaw/`, never in vault
5. **Auto-Patching:** Unattended security upgrades daily

---

## Why This Architecture?

### Compared to Docker Version

| Aspect | Old (Docker + Git) | New (Direct + Syncthing) |
|--------|-------------------|-------------------------|
| Complexity | High (containers, compose, git hooks) | Low (direct execution) |
| Sync | Git (cron-based, conflicts) | Syncthing (real-time, auto-resolve) |
| Resource Usage | Higher (container overhead) | Lower (native processes) |
| Maintenance | Docker updates, image rebuilds | Just system packages |
| Reliability | Git merge conflicts | Syncthing conflict files |

### Why Syncthing Over Git?

- **Real-time sync**: Changes propagate instantly
- **Conflict handling**: Creates `.sync-conflict-*` files instead of breaking
- **No cron jobs**: No 5-minute delays or push/pull errors
- **Mobile-friendly**: Native apps, no Git plugins needed
- **Resilient**: Works offline, syncs when connected

---

## License

MIT License — feel free to use, modify, and share.

---

_Built with Obsidian, OpenClaw, Syncthing, and a lot of voice notes._
