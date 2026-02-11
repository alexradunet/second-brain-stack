# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Syncthing, and hosted on a hardened Debian VPS behind Tailscale.

**Architecture:** Simple and secure — no Docker, direct execution under dedicated user.

---

## Project Overview

This project consists of three integrated layers:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method
2. **Intelligence Layer** (OpenClaw Gateway) — The Nazar AI agent that processes voice messages and manages daily journals
3. **Infrastructure Layer** — Simple services running directly on the VPS

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
├── nazar/                ← Service user configuration
│   ├── config/           ← OpenClaw config templates
│   └── scripts/          ← Setup scripts for services
├── system/               ← System administration
│   ├── scripts/          ← Admin helper scripts
│   └── docs/             ← Admin documentation
├── bootstrap/            ← VPS bootstrap files
└── docs/                 ← User documentation
```

---

## User Model

| User | Purpose | Permissions |
|------|---------|-------------|
| `debian` | System administrator | sudo access, SSH login |
| `nazar` | Service user | No sudo, runs OpenClaw + Syncthing |

This separation ensures that even if the service account is compromised, the attacker cannot gain root access.

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| **Gateway** | Node.js 22 + OpenClaw (npm global install) |
| **Voice Processing** | Python 3 + Whisper (STT) + Piper (TTS) |
| **Sync** | Syncthing (P2P over Tailscale) |
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

### Quick Start

```bash
# On fresh VPS as root
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash

# Follow on-screen instructions to:
# 1. Start Tailscale
# 2. Clone and copy vault
# 3. Start Syncthing
# 4. Configure OpenClaw
```

### What the Bootstrap Does

1. **Creates users**: `debian` (admin), `nazar` (service)
2. **Installs packages**: Node.js 22, OpenClaw, Syncthing, Tailscale
3. **Hardens security**: SSH keys only, firewall, fail2ban, auto-updates
4. **Sets up services**: systemd user services for OpenClaw and Syncthing
5. **Configures environment**: Paths, permissions, helper scripts

---

## Service Management

### OpenClaw Gateway

```bash
# As debian user (with sudo)
sudo -u nazar systemctl --user start openclaw
sudo -u nazar systemctl --user stop openclaw
sudo -u nazar systemctl --user restart openclaw

# Or use helper
nazar-restart

# Logs
nazar-logs
# or
sudo -u nazar journalctl --user -u openclaw -f
```

### Syncthing

```bash
# As debian user (with sudo)
sudo -u nazar systemctl --user start syncthing
sudo -u nazar systemctl --user stop syncthing

# Logs
sudo -u nazar journalctl --user -u syncthing -f

# CLI
sudo -u nazar syncthing cli show system
```

---

## Vault Synchronization (Syncthing)

Syncthing provides real-time bidirectional sync over Tailscale:

```
Laptop ◄──────────────────► VPS ◄──────────────────► Phone
Syncthing                  Syncthing               Syncthing
~/vault                    /home/nazar/vault       ~/vault
      \________________________/
              Tailscale VPN
```

### Setup

1. **VPS**: Syncthing runs as `nazar` user on port 8384
2. **Devices**: Add VPS device ID to laptop/phone Syncthing
3. **Folder**: Share `nazar-vault` folder across devices
4. **Sync**: Changes propagate instantly (no cron needed)

### Conflict Handling

Syncthing creates `.sync-conflict-YYYYMMDD-HHMMSS.md` files instead of blocking sync. This is much more reliable than Git merge conflicts.

---

## Configuration

### OpenClaw Config

Location: `/home/nazar/.openclaw/openclaw.json`

Key settings:
- **Sandbox mode**: `non-main` — group chats are sandboxed
- **Gateway**: Token auth, binds to loopback, Tailscale Serve enabled
- **Workspace**: Points to `vault/99-system/openclaw/workspace`

### Environment Variables

Set in `/home/nazar/.openclaw/.env`:
- `ANTHROPIC_API_KEY` — Claude API key
- `OPENAI_API_KEY` — OpenAI API key (if used)
- `VAULT_PATH` — `/home/nazar/vault`

---

## Security Model

Defense-in-depth with 5 layers:

1. **Network**: Tailscale VPN + UFW firewall — zero public ports
2. **Authentication**: SSH keys only — no passwords, no root login
3. **User Isolation**: `nazar` user has no sudo access
4. **Secrets**: API keys in `~/.openclaw/.env`, never in vault
5. **Auto-Patching**: Unattended security upgrades daily

### Security Audit

```bash
# Run from vault
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

Checks: root login disabled, SSH key-only, firewall active, Fail2Ban running, auto-updates enabled, Tailscale connected, no secrets in vault.

---

## Code Style Guidelines

### File Naming
- **Folders**: kebab-case with numeric prefix (`01-daily-journey/`)
- **Daily notes**: `YYYY-MM-DD.md`
- **Templates**: descriptive names with underscores
- **No spaces in folder names** — prevents quoting issues

### Python Skills
- Use environment variables for paths: `os.environ.get("VAULT_PATH", "/home/nazar/vault")`
- Never hardcode user paths
- Keep skills self-contained

---

## Troubleshooting

### Quick Diagnostics

```bash
# Everything at a glance
echo "=== Tailscale ===" && tailscale status
echo "=== Services ===" && nazar-status
echo "=== Firewall ===" && sudo ufw status
echo "=== Syncthing ===" && sudo -u nazar syncthing cli show system | head -5
```

### Common Issues

**Syncthing not syncing:**
```bash
# Check device connections
sudo -u nazar syncthing cli show connections

# Restart Syncthing
sudo -u nazar systemctl --user restart syncthing
```

**OpenClaw won't start:**
```bash
# Check config validity
sudo -u nazar jq . ~/.openclaw/openclaw.json

# Check logs
sudo -u nazar journalctl --user -u openclaw -n 50
```

**Permission denied on vault:**
```bash
sudo chown -R nazar:nazar /home/nazar/vault
```

---

## Documentation Index

| Document | Description |
|----------|-------------|
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
# List pending devices
sudo -u nazar openclaw devices list

# Approve by request ID
sudo -u nazar openclaw devices approve <request-id>

# Restart gateway to apply
sudo -u nazar systemctl --user restart openclaw
```

### Bash Aliases (as debian user)

| Alias | Command | Purpose |
|-------|---------|---------|
| `nazar-status` | Service status check | Quick health check |
| `nazar-logs` | View OpenClaw logs | Debug issues |
| `nazar-restart` | Restart OpenClaw | Apply config changes |

---

## Extension Points

| Want to... | Do this |
|------------|---------|
| Add a new skill | Create folder in `vault/99-system/openclaw/skills/` |
| Change agent personality | Edit `vault/99-system/openclaw/workspace/SOUL.md` |
| Add an LLM provider | Run `sudo -u nazar openclaw configure` |
| Add a channel | Run `sudo -u nazar openclaw configure` |
| Change vault structure | Rename folders, update skills |

---

*This file is the AI agent's entry point to understanding the project. Keep it accurate and up-to-date.*
