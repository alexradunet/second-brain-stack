# AI-Assisted VPS Bootstrap Guide

Complete walkthrough for setting up Nazar using Claude Code or Kimi Code directly on the VPS.

---

## Overview

This guide is for the **AI-assisted setup flow** where Claude Code or Kimi Code runs directly on the VPS and guides you through configuration interactively.

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
│  Install        │
│  Claude/Kimi    │
│  Code           │
└────────┬────────┘
         ▼
┌─────────────────┐
│  Clone repo to  │
│  ~/nazar_deploy │
└────────┬────────┘
         ▼
┌─────────────────┐
│  Launch AI      │
│  assistant      │
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
- API keys for LLM providers (Anthropic, OpenAI, etc.) - for `openclaw configure` step

### 2. Connect via SSH

```bash
ssh root@<vps-ip-address>
```

### 3. Install Node.js

Claude Code and Kimi Code require Node.js 18+:

```bash
# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Verify
node --version  # Should show v20.x.x
```

### 4. Install Claude Code or Kimi Code

**Claude Code:**
```bash
npm install -g @anthropic-ai/claude-code
# or use the install script:
curl -fsSL https://claude.ai/install.sh | sh
```

**Kimi Code:**
```bash
# Install Kimi Code CLI
npm install -g @moonshot-ai/kimi-code
```

### 5. Clone the Repository

```bash
cd ~
mkdir -p nazar_deploy
cd nazar_deploy
git clone https://github.com/<your-username>/nazar-second-brain.git .
```

Or if you have a private fork:
```bash
cd ~
mkdir -p nazar_deploy
cd nazar_deploy
git clone git@github.com:<your-username>/nazar-second-brain.git .
```

### 6. Launch the AI Assistant

**Claude Code:**
```bash
cd ~/nazar_deploy
claude
```

**Kimi Code:**
```bash
cd ~/nazar_deploy
kimi
```

### 7. Start the Guided Setup

Once the AI assistant is running, paste this prompt:

```
I'm a new user setting up the Nazar Second Brain on this VPS. 
Please:
1. Read the AGENTS.md file to understand this project
2. Read the deploy configuration files
3. Guide me step-by-step through the complete VPS setup

I want to use this VPS as my personal Second Brain server with:
- Tailscale for secure access
- Git-based vault synchronization
- The full OpenClaw/Nazar stack

Please explain each step before executing it.
```

The AI will then:
1. **Analyze** the project structure
2. **Check** current system state
3. **Guide** you through each phase:
   - Security hardening
   - Tailscale installation
   - Docker setup
   - Vault repository setup
   - Container deployment
   - Configuration

---

## What Gets Installed

The AI will set up the following on your VPS:

### Security Layer
| Component | Purpose |
|-----------|---------|
| UFW Firewall | Block all incoming except SSH |
| Fail2Ban | Ban IPs with failed login attempts |
| SSH Hardening | Key-only, no root, port 22 |
| Tailscale ACL | Lock SSH to Tailscale network only |
| Unattended Upgrades | Auto-install security patches |

### Application Layer
| Component | Purpose |
|-----------|---------|
| Docker CE | Container runtime |
| Docker Compose | Multi-container orchestration |
| OpenClaw Gateway | AI agent server |
| Whisper STT | Speech-to-text |
| Piper TTS | Text-to-speech |
| Git Repos | Vault sync infrastructure |

### Data Layer
| Path | Purpose |
|------|---------|
| `/srv/nazar/vault/` | Obsidian vault (working copy) |
| `/srv/nazar/vault.git/` | Bare repo for client sync |
| `/srv/nazar/data/` | Application state |
| `/srv/nazar/scripts/` | Automation scripts |

---

## Configuration Decisions

The AI will ask you to make these choices during setup:

### 1. Deploy User
- **Default:** `debian` (or `ubuntu` on Ubuntu)
- **Alternative:** Create a custom user
- **Note:** This user owns all files and runs cron jobs

### 2. Vault Git Remote
- **Option A:** Local bare repo (default)
  - Clients clone from VPS directly
  - Simple, no external dependencies
- **Option B:** External remote (GitHub/GitLab)
  - Use if you already have a vault on GitHub
  - VPS mirrors the external repo

### 3. Tailscale
- The AI will help you authenticate
- Choose your tailnet name
- The VPS will be accessible via `https://<hostname>.<tailnet>.ts.net`

---

## Post-Setup

After the AI completes the setup:

### 1. Verify Installation
```bash
# Check containers
ssh debian@<tailscale-ip>
cd /srv/nazar
docker compose ps

# Check Tailscale
tailscale status

# Check firewall
sudo ufw status
```

### 2. Configure OpenClaw
```bash
openclaw configure
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
openclaw devices list
openclaw devices approve <request-id>
```

### 4. Sync Your Vault

**If you have an existing vault:**
```bash
cd ~/your-existing-vault
git remote add origin debian@<tailscale-ip>:/srv/nazar/vault.git
git push -u origin main
```

**If starting fresh:**
```bash
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/nazar-vault
```

### 5. Set Up Obsidian

1. Open Obsidian
2. "Open folder as vault" → select `~/nazar-vault`
3. Install "Obsidian Git" plugin
4. Configure auto-sync (commit every 5 min, push on commit)

---

## Troubleshooting

### Claude/Kimi Code Issues

**"command not found" after install:**
```bash
export PATH="$PATH:/usr/local/bin"
# Or restart your shell
exec bash
```

**Out of memory during AI assistant startup:**
```bash
# Add swap
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

### Setup Issues

**Docker fails to start:**
```bash
# Check logs
journalctl -u docker.service

# Reinstall if needed
apt-get remove docker docker-engine docker.io
apt-get install docker-ce docker-ce-cli containerd.io
```

**Tailscale auth fails:**
```bash
# Re-run auth
tailscale up
```

**Vault permissions issues:**
```bash
sudo chown -R debian:vault /srv/nazar/vault
sudo find /srv/nazar/vault -type d -exec chmod 2775 {} +
```

---

## Alternative: Non-Interactive Setup

If you prefer traditional scripted setup instead of AI-guided:

```bash
# Copy deploy files to VPS
scp -r deploy/ root@<vps-ip>:/tmp/deploy/

# SSH and run
ssh root@<vps-ip>
bash /tmp/deploy/scripts/setup-vps.sh
```

See [deployment.md](deployment.md) for full details.

---

## Security Checklist

After setup is complete, verify:

```bash
# Run the security audit
bash /srv/nazar/vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

Expected output:
- ✅ SSH root login disabled
- ✅ SSH password auth disabled
- ✅ UFW active, only SSH allowed
- ✅ Fail2Ban running
- ✅ Unattended upgrades enabled
- ✅ Tailscale connected
- ✅ No secrets in vault

---

## Support

- **Issues with the AI assistant:** Check [Claude Code docs](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) or [Kimi Code docs](https://github.com/moonshot-ai/kimi-code-cli)
- **Issues with setup:** Check [troubleshooting.md](troubleshooting.md)
- **General questions:** Review [README.md](../README.md)
