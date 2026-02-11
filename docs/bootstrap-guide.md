# AI-Assisted VPS Bootstrap Guide

Complete walkthrough for setting up Nazar using Claude Code or Kimi Code directly on the VPS.

---

## Overview

This guide is for the **AI-assisted setup flow** where Claude Code or Kimi Code runs directly on the VPS and guides you through configuration interactively.

**New Architecture:**
- **No Docker** — Services run directly under systemd
- **Two users** — `debian` (admin) and `nazar` (service)
- **Syncthing** — Real-time vault sync (not Git)
- **Simpler** — Direct execution, easier debugging

---

## The Flow

```
┌─────────────────┐
│  Buy VPS        │
│  (Hetzner, OVH) │
└────────┬────────┘
         ▼
┌─────────────────┐
│  SSH as root    │
└────────┬────────┘
         ▼
┌─────────────────┐
│  Run Bootstrap  │
│  Script         │
└────────┬────────┘
         ▼
┌─────────────────┐
│  Launch AI      │
│  Assistant      │
└────────┬────────┘
         ▼
┌─────────────────┐
│  AI guides you  │
│  through setup  │
└─────────────────┘
```

---

## Detailed Steps

### 1. Provision a VPS

Choose any provider:
- **Hetzner** (CX21: 2 vCPU, 4GB RAM, ~€6/month)
- **OVH** (Starter: 1 vCPU, 2GB RAM, ~€4/month)
- **DigitalOcean** (Basic: 1 vCPU, 2GB RAM, ~$6/month)

**Requirements:**
- Debian 13 (or Ubuntu 22.04/24.04)
- 2GB RAM minimum (4GB recommended)
- 20GB disk minimum (40GB recommended)
- SSH key access

### 2. Connect via SSH

```bash
ssh root@<vps-ip-address>
```

### 3. Run Bootstrap Script

The bootstrap script installs everything automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/second-brain/main/bootstrap/bootstrap.sh | bash
```

This will:
- Create `debian` (admin) and `nazar` (service) users
- Install Node.js 22, OpenClaw, Syncthing, Tailscale
- Harden SSH and configure firewall
- Set up systemd user services

### 4. Start Tailscale

```bash
sudo tailscale up
# Authenticate in browser when prompted
```

### 5. Clone Repository

As the debian user:

```bash
su - debian
mkdir -p ~/nazar
cd ~/nazar
git clone https://github.com/<your-username>/second-brain-stack.git .
```

Or if you have a private fork:
```bash
cd ~/nazar
git clone git@github.com:<your-username>/second-brain-stack.git .
```

### 6. Install AI Assistant (Optional)

If not already installed by bootstrap:

**Claude Code:**
```bash
npm install -g @anthropic-ai/claude-code
```

**Kimi Code:**
```bash
npm install -g @moonshot-ai/kimi-code
```

### 7. Launch the AI Assistant

**Claude Code:**
```bash
cd ~/nazar
claude
```

**Kimi Code:**
```bash
cd ~/nazar
kimi
```

### 8. Start the Guided Setup

Once the AI assistant is running, paste this prompt:

```
I'm a new user setting up the Nazar Second Brain on this VPS. 
Please:
1. Read the AGENTS.md file to understand this project
2. Read the bootstrap/AI_BOOTSTRAP.md file for setup instructions
3. Guide me step-by-step through the complete VPS setup

I want to use this VPS as my personal Second Brain server with:
- Tailscale for secure access
- Syncthing for vault synchronization
- OpenClaw/Nazar AI agent

