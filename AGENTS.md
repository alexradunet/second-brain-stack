# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Git, and hosted on a hardened Debian VPS behind Tailscale.

---

## Project Overview

This project consists of three integrated layers:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method (Projects, Areas, Resources, Archive)
2. **Intelligence Layer** (OpenClaw Gateway) — The Nazar AI agent that processes voice messages, manages daily journals, and answers questions about your notes
3. **Infrastructure Layer** (`deploy/`) — Docker containers running on a hardened VPS with Git-based vault synchronization

```
second-brain/
├── vault/                ← Obsidian vault (PARA structure + agent config)
│   ├── 00-inbox/         ← Quick capture
│   ├── 01-daily-journey/ ← Daily notes (YYYY/MM-MMMM/YYYY-MM-DD.md)
│   ├── 02-projects/      ← Active projects with goals/deadlines
│   ├── 03-areas/         ← Life areas requiring ongoing attention
│   ├── 04-resources/     ← Reference material
│   ├── 05-arhive/        ← Completed/inactive items
│   └── 99-system/        ← Agent workspace, skills, templates
├── deploy/               ← Docker stack for VPS deployment
│   ├── docker-compose.yml
│   ├── Dockerfile.nazar
│   ├── openclaw.json     ← Agent configuration
│   └── scripts/          ← VPS setup scripts
└── docs/                 ← Project documentation
```

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| **Gateway** | Node.js 22 (OpenClaw framework) |
| **Voice Processing** | Python 3 + Whisper (STT) + Piper (TTS) |
| **Containerization** | Docker + Docker Compose |
| **Sync** | Git over SSH |
| **Networking** | Tailscale (WireGuard VPN) |
| **OS** | Debian 13 |
| **PKM App** | Obsidian |

---

## Vault Structure (PARA Method)

The vault uses the PARA organizational method with numbered kebab-case folders:

| Folder | Purpose |
|--------|---------|
| `00-inbox/` | Quick capture — new notes land here by default |
| `01-daily-journey/` | Daily journal notes (`YYYY/MM-MMMM/YYYY-MM-DD.md`) |
| `02-projects/` | Active projects with clear goals and deadlines |
| `03-areas/` | Life areas requiring ongoing attention |
| `04-resources/` | Reference material and knowledge base |
| `05-arhive/` | Completed or inactive items |
| `99-system/` | System configuration (agent workspace, templates) |

### Daily Note Format

Daily notes follow the structure: `01-daily-journey/2026/02-February/2026-02-11.md`

Voice notes are appended with timestamps:
```markdown
---

**[14:32]**

Transcribed voice note content...
```

---

## Agent Workspace

The agent's "brain" lives at `vault/99-system/openclaw/workspace/`:

| File | Purpose |
|------|---------|
| `SOUL.md` | Agent personality and values |
| `AGENTS.md` | Behavior rules and operational guidelines |
| `USER.md` | User profile and preferences |
| `IDENTITY.md` | Agent self-concept (name, creature type, vibe) |
| `MEMORY.md` | Long-term curated memory (main sessions only) |
| `TOOLS.md` | Environment notes (camera names, SSH hosts, etc.) |
| `HEARTBEAT.md` | Periodic task checklist |
| `memory/` | Daily log files (`YYYY-MM-DD.md`) |

### Session Startup Protocol

Before each session, the agent reads:
1. `SOUL.md` — who it is
2. `USER.md` — who it's helping
3. `memory/YYYY-MM-DD.md` (today + yesterday) — recent context
4. `MEMORY.md` — if in a main (direct) session only

---

## Skills

Skills are self-contained modules in `vault/99-system/openclaw/skills/`:

### obsidian/
Vault operations: read/write notes, manage daily journal, work with templates.

**Key functions:**
- `get_daily_note_path()` — Path for today's note
- `create_daily_note(content)` — Create daily note
- `append_to_daily_note(content)` — Append with timestamp
- `create_note(title, content, folder)` — Create note in any folder
- `read_note(path)` — Read a note

### voice/
Local speech-to-text (Whisper) and text-to-speech (Piper) with Obsidian integration.

**Key functions:**
- `transcribe_audio(audio_path)` — Audio → text
- `transcribe_and_save(audio_path)` — Full pipeline: transcribe → daily note
- `generate_speech(text)` — Text → WAV
- `convert_to_opus(wav_path)` — WAV → OGG/Opus (WhatsApp)

### vps-setup/
VPS provisioning and security hardening scripts:
- `provision-vps.sh` — Master provisioning script
- `secure-vps.sh` — SSH hardening, firewall, fail2ban
- `install-tailscale.sh` — Install Tailscale
- `install-docker.sh` — Install Docker
- `audit-vps.sh` — Security audit

---

## Build and Deployment

### Local Development

