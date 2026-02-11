# Architecture

## System Overview

The Second Brain is three layers: content, intelligence, and infrastructure.

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CONTENT LAYER                              │
│                                                                      │
│  vault/                                                              │
│  ├── 00-inbox/  01-daily-journey/  02-projects/  03-areas/  ...    │
│  └── 99-system/                                                      │
│      ├── openclaw/workspace/    ← Agent personality + memory         │
│      ├── openclaw/skills/       ← Agent capabilities                 │
│      └── templates/             ← Obsidian templates                 │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                       INTELLIGENCE LAYER                             │
│                                                                      │
│  OpenClaw Gateway (systemd user service)                             │
│  ├── Nazar agent                                                     │
│  │   ├── SOUL.md    → personality                                    │
│  │   ├── AGENTS.md  → behavior rules                                 │
│  │   └── USER.md    → knowledge about you                            │
│  ├── Whisper STT    → voice message transcription                    │
│  ├── Piper TTS      → voice reply generation                         │
│  └── LLM backends   → configured via `openclaw configure`            │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                      INFRASTRUCTURE LAYER                            │
│                                                                      │
│  VPS (Debian 13)                                                     │
│  ├── Tailscale      → encrypted overlay network                      │
│  ├── Syncthing      → real-time vault synchronization                │
│  ├── Users          → debian (admin) + nazar (service)               │
│  ├── UFW + Fail2Ban → firewall + brute-force protection              │
│  └── systemd        → service management + sandboxing                │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Obsidian Vault (`vault/`)

The vault is the single source of truth. Everything — your notes, the agent's brain, templates, skills — lives here. It syncs across all devices via Syncthing over Tailscale.

The agent's workspace is embedded at `vault/99-system/openclaw/workspace/`. This means when you sync the vault, you sync the agent's personality and memory too.

### 2. OpenClaw Gateway (systemd service)

The OpenClaw gateway runs as a systemd user service under the `nazar` user:

- Receives messages from WhatsApp, Telegram, or web chat
- Routes them to the Nazar agent
- Provides the agent with access to the vault at `/home/nazar/vault`
- Runs voice processing (Whisper STT, Piper TTS) locally

The gateway binds to loopback and uses integrated Tailscale Serve to expose at `https://<tailscale-hostname>/`.

### 3. Syncthing Vault Sync

Syncthing provides real-time bidirectional sync:

```
Laptop ◄────► VPS ◄────► Phone
Syncthing    Syncthing   Syncthing
~/vault      ~/vault     ~/vault
     \________/
    Tailscale VPN
```

- **Conflict handling**: Creates `.sync-conflict-*` files instead of blocking
- **Versioning**: Simple file versioning protects against accidental deletes
- **Encryption**: All traffic over Tailscale's WireGuard encryption
- **No polling**: Instant sync when files change

### 4. User Model

| User | Purpose | Permissions |
|------|---------|-------------|
| `debian` | System administrator | sudo access, SSH login |
| `nazar` | Service account | Runs OpenClaw + Syncthing, owns vault |

**Key security features:**
- `nazar` has **no sudo access** — cannot escalate privileges
- `nazar` password is **locked** — cannot login interactively
- `nazar` home directory is `drwx------` — only owner can read
- Services run with systemd sandboxing (NoNewPrivileges, PrivateTmp, etc.)

### 5. Tailscale

All services are only reachable via Tailscale's encrypted mesh VPN (`100.x.x.x` addresses). No public ports are needed.

## Data Flow

### Voice Message → Daily Journal

```
Phone (WhatsApp)
    │ voice message
    ▼
OpenClaw Gateway (https://<tailscale-hostname>/)
    │
    ▼
Whisper STT (local, in venv)
    │ transcribed text
    ▼
Obsidian skill (obsidian.py)
    │ append with timestamp
    ▼
/home/nazar/vault/01-daily-journey/2026/02-February/2026-02-11.md
    │
    ▼
Syncthing syncs to all devices instantly
```

### Agent Workspace Loading

```
Session starts
    │
    ▼
Read SOUL.md → "who am I"
Read USER.md → "who am I helping"
Read AGENTS.md → "how should I behave"
Read memory/today.md → "what happened recently"
    │
    ▼
Agent is ready to respond
```

### Configuration Flow

```
nazar/config/openclaw.json
    │ copied to VPS at setup
    ▼
/home/nazar/.openclaw/openclaw.json
    │
    ▼
OpenClaw reads config, starts gateway
    │ workspace path
    ▼
/home/nazar/vault/99-system/openclaw/workspace/
```

## Network Topology

```
Internet                    VPS Firewall (UFW)           Services
─────────────────────────────────────────────────────────────────────
                            DENY all incoming
                            ─────────────────
Public IP ──► *         ──► DENY (no public ports needed)

Tailscale ──► 22/tcp   ──► ALLOW ──► sshd (tailscale0 only)
(100.x.x.x)                          ├── interactive SSH
                                      └── admin access

Tailscale ──► 8384/tcp ──► ALLOW ──► Syncthing GUI (tailscale0 only)
              HTTPS/443 ──► Tailscale Serve ──► loopback:18789
                                        └── OpenClaw gateway
```

**Note:** No public ports exposed. All access flows through Tailscale.

## File Locations

| Path | Owner | Purpose |
|------|-------|---------|
| `/home/nazar/vault/` | `nazar:nazar` | Obsidian vault (mode 700) |
| `/home/nazar/.openclaw/` | `nazar:nazar` | OpenClaw config + state (mode 700) |
| `/home/nazar/.local/state/syncthing/` | `nazar:nazar` | Syncthing data |
| `/home/debian/` | `debian:debian` | Admin user home |

## Extension Points

| Want to... | Do this |
|------------|---------|
| Add a new skill | Create folder in `vault/99-system/openclaw/skills/` |
| Change agent personality | Edit `vault/99-system/openclaw/workspace/SOUL.md` |
| Add an LLM provider | Run `sudo -u nazar openclaw configure` |
| Add a new channel | Run `sudo -u nazar openclaw configure` |
| Change vault structure | Rename folders, update `AGENTS.md` + `obsidian/SKILL.md` |
| Enhance security | Run `sudo bash system/scripts/setup-all-security.sh` |
