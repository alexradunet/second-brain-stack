# Architecture

## System Overview

The Second Brain is three layers: content, intelligence, and infrastructure.

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CONTENT LAYER                              │
│                                                                      │
│  ~/nazar/vault/                                                      │
│  ├── 00-inbox/  01-daily-journey/  02-projects/  03-areas/  ...    │
│  └── 99-system/                                                      │
│      ├── openclaw/workspace/    ← Agent personality + memory         │
│      ├── openclaw/skills/       ← Agent capabilities                 │
│      └── templates/             ← Obsidian templates                 │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                       INTELLIGENCE LAYER                             │
│                                                                      │
│  OpenClaw Gateway (Docker container)                                 │
│  ├── Nazar agent                                                     │
│  │   ├── SOUL.md    → personality                                    │
│  │   ├── AGENTS.md  → behavior rules                                 │
│  │   └── USER.md    → knowledge about you                            │
│  └── LLM backends   → configured via `openclaw configure`            │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                      INFRASTRUCTURE LAYER                            │
│                                                                      │
│  VPS (Debian/Ubuntu)                                                 │
│  ├── Docker         → container runtime                              │
│  ├── Syncthing      → real-time vault synchronization                │
│  ├── UFW + Fail2Ban → firewall + brute-force protection              │
│  └── SSH/Tailscale  → secure access (no public ports)                │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Obsidian Vault (`~/nazar/vault/`)

The vault is the single source of truth. Everything — your notes, the agent's brain, templates, skills — lives here. It syncs across all devices via Syncthing.

The agent's workspace is at `~/nazar/.openclaw/workspace/` (mounted to `/home/node/.openclaw/workspace` in the container). This is separate from the vault for configuration management while still being backed up.

### 2. OpenClaw Gateway (Docker Container)

The AI gateway runs in a Docker container (`nazar-openclaw`):
- **Base image**: Node.js 22 (bookworm-slim)
- **User**: `node` (UID 1000)
- **Ports**: 18789 (gateway)
- **Volumes**: 
  - `~/nazar/.openclaw/` → `/home/node/.openclaw/`
  - `~/nazar/vault/` → `/vault/`

### 3. Syncthing (Docker Container)

File synchronization runs in a Docker container (`nazar-syncthing`):
- **Base image**: `syncthing/syncthing:latest`
- **User**: 1000:1000
- **Ports**: 8384 (web UI), 22000 (sync), 21027 (discovery)
- **Volumes**:
  - `~/nazar/vault/` → `/var/syncthing/vault/`
  - `~/nazar/syncthing/config/` → `/var/syncthing/config/`

### 4. Security Layer

- **SSH**: Key-based authentication, root login disabled
- **UFW**: Firewall blocks all incoming except SSH
- **Fail2ban**: Blocks IPs after 3 failed login attempts
- **Docker**: Container isolation, non-root execution

## Data Flow

### Vault Synchronization

```
Laptop (Obsidian)
       │
       │ Edit note
       ▼
Syncthing (laptop) ──► Syncthing (VPS) ──► Syncthing (phone)
       │                      │
       │                      ▼
       │               ~/nazar/vault/
       │                      │
       │                      ▼
       │               OpenClaw (read/write)
       │
       ▼
Real-time sync to all devices
```

### AI Interaction

```
User (via WhatsApp/Telegram/Web)
       │
       │ Message
       ▼
OpenClaw Gateway
       │
       ├─► LLM API (Claude/GPT-4)
       │
       ├─► Write to ~/nazar/vault/01-daily-journey/
       │
       └─► Syncthing syncs to all devices
```

## Access Patterns

### SSH Tunnel (Default)

```
Laptop ──SSH──► VPS
         Tunnel: localhost:18789 → VPS:18789
         Tunnel: localhost:8384 → VPS:8384
```

Most secure - no ports exposed to internet.

### Tailscale (Optional)

```
Laptop ──Tailscale──► VPS ──Tailscale──► Phone
       Mesh VPN with encrypted connections
```

For multi-device access without SSH tunnels.

## File Locations

| Path (Host) | Path (Container) | Purpose |
|-------------|------------------|---------|
| `~/nazar/vault/` | `/vault/` (OpenClaw)<br>`/var/syncthing/vault/` (Syncthing) | Obsidian vault |
| `~/nazar/.openclaw/` | `/home/node/.openclaw/` | OpenClaw config |
| `~/nazar/.openclaw/workspace/` | `/home/node/.openclaw/workspace/` | Agent workspace |
| `~/nazar/syncthing/config/` | `/var/syncthing/config/` | Syncthing database |

## Container Communication

```
┌─────────────────────────────────────────────┐
│              Docker Network                 │
│         (nazar-internal bridge)             │
│                                             │
│  ┌──────────────┐    ┌──────────────┐      │
│  │   OpenClaw   │◄──►│  Syncthing   │      │
│  │   :18789     │    │   :8384      │      │
│  └──────────────┘    └──────────────┘      │
│         │                                   │
│         └──────────────────┐                │
│                            ▼                │
│                    ~/nazar/vault/           │
│                    (bind mount)             │
└─────────────────────────────────────────────┘
```

Containers communicate through the shared vault bind mount. OpenClaw reads/writes notes, Syncthing syncs them.

## Update Flow

1. **Docker Images**: `docker compose pull && docker compose up -d`
2. **Configuration**: Edit `~/nazar/.openclaw/openclaw.json`
3. **Vault**: Changes sync automatically via Syncthing
4. **Security**: Automatic via unattended-upgrades

## Security Boundaries

```
┌─────────────────────────────────────────────────────┐
│  Host (Debian/Ubuntu)                               │
│  ├── debian user (runs Docker)                      │
│  ├── UFW firewall                                   │
│  └── Fail2ban                                       │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Docker Engine                               │   │
│  │                                              │   │
│  │  ┌──────────────┐  ┌──────────────┐         │   │
│  │  │  Container   │  │  Container   │         │   │
│  │  │  UID 1000    │  │  UID 1000    │         │   │
│  │  │  read-only   │  │  read-only   │         │   │
│  │  │  root fs     │  │  root fs     │         │   │
│  │  └──────────────┘  └──────────────┘         │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

- Host firewall (UFW) protects the VPS
- Docker provides process isolation
- Containers run as non-root
- Read-only root filesystems
- No new privileges allowed
