# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Syncthing, and hosted on a hardened Debian VPS behind Tailscale.

**Architecture:** Two deployment options:
1. **Docker** (Recommended) — Containerized OpenClaw + Syncthing with shared volume
2. **Direct** — Simple execution under dedicated user (systemd)

---

## Project Overview

This project consists of three integrated layers:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method
2. **Intelligence Layer** (OpenClaw Gateway) — The Nazar AI agent that processes voice messages and manages daily journals
3. **Infrastructure Layer** — Services running in Docker containers or directly on VPS

```
second-brain/
├── vault/                ← Obsidian vault (PARA structure + agent config)
│   ├── 00-inbox/         ← Quick capture
│   ├── 01-daily-journey/ ← Daily notes (YYYY/MM-MMMM/YYYY-MM-DD.md)
│   ├── 02-projects/      ← Active projects with goals/deadlines
│   ├── 03-areas/         ← Life areas requiring ongoing attention
│   ├── 04-resources/     ← Reference material
│   ├── 05-archive/       ← Completed/inactive items
│   └── 99-system/        ← Agent workspace, skills, templates
├── docker/               ← Docker deployment files (recommended)
│   ├── docker-compose.yml
│   ├── Dockerfile.openclaw
│   ├── setup.sh
│   └── nazar-cli.sh
├── nazar/                ← Service user configuration (direct mode)
│   ├── config/           ← OpenClaw config templates
│   └── scripts/          ← Setup scripts for services
├── bootstrap/            ← VPS bootstrap files (direct mode)
├── system/               ← System administration
│   ├── scripts/          ← Admin helper scripts
│   └── docs/             ← Admin documentation
└── docs/                 ← User documentation
```

---

## Deployment: Docker (Recommended)

OpenClaw and Syncthing run in Docker containers with a shared volume for the vault. Docker provides process isolation, eliminating the need for a separate service user.

**Benefits:**
- Isolated, reproducible environment
- Easy updates (pull new images)
- Consistent across different hosts
- Simplified backup/restore
- No separate service user needed

```bash
# Quick start
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│              VPS (Single debian user)                       │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   OpenClaw   │  │  Syncthing   │  │   SSH/       │      │
│  │  Container   │  │  Container   │  │  Tailscale   │      │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘      │
│         └─────────────────┼─────────────────┘               │
│                  ┌────────┴────────┐                        │
│                  │  ~/nazar/vault  │                        │
│                  │  (bind mount)   │                        │
│                  └─────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

**Deployment Modes:**
- **SSH Tunnel** (default): Access via `ssh -L 18789:localhost:18789 debian@vps`
- **Tailscale**: Mesh VPN for multi-device access

---

## User Model

| User | Purpose | Permissions |
|------|---------|-------------|
| `debian` | System administrator | SSH login, runs Docker containers |
| `1000:1000` | Container user | Inside Docker containers |

Docker provides isolation - no separate service user needed on the host.

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| **Gateway** | OpenClaw Docker image |
| **Sync** | Syncthing official Docker image |
| **Networking** | SSH tunnel (default) or Tailscale container |
| **Voice Processing** | Optional: Whisper + Piper in container |
| **OS** | Debian 13 / Ubuntu 22.04+ |
| **PKM App** | Obsidian |
| **Container Runtime** | Docker + Docker Compose |

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
| `05-archive/` | Completed or inactive items |
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
VPS provisioning and security hardening scripts.

---

## Bootstrap and Deployment

### Quick Deploy

```bash
# On fresh Debian/Ubuntu VPS
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

See [docker/HETZNER.md](docker/HETZNER.md) for detailed Hetzner VPS deployment.

### What the Setup Does

1. **Installs Docker** — Container runtime
2. **Creates directory structure** — `~/nazar/` with vault, config, workspace
3. **Generates OpenClaw config** — With secure token
4. **Starts containers** — OpenClaw + Syncthing
5. **Configures permissions** — UID 1000 for container access

### Post-Setup

```bash
# Access services via SSH tunnel
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@vps-ip

# Then open:
# - OpenClaw: http://localhost:18789
# - Syncthing: http://localhost:8384
```

---

## Service Management

```bash
cd ~/nazar/docker

# Status
docker compose ps

# Start/Stop/Restart
docker compose up -d
docker compose down
docker compose restart

# Logs
docker compose logs -f
docker compose logs -f openclaw

# Or use the CLI helper
nazar-cli status
nazar-cli logs
nazar-cli restart
nazar-cli shell
nazar-cli configure
nazar-cli backup
```

---

## Vault Synchronization (Syncthing)

Syncthing provides real-time bidirectional sync:

```
Laptop ◄──────────────────► VPS ◄──────────────────► Phone
Syncthing                  Syncthing               Syncthing
~/vault                    ~/nazar/vault           ~/vault
      \________________________/
         SSH Tunnel or Internet
```

### Setup

1. **VPS**: Syncthing runs in container on port 8384
2. **Devices**: Add VPS device ID to laptop/phone Syncthing
3. **Folder**: Share `nazar-vault` folder across devices
4. **Sync**: Changes propagate instantly (no cron needed)

### Conflict Handling

