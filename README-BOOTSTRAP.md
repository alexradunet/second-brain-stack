# Nazar VPS Bootstrap Guide (AI-Assisted)

This is the **AI-assisted setup flow** for the Nazar Second Brain system. Instead of manually running scripts, you'll use Claude Code or Kimi Code directly on the VPS to guide you through the entire setup interactively.

---

## Prerequisites

1. **A VPS** — Any Debian 13-based VPS (Hetzner, OVH, DigitalOcean, etc.)
   - Recommended: 2 vCPU, 4GB RAM, 40GB SSD
   - Minimum: 1 vCPU, 2GB RAM, 20GB SSD (with swap)
2. **SSH access** — Root or sudo user access with SSH key
3. **Tailscale account** — [login.tailscale.com](https://login.tailscale.com) (free)
4. **API Keys** — For LLM providers (Anthropic, OpenAI, etc.) - needed during `openclaw configure`
5. **GitHub account** (optional) — Only if you want to use GitHub as your vault remote

---

## The Bootstrap Flow

### Step 1: SSH into your fresh VPS

```bash
ssh root@<your-vps-ip>
```

### Step 2: Install Claude Code or Kimi Code

**For Claude Code:**
```bash
curl -fsSL https://claude.ai/install.sh | sh
```

**For Kimi Code:**
```bash
npm install -g @moonshot-ai/kimi-code
```

### Step 3: Create the deploy directory and clone this repo

```bash
cd ~
mkdir -p nazar_deploy
cd nazar_deploy
git clone <this-repository-url> .
```

### Step 4: Launch the AI assistant

```bash
# For Claude Code
claude

# For Kimi Code
kimi
```

### Step 5: Let the AI guide you

Once the AI assistant is running inside the repository, simply ask:

> **"I'm a new user. Please read the project context and guide me through setting up this VPS for the Nazar Second Brain system."**

The AI will:
1. Read `AGENTS.md` to understand the project structure
2. Read `deploy/` configuration files
3. Guide you step-by-step through:
   - VPS hardening (SSH, firewall, fail2ban)
   - Tailscale installation
   - Docker setup
   - Repository and vault configuration
   - Container deployment
   - Initial configuration

---

## What the AI Will Set Up

The AI assistant will configure your VPS with:

| Component | Purpose |
|-----------|---------|
| **Hardened SSH** | Key-only auth, no root login, locked to Tailscale |
| **UFW Firewall** | Deny all incoming, allow SSH only via Tailscale |
| **Fail2Ban** | Brute-force protection |
| **Tailscale** | Zero-config VPN for secure access |
| **Docker + Compose** | Container runtime for the gateway |
| **Vault Git Repo** | Bare repo at `/srv/nazar/vault.git` |
| **nazar-gateway** | OpenClaw AI agent with voice processing |
| **Auto-sync** | Git sync every 5 minutes |

---

## Directory Structure After Setup

```
/srv/nazar/                    # Main installation directory
├── docker-compose.yml         # Container orchestration
├── .env                       # Secrets and configuration
├── vault/                     # Your Obsidian vault (working copy)
│   ├── 00-inbox/
│   ├── 01-daily-journey/
│   ├── 02-projects/
│   ├── 03-areas/
│   ├── 04-resources/
│   ├── 05-arhive/
│   └── 99-system/            # Agent workspace
├── vault.git/                 # Bare repo for git sync
├── scripts/                   # Automation scripts
└── data/openclaw/            # Agent configuration

~/nazar_deploy/               # This repository (reference)
```

---

## Post-Setup Access

After the AI-guided setup is complete:

### Access the Control UI
```
https://<your-vps-tailscale-hostname>/
```

### Clone your vault locally
```bash
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/nazar-vault
```

### Open in Obsidian
Point Obsidian to `~/nazar-vault` and install the Git plugin.

---

## Why This Approach?

**Traditional approach:** Copy scripts, read docs, run commands manually, hope nothing breaks.

**AI-assisted approach:** 
- ✅ Interactive guidance — the AI explains what each step does
- ✅ Error handling — the AI helps troubleshoot issues in real-time
- ✅ Customization — adapt the setup to your specific VPS provider
- ✅ Education — understand your system as it's being built
- ✅ Safety — the AI confirms destructive actions before executing

---

## Troubleshooting

**Claude/Kimi Code won't install?**
- Ensure Node.js 18+ is installed: `apt update && apt install -y nodejs npm`

**Permission denied during setup?**
- Make sure you're running as root or with sudo

**Want to start over?**
```bash
# Stop containers
sudo docker compose -f /srv/nazar/docker-compose.yml down 2>/dev/null || true
# Remove data (WARNING: this deletes your vault on the VPS!)
# Make sure you have a backup or it's synced elsewhere first!
sudo rm -rf /srv/nazar
```
Then re-run the AI assistant.

---

## Next Steps

1. Complete this bootstrap flow
2. Configure `openclaw` (the AI assistant will guide you)
3. Set up your devices (phone, laptop) to sync with the vault
4. Start capturing notes!

---

*Ready? SSH into your VPS and start at Step 1 above.*
