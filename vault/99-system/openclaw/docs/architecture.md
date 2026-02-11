# Architecture

How Nazar works under the hood.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        OVH VPS (Debian 13)                      │
│                                                                  │
│  Git (SSH over Tailscale) ◄──►  /srv/nazar/vault.git (bare repo)  │
│                                          │ post-receive hook       │
│                                          ▼                        │
│                               /srv/nazar/vault/ (working copy)    │
│                                          │ bind mount             │
│                                          ▼                        │
│  ┌─────────────────┐     ┌──────────────────────────────────┐   │
│  │  OpenClaw GW     │────►│  /vault (inside container)       │   │
│  │  (container)     │     │  read/write vault only           │   │
│  │  host network    │     └──────────────────────────────────┘   │
│  └─────────────────┘                                              │
│          ▲                                                        │
│          │ Tailscale (100.x.x.x)                                 │
│          │                                                        │
└──────────┼────────────────────────────────────────────────────────┘
           │
     Your devices (phone, laptop)
```

## Components

### 1. OpenClaw Gateway (Docker container)

- Official OpenClaw Docker image extended with voice tools
- Receives messages from WhatsApp/Telegram
- Routes to the Nazar agent
- Vault bind-mounted at `/vault`
- Gateway API on port 18789 (127.0.0.1 only, Tailscale access)

### 2. Git-Based Vault Sync

- Bare repo at `/srv/nazar/vault.git/` with post-receive hook
- Working copy at `/srv/nazar/vault/` bind-mounted into container
- Auto-commit cron every 5 minutes for agent writes
- All sync over SSH through Tailscale — no public ports

### 3. Agent Workspace

Located at `99-system/openclaw/workspace/` (inside the vault):

| File | Purpose |
|------|---------|
| `SOUL.md` | Personality, values, how the agent responds |
| `USER.md` | What the agent knows about you |
| `AGENTS.md` | Guidelines for agent behavior |
| `TOOLS.md` | Environment-specific tool notes |
| `HEARTBEAT.md` | Periodic tasks to check |
| `MEMORY.md` | Long-term memories (created as needed) |

### 4. Skills System

Located at `99-system/openclaw/skills/`:

```
skills/
├── obsidian/           # Vault operations
│   ├── SKILL.md        # Documentation
│   ├── obsidian.py     # Python module
│   └── scripts/        # CLI tools
└── voice/              # Speech processing
    ├── SKILL.md
    ├── voice.py
    └── scripts/
```

### 5. Obsidian Vault Structure (PARA)

```
vault/
├── 00-inbox/              - Quick capture
├── 01-daily-journey/      - Daily notes (YYYY/MM-MMMM/YYYY-MM-DD.md)
├── 02-projects/           - Active projects with clear goals and deadlines
├── 03-areas/              - Life areas requiring ongoing attention
├── 04-resources/          - Reference material and knowledge base
├── 05-archive/             - Completed or inactive items
├── 99-system/             - Agent workspace, skills, templates, docs
│   ├── openclaw/          - Agent system
│   └── templates/         - Obsidian templates
└── .obsidian/             - Obsidian configuration
```

## Data Flow

### Voice Message Flow

```
WhatsApp Audio
       │
       ▼
   ┌──────────┐
   │ Whisper  │  (Local STT in container)
   │  (local) │
   └────┬─────┘
        │ Text
        ▼
   ┌──────────┐
   │ Timestamp│
   └────┬─────┘
        │
        ▼
Daily Note Append → 01-daily-journey/YYYY/MM-MMMM/YYYY-MM-DD.md
```

### Configuration Flow

```
deploy/openclaw.json → /home/node/.openclaw/openclaw.json (inside container)
                              │
                              │ (OpenClaw reads)
                              ▼
                       OpenClaw Gateway
                              │
                              │ (workspace bind mount)
                              ▼
                   /vault/99-system/openclaw/workspace/
```

## Security Model

| Layer | Mechanism |
|-------|-----------|
| Network | Tailscale-only SSH; gateway bound to 127.0.0.1 |
| Auth | Gateway token auth; SSH key-only access |
| Sandbox | `non-main` mode — group/channel sessions isolated in Docker |
| Filesystem | Agent only sees `/vault` via bind mount; no host filesystem access |
| Container | Non-root user (uid 1000); read-only root FS option available |
| Secrets | `.env` file on host, never committed; API keys via env vars |
| Vault sync | Git over SSH over Tailscale (WireGuard encryption) |

## Portability

Everything in `99-system/openclaw/` is portable:

1. **Git** syncs the vault (including agent workspace) across devices via SSH
2. **deploy/ repo** contains the Docker stack — push to VPS and run
3. Move to a new machine: clone vault + clone deploy repo + `setup-vps.sh`

## Extension Points

Add capabilities by:

1. **New skills** — Create folder in `99-system/openclaw/skills/`
2. **CLI tools** — Add to `skills/*/scripts/`
3. **Agent memory** — Edit files in `workspace/`
4. **Cron jobs** — Add to OpenClaw cron system

---

See [Skills Development](skills.md) for creating new capabilities.
