# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Syncthing, and hosted on a hardened OVHcloud Debian 13 VPS.

**Architecture:** Docker containers with shared vault volume.

---

## Project Overview

Three integrated layers:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method
2. **Intelligence Layer** (OpenClaw Gateway) — The Nazar AI agent
3. **Infrastructure Layer** — Docker containers (OpenClaw + Syncthing)

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

## Deployment

OpenClaw and Syncthing run in Docker containers with a shared volume for the vault.

```bash
# Quick start
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│              VPS (Single debian user)                       │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │   OpenClaw   │  │  Syncthing   │                        │
│  │  Container   │  │  Container   │                        │
│  └──────┬───────┘  └──────┬───────┘                        │
│         └─────────────────┼─────────────────┘               │
│                  ┌────────┴────────┐                        │
│                  │  ~/nazar/vault  │                        │
│                  │  (bind mount)   │                        │
│                  └─────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

**Access Modes:**
- **SSH Tunnel** (default): `ssh -L 18789:localhost:18789 debian@vps`
- **Tailscale**: Mesh VPN for multi-device access

---

## User Model

| User | Purpose | Permissions |
|------|---------|-------------|
| `debian` | System administrator | SSH login, runs Docker containers |
| `1000:1000` | Container user | Inside Docker containers |

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| **Gateway** | OpenClaw Docker image |
| **Sync** | Syncthing official Docker image |
| **Networking** | SSH tunnel (default) or Tailscale container |
| **OS** | Debian 13 (OVHcloud) |
| **PKM App** | Obsidian |
| **Container Runtime** | Docker + Docker Compose |

---

## Vault Structure (PARA Method)

| Folder | Purpose |
|--------|---------|
| `00-inbox/` | Quick capture |
| `01-daily-journey/` | Daily journal notes (`YYYY/MM-MMMM/YYYY-MM-DD.md`) |
| `02-projects/` | Active projects with goals and deadlines |
| `03-areas/` | Life areas requiring ongoing attention |
| `04-resources/` | Reference material and knowledge base |
| `05-archive/` | Completed or inactive items |
| `99-system/` | System configuration (agent workspace, templates) |

### Daily Note Format

```markdown
---

**[14:32]**

Transcribed voice note content...
```

---

## Agent Workspace

The agent's "brain" lives at `~/nazar/.openclaw/workspace/` (mounted at `/home/node/.openclaw/workspace` in container):

| File | Purpose |
|------|---------|
| `SOUL.md` | Agent personality and values |
| `AGENTS.md` | Behavior rules and operational guidelines |
| `USER.md` | User profile and preferences |
| `IDENTITY.md` | Agent self-concept |
| `MEMORY.md` | Long-term curated memory |
| `TOOLS.md` | Environment notes |
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

Skills are self-contained modules in `~/nazar/.openclaw/workspace/skills/`:

### obsidian/
Vault operations: read/write notes, manage daily journal.

**Key functions:**
- `get_daily_note_path()` — Path for today's note
- `create_daily_note(content)` — Create daily note
- `append_to_daily_note(content)` — Append with timestamp
- `create_note(title, content, folder)` — Create note in any folder
- `read_note(path)` — Read a note

### voice/
Local speech-to-text (Whisper) and text-to-speech (Piper).

**Key functions:**
- `transcribe_audio(audio_path)` — Audio → text
- `transcribe_and_save(audio_path)` — Full pipeline: transcribe → daily note
- `generate_speech(text)` — Text → WAV

---

## Bootstrap and Deployment

### Quick Deploy

```bash
# On fresh OVHcloud Debian 13 VPS
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

See [docker/VPS-GUIDE.md](docker/VPS-GUIDE.md) for detailed VPS deployment.

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
4. **Sync**: Changes propagate instantly

### Conflict Handling

Syncthing creates `.sync-conflict-YYYYMMDD-HHMMSS.md` files instead of blocking sync.

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
3. **User Isolation**: Service user has no sudo access (direct) / containers run as non-root (Docker)
4. **Secrets**: API keys in `.env` file, never in vault

### Security Audit

```bash
# Run security audit
sudo nazar-security-audit

# Or check manually
cd ~/nazar/docker
docker compose exec openclaw openclaw health
nazar-cli status
sudo ufw status
```

---

## Code Style Guidelines

### File Naming
- **Folders**: kebab-case with numeric prefix (`01-daily-journey/`)
- **Daily notes**: `YYYY-MM-DD.md`
- **Templates**: descriptive names with underscores
- **No spaces in folder names** — prevents quoting issues

### Python Skills
- Use environment variables for paths: `os.environ.get("VAULT_PATH", "~/nazar/vault")`
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

---

## Documentation Index

| Document | Description |
|----------|-------------|
| `docker/README.md` | Docker deployment guide |
| `docker/VPS-GUIDE.md` | OVHcloud Debian 13 VPS deployment guide |
| `docker/SECURITY.md` | Security hardening and best practices |
| `docker/MIGRATION.md` | Migration from old systemd setup |
| `docs/README.md` | Project overview and quick start |
| `docs/vault-structure.md` | PARA method and folder conventions |
| `docs/agent.md` | Nazar agent system and workspace |
| `docs/skills.md` | Available skills reference |
| `docs/syncthing-setup.md` | Syncthing configuration |
| `docs/openclaw-config.md` | OpenClaw configuration |
| `docs/troubleshooting.md` | Common issues and fixes |

---

## Post-Infrastructure

Once infrastructure is running, configure services through their own UIs:

1. **Syncthing** — Open the Syncthing GUI (`http://localhost:8384` via SSH tunnel), add devices, share the vault folder
2. **OpenClaw** — Run the onboarding wizard: `docker compose exec -it openclaw openclaw configure`

### Infrastructure Management

| Command | Purpose |
|---------|---------|
| `nazar-cli status` | Service status check |
| `nazar-cli logs` | View logs |
| `nazar-cli restart` | Restart services |
| `nazar-cli backup` | Create backup |
| `nazar-cli tunnel` | Show SSH tunnel command |
| `nazar-cli security` | Run security audit |

---

*This file is the AI agent's entry point to understanding the project. Keep it accurate and up-to-date.*