```bash
# Clone the repo
git clone <repo-url>
cd second-brain

# Open vault in Obsidian
# (Point Obsidian to the vault/ folder)
```

### VPS Deployment (AI-Assisted Bootstrap)

**Recommended:** Use Claude Code or Kimi Code directly on the VPS for an interactive, guided setup experience.

**Prerequisites:**
- Debian 13 VPS (or Ubuntu 22.04+)
- Root SSH access
- Tailscale account

**Quick Start — AI-Assisted:**
```bash
# 1. SSH into your fresh VPS
ssh root@<vps-ip>

# 2. Run the bootstrap preparation script
curl -fsSL https://raw.githubusercontent.com/<user>/nazar-second-brain/main/bootstrap/bootstrap.sh | bash

# 3. Or manually: Install Node.js + AI assistant
apt update && apt install -y nodejs npm
npm install -g @anthropic-ai/claude-code  # or @moonshot-ai/kimi-code

# 4. Clone this repository
cd ~ && mkdir -p nazar_deploy && cd nazar_deploy
git clone <this-repo-url> .

# 5. Launch the AI assistant
claude  # or: kimi

# 6. Ask the AI to guide you:
# "I'm a new user. Please read the project context and guide me 
#  through setting up this VPS for the Nazar Second Brain system."
```

The AI assistant will guide you through:
- VPS security hardening (SSH, firewall, fail2ban)
- Tailscale VPN setup
- Docker installation
- Repository and vault configuration
- Container deployment
- Initial configuration

**Alternative — Scripted Deploy:**
```bash
# Copy deploy repo to VPS
scp -r deploy/ root@<vps-ip>:/srv/nazar/

# SSH and run provisioning
ssh root@<vps-ip>
sudo bash /srv/nazar/deploy/scripts/setup-vps.sh

# Configure models and channels
openclaw configure
```

**Alternative — Manual Step-by-Step:**
```bash
# On VPS as root
bash vault/99-system/openclaw/skills/vps-setup/scripts/secure-vps.sh
bash vault/99-system/openclaw/skills/vps-setup/scripts/install-tailscale.sh
bash vault/99-system/openclaw/skills/vps-setup/scripts/lock-ssh-to-tailscale.sh
bash vault/99-system/openclaw/skills/vps-setup/scripts/install-docker.sh
bash /srv/nazar/deploy/scripts/setup-vps.sh
```

See [README-BOOTSTRAP.md](README-BOOTSTRAP.md) and [docs/bootstrap-guide.md](docs/bootstrap-guide.md) for detailed AI-assisted setup instructions.

### Docker Management

```bash
cd /srv/nazar

# Status
docker compose ps

# Logs
docker compose logs -f nazar-gateway

# Restart
docker compose restart

# Rebuild
docker compose build --no-cache nazar-gateway
docker compose up -d

# Stop
docker compose down
```

### OpenClaw CLI

```bash
# Configure models, API keys, channels
openclaw configure

# Health check and auto-fix
openclaw doctor --fix

# List/approve devices
openclaw devices list
openclaw devices approve <request-id>

# Channel management
openclaw channels
```

---

## Vault Synchronization

The vault syncs across devices using Git over SSH through Tailscale:

### Client Setup

```bash
# Clone vault (from laptop/phone)
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/vault

# Or if using external remote
git clone git@github.com:you/vault.git ~/vault
```

### With Obsidian Git Plugin

1. Install Obsidian Git plugin
2. Configure auto-pull: 5 minutes
3. Configure auto-push: after commit
4. Configure auto-commit: 5 minutes

### Sync Flow

```
Laptop/Phone ──git push──► VPS (vault.git bare repo)
                                │
                         post-receive hook
                                │
                                ▼
                    VPS working copy (/srv/nazar/vault)
                                │
                    cron (every 5 min)
                                │
                    auto-commit + push
                                │
                                ▼
                    VPS (vault.git bare repo)
                                │
Laptop/Phone ◄──git pull───────┘
```

---

## Configuration

### Environment Variables (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | auto-generated | Gateway authentication token |
| `OPENCLAW_GATEWAY_PORT` | 18789 | Gateway bind port |
| `VAULT_DIR` | `/srv/nazar/vault` | Vault path on host |
| `OPENCLAW_CONFIG_DIR` | `/srv/nazar/data/openclaw` | Config path |
| `WHISPER_MODEL` | `small` | Whisper model size |

### OpenClaw Config (`deploy/openclaw.json`)

Key settings:
- **Sandbox mode:** `non-main` — group chats are sandboxed, direct chats have full access
- **Gateway:** Token auth, binds to loopback, Tailscale Serve enabled
- **Max concurrent:** 4 agents, 8 subagents

### Deploy Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NAZAR_ROOT` | `/srv/nazar` | Base installation directory |
| `DEPLOY_USER` | `debian` | OS user that owns files |
| `VAULT_GIT_REMOTE` | *(unset)* | External git remote (GitHub/GitLab) |

