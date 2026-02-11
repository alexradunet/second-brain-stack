# Architecture

How Nazar works under the hood.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        OVH VPS (Debian 13)                      │
│                                                                  │
│  Syncthing (P2P over Tailscale) ◄──► /home/nazar/vault           │
│                                          │ direct filesystem      │
│                                          ▼                        │
│  ┌─────────────────┐     ┌──────────────────────────────────┐   │
│  │  OpenClaw GW     │────►│  /home/nazar/vault                │   │
│  │  (systemd user   │     │  read/write vault only            │   │
│  │   service)       │     └──────────────────────────────────┘   │
│  └─────────────────┘                                              │
│          ▲                                                        │
│          │ Tailscale Serve (HTTPS)                                │
│          │                                                        │
└──────────┼────────────────────────────────────────────────────────┘
           │
     Your devices (phone, laptop) via Tailscale (100.x.x.x)
```

## Components

### 1. OpenClaw Gateway (systemd user service)

- Installed globally via `npm install -g openclaw`
- Runs as the `nazar` user under systemd (`openclaw.service`)
- Receives messages from WhatsApp/Telegram
- Routes to the Nazar agent
- Vault accessed directly at `/home/nazar/vault`
- Gateway API on port 18789 (127.0.0.1 only, exposed via Tailscale Serve)

### 2. Syncthing-Based Vault Sync

- Runs as the `nazar` user under systemd (`syncthing.service`)
- Real-time P2P sync across all devices over Tailscale
- No public ports — communicates through Tailscale mesh
- No cron jobs or manual commits — changes sync automatically

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
├── 05-archive/            - Completed or inactive items
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
   │ Whisper  │  (Local STT via Python venv)
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
        │
        ▼
   Syncthing → All devices (real-time)
```

### Configuration Flow

```
/home/nazar/.openclaw/openclaw.json
                      │
                      │ (OpenClaw reads)
                      ▼
               OpenClaw Gateway
                      │
                      │ (direct filesystem)
                      ▼
           /home/nazar/vault/99-system/openclaw/workspace/
```

## Security Model

| Layer | Mechanism |
|-------|-----------|
| Network | Tailscale-only SSH; gateway bound to 127.0.0.1 |
| Auth | Gateway token auth; SSH key-only access |
| User isolation | `nazar` service user (no sudo, locked password, home 700) |
| Sandbox | `non-main` mode — group/channel sessions sandboxed by systemd |
| Filesystem | systemd `ProtectSystem=strict`, `ReadWritePaths` limited to vault + config |
| Secrets | `openclaw.json` in mode-700 directory, never committed to vault |
| Vault sync | Syncthing over Tailscale (WireGuard encryption) |

## Portability

Everything in `99-system/openclaw/` is portable:

1. **Syncthing** syncs the vault (including agent workspace) across devices automatically
2. **bootstrap.sh** sets up a new VPS from scratch — one command
3. Move to a new machine: run bootstrap + set up Syncthing + configure OpenClaw

## Extension Points

Add capabilities by:

1. **New skills** — Create folder in `99-system/openclaw/skills/`
2. **CLI tools** — Add to `skills/*/scripts/`
3. **Agent memory** — Edit files in `workspace/`
4. **Cron jobs** — Add to OpenClaw cron system

---

See [Skills Development](skills.md) for creating new capabilities.