Syncthing creates `.sync-conflict-YYYYMMDD-HHMMSS.md` files instead of blocking sync. This is much more reliable than Git merge conflicts.

---

## Configuration

### OpenClaw

Config: `~/nazar/.openclaw/openclaw.json`

Key settings:
- **Sandbox mode**: `non-main` — group chats are sandboxed
- **Gateway**: Token auth, binds to 0.0.0.0 inside container
- **Workspace**: `~/nazar/.openclaw/workspace/` → `/home/node/.openclaw/workspace`
- **Vault**: `~/nazar/vault/` → `/vault`

### Environment

Environment file: `~/nazar/docker/.env`

Key variables:
- `DEPLOYMENT_MODE` — `sshtunnel` or `tailscale`
- `OPENCLAW_GATEWAY_BIND` — `127.0.0.1` (SSH) or `0.0.0.0` (Tailscale)
- `TAILSCALE_AUTHKEY` — Tailscale authentication key
- `ANTHROPIC_API_KEY` — Claude API key
- `OPENAI_API_KEY` — OpenAI API key

---

## Security Model

Defense-in-depth with 4 layers:

1. **Network**: SSH tunnel (localhost only) or Tailscale VPN — zero public ports
2. **Authentication**: SSH keys only — no passwords, no root login
3. **Container Isolation**: Services run as non-root UID 1000 inside containers
4. **Secrets**: API keys in `~/nazar/docker/.env`, never in vault

### Security Audit

```bash
cd ~/nazar/docker
docker compose exec openclaw openclaw health
nazar-cli status

# Check firewall
sudo ufw status

# Check SSH config
grep "PermitRootLogin\|PasswordAuthentication" /etc/ssh/sshd_config
```

---

## Code Style Guidelines

### File Naming
- **Folders**: kebab-case with numeric prefix (`01-daily-journey/`)
- **Daily notes**: `YYYY-MM-DD.md`
- **Templates**: descriptive names with underscores
- **No spaces in folder names** — prevents quoting issues

### Python Skills
- Use environment variables for paths: `os.environ.get("VAULT_PATH", "/opt/nazar/vault")`
- Never hardcode user paths
- Keep skills self-contained

---

## Troubleshooting

### Quick Diagnostics

```bash
cd ~/nazar/docker

# Everything at a glance
docker compose ps
docker compose logs --tail=50

# Service-specific
docker compose logs openclaw
docker compose logs syncthing
docker compose logs tailscale
```

### Common Issues

**Syncthing not syncing:**
```bash
docker compose exec syncthing syncthing cli show connections
docker compose restart syncthing
```

**OpenClaw won't start:**
```bash
docker compose logs openclaw
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json
```

**Permission denied on vault:**
```bash
chown -R 1000:1000 ~/nazar/vault
```

**Can't access via SSH tunnel:**
```bash
# On laptop
ssh -N -L 18789:localhost:18789 debian@YOUR_VPS_IP

# Check if services are listening
docker compose exec openclaw netstat -tlnp
docker compose exec syncthing netstat -tlnp
```

---

## Documentation Index

| Document | Description |
|----------|-------------|
| `docker/README.md` | Docker deployment guide |
| `docker/HETZNER.md` | Hetzner VPS deployment guide |
| `docker/SECURITY.md` | Security hardening and best practices |
| `docs/README.md` | Project overview and quick start |
| `docs/architecture.md` | System design and data flow |
| `docs/vault-structure.md` | PARA method and folder conventions |
| `docs/agent.md` | Nazar agent system and workspace |
| `docs/skills.md` | Available skills reference |
| `docs/syncthing-setup.md` | Syncthing configuration |
| `docs/openclaw-config.md` | OpenClaw configuration |
| `docs/troubleshooting.md` | Common issues and fixes |
| `system/docs/admin-guide.md` | System administration guide |

---

## Gateway Management (Post-Setup)

### Device Pairing

New browsers/devices must be approved before accessing the Control UI:

```bash
docker compose exec openclaw openclaw devices list
docker compose exec openclaw openclaw devices approve <request-id>
```

### Helper Commands

| Command | Purpose |
|---------|---------|
| `nazar-cli status` | Service status check |
| `nazar-cli logs` | View logs |
| `nazar-cli restart` | Restart services |
| `nazar-cli backup` | Create backup |
| `nazar-cli token` | Show gateway token |
| `nazar-cli tunnel` | Show SSH tunnel command |
| `nazar-cli syncthing-id` | Show Syncthing Device ID |

---

## Extension Points

| Want to... | Do this |
|------------|---------|
| Add a new skill | Create folder in `~/nazar/.openclaw/workspace/skills/` |
| Change agent personality | Edit `~/nazar/.openclaw/workspace/SOUL.md` |
| Add an LLM provider | Run `nazar-cli configure` |
| Add a channel | Run `nazar-cli configure` |
| Change vault structure | Rename folders in `~/nazar/vault/`, update skills |
| Customize Docker | Edit `~/nazar/docker/docker-compose.yml` |
| Add extra packages | Set `OPENCLAW_EXTRA_PACKAGES` in `.env` |

---

*This file is the AI agent's entry point to understanding the project. Keep it accurate and up-to-date.*