---

## Security Model

Defense-in-depth with 6 layers:

1. **Network:** Tailscale VPN + UFW firewall — zero public ports
2. **Authentication:** SSH keys + gateway tokens — no passwords
3. **Container:** Docker isolation — agent only sees `/vault`
4. **Agent Sandbox:** Group chats run in sandboxed Docker containers
5. **Secrets:** API keys in `.env`, never in vault
6. **Auto-Patching:** Unattended security upgrades daily

### Security Audit

```bash
# Run full security audit
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

Checks: root login disabled, SSH key-only, firewall active, Fail2Ban running, auto-updates enabled, Tailscale connected, no secrets in vault.

---

## Code Style Guidelines

### File Naming
- **Folders:** kebab-case with numeric prefix (`01-daily-journey/`, not `01 Daily Journey/`)
- **Daily notes:** `YYYY-MM-DD.md`
- **Templates:** descriptive names with underscores (`daily_note_template.md`)
- **No spaces in folder names** — prevents quoting issues across Docker/shell

### Python Skills
- Use environment variables for paths: `os.environ.get("VAULT_PATH", "/vault")`
- Never hardcode user paths like `/home/debian/`
- Import sibling skills via relative path manipulation
- Keep skills self-contained

### Git Conventions
- Commit message: present tense, descriptive
- Agent commits as user `Nazar <nazar@vps>`
- Auto-commit every 5 minutes via cron

---

## Troubleshooting

### Quick Diagnostics

```bash
# Everything at a glance
echo "=== Tailscale ===" && tailscale status
echo "=== Docker ===" && cd /srv/nazar && docker compose ps
echo "=== Firewall ===" && sudo ufw status
echo "=== Vault Git ===" && git -C /srv/nazar/vault log --oneline -3
echo "=== Sync Log ===" && tail -5 /srv/nazar/data/git-sync.log
```

### Common Issues

**Container can't write to vault:**
```bash
sudo chown -R debian:vault /srv/nazar/vault
sudo find /srv/nazar/vault -type d -exec chmod 2775 {} +
```

**Git push rejected (non-fast-forward):**
```bash
git pull --rebase origin main
git push origin main
```

**Build fails (out of memory):**
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

**Device pairing required:**
```bash
openclaw devices list
openclaw devices approve <request-id>
```

See `docs/troubleshooting.md` for full details.

---

## Documentation Index

| Document | Description |
|----------|-------------|
| `docs/README.md` | Project overview and quick start |
| `docs/architecture.md` | System design and data flow |
| `docs/deployment.md` | VPS provisioning walkthrough |
| `docs/vault-structure.md` | PARA method and folder conventions |
| `docs/agent.md` | Nazar agent system and workspace |
| `docs/skills.md` | Available skills reference |
| `docs/security.md` | Security model and hardening |
| `docs/git-sync.md` | Multi-device synchronization |
| `docs/troubleshooting.md` | Common issues and fixes |

---

## Gateway Management (Post-Setup)

### Device Pairing

New browsers/devices must be approved before accessing the Control UI:

```bash
# List pending devices
dopenclaw devices list

# Approve by request ID
dopenclaw devices approve <request-id>

# Restart gateway to apply
drestart
```

Device files location:
- `/srv/nazar/data/openclaw/devices/pending.json` — New requests
- `/srv/nazar/data/openclaw/devices/paired.json` — Approved devices

### Bash Aliases

The following aliases are configured on the VPS (`~/.nazar_aliases`):

| Alias | Command |
|-------|---------|
| `dopenclaw` | `docker compose ... exec openclaw-gateway npx openclaw` |
| `dclaw` | Shorthand for `dopenclaw` |
| `dnazar` or `dn` | Docker compose for Nazar stack |
| `dps` | `dnazar ps` — Container status |
| `dlogs` | `dnazar logs -f` — Follow logs |
| `drestart` | `dnazar restart` — Restart gateway |

### Common Operations

```bash
# Health check
dopenclaw doctor

# Fix auto-detected issues
dopenclaw doctor --fix

# Configure API keys and channels
dopenclaw configure

# View logs
dlogs

# Restart gateway
drestart
```

---

## Extension Points

| Want to... | Do this |
|------------|---------|
| Add a new skill | Create folder in `vault/99-system/openclaw/skills/` |
| Change agent personality | Edit `vault/99-system/openclaw/workspace/SOUL.md` |
| Add an LLM provider | Run `dopenclaw configure` |
| Add a channel | Run `dopenclaw configure` (WhatsApp, Telegram, etc.) |
| Change vault structure | Rename folders, update skills that reference paths |

---

*This file is the AI agent's entry point to understanding the project. Keep it accurate and up-to-date.*