Please explain each step before executing it.
```

The AI will then:
1. **Analyze** the project structure
2. **Check** current system state
3. **Guide** you through each phase:
   - Copy vault to service user
   - Start Syncthing
   - Start OpenClaw
   - Configure services
   - Optional security hardening

---

## What Gets Installed

The bootstrap sets up the following on your VPS:

### Security Layer
| Component | Purpose |
|-----------|---------|
| UFW Firewall | Block all incoming except SSH |
| Fail2Ban | Ban IPs with failed login attempts |
| SSH Hardening | Key-only, no root, port 22 |
| User Isolation | `debian` (sudo) + `nazar` (no sudo) |
| Tailscale ACL | Lock SSH to Tailscale network only |
| Unattended Upgrades | Auto-install security patches |

### Application Layer
| Component | Purpose |
|-----------|---------|
| Node.js 22 | JavaScript runtime for OpenClaw |
| OpenClaw | AI agent gateway (npm global) |
| Syncthing | Real-time vault synchronization |
| Whisper STT | Speech-to-text |
| Piper TTS | Text-to-speech |

### Data Layer
| Path | Purpose |
|------|---------|
| `/home/nazar/vault/` | Obsidian vault (mode 700) |
| `/home/nazar/.openclaw/` | OpenClaw configuration |
| `/home/nazar/.local/state/syncthing/` | Syncthing data |

---

## Configuration Decisions

The AI will help you with:

### 1. Tailscale Setup
- Authenticate with your Tailscale account
- Choose your tailnet name
- The VPS will be accessible via `https://<hostname>.<tailnet>.ts.net`

### 2. Syncthing Device Pairing
- Exchange device IDs with your laptop/phone
- Share the vault folder
- Configure versioning if desired

### 3. OpenClaw Configuration
- Run `sudo -u nazar openclaw configure`
- Set up LLM providers and API keys
- Configure channels (WhatsApp, Telegram, etc.)

---

## Post-Setup

After the AI completes the setup:

### 1. Verify Installation
```bash
# Check services
ssh debian@<tailscale-ip>
nazar-status

# Check Tailscale
tailscale status

# Check firewall
sudo ufw status
```

### 2. Configure OpenClaw
```bash
sudo -u nazar openclaw configure
```

This interactive wizard sets up:
- LLM providers (OpenAI, Anthropic, local models)
- API keys
- Channels (WhatsApp, Telegram, etc.)
- Agent personality settings

### 3. Access Control UI
Open in your browser:
```
https://<vps-hostname>.<tailnet>.ts.net/
```

First access requires device approval:
```bash
sudo -u nazar openclaw devices list
sudo -u nazar openclaw devices approve <request-id>
sudo -u nazar systemctl --user restart openclaw
```

### 4. Set Up Syncthing on Your Devices

**On VPS** (get device ID):
```bash
sudo -u nazar syncthing cli show system | grep myID
```

**On Laptop:**
1. Install Syncthing
2. Add VPS device ID
3. Share vault folder

**On Phone:**
1. Install Syncthing app
2. Add VPS device ID
3. Share vault folder

### 5. Set Up Obsidian

1. Open Obsidian
2. "Open folder as vault" → select your Syncthing-synced vault folder
3. Start writing — changes sync automatically

---

## Troubleshooting

### Service Won't Start

**Check logs:**
```bash
# OpenClaw logs
sudo -u nazar journalctl --user -u openclaw -n 50

# Syncthing logs
sudo -u nazar journalctl --user -u syncthing -n 50

# Check config validity
sudo -u nazar jq . /home/nazar/.openclaw/openclaw.json
```

### Syncthing Not Syncing

**Check connectivity:**
```bash
# Tailscale status
tailscale status

# Syncthing connections
sudo -u nazar syncthing cli show connections

# Restart Syncthing
sudo -u nazar systemctl --user restart syncthing
```

### Permission Issues

```bash
# Fix vault permissions
sudo chown -R nazar:nazar /home/nazar/vault
```

### AI Assistant Issues

**"command not found" after install:**
```bash
export PATH="$PATH:/usr/local/bin"
# Or restart your shell
exec bash
```

**Out of memory:**
```bash
# Add swap
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

---

## Comparison: Old vs New Architecture

| Aspect | Old (Docker + Git) | New (Direct + Syncthing) |
|--------|-------------------|-------------------------|
| **Setup Time** | ~30 min | ~5 min |
| **Sync** | Git cron (5 min delay) | Real-time |
| **Conflicts** | Git merge issues | Conflict files |
| **Resource Usage** | Higher (containers) | Lower (native) |
| **Debugging** | Complex (layers) | Simple (direct) |
| **Maintenance** | Docker updates | System packages only |

---

## Next Steps

- Read [architecture.md](architecture.md) for system details
- Read [syncthing-setup.md](syncthing-setup.md) for sync configuration
- Read [security.md](security.md) for optional hardening
- Read [troubleshooting.md](troubleshooting.md) for common issues

---

*Last updated: 2026-02-11*
