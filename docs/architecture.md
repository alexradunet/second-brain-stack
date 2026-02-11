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
│  OpenClaw Gateway (Docker container)                                 │
│  ├── Nazar agent                                                     │
│  │   ├── SOUL.md    → personality                                    │
│  │   ├── AGENTS.md  → behavior rules                                 │
│  │   └── USER.md    → knowledge about you                            │
│  ├── Whisper STT    → voice message transcription                    │
│  ├── Piper TTS      → voice reply generation                         │
│  └── LLM backends   → Claude Opus 4.6 / Kimi K2.5                   │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                      INFRASTRUCTURE LAYER                            │
│                                                                      │
│  VPS (Debian 13)                                                     │
│  ├── Tailscale      → encrypted overlay network                      │
│  ├── Docker          → container isolation                            │
│  ├── Git (bare repo) → vault sync over SSH                           │
│  ├── UFW + Fail2Ban  → firewall + brute-force protection             │
│  └── Unattended upgrades → automatic security patches                │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Obsidian Vault (`vault/`)

The vault is the single source of truth. Everything — your notes, the agent's brain, templates, skills — lives here. It syncs across all devices via Git over SSH (through Tailscale).

The agent's workspace is embedded at `vault/99-system/openclaw/workspace/`. This means when you sync the vault, you sync the agent's personality and memory too.

### 2. OpenClaw Gateway (Docker)

The OpenClaw gateway runs in a Docker container (`nazar-gateway`). It:

- Receives messages from WhatsApp, Telegram, or web chat
- Routes them to the Nazar agent
- Provides the agent with access to the vault at `/vault`
- Runs voice processing (Whisper STT, Piper TTS) locally

The gateway container uses `network_mode: host` and binds to loopback. It includes an integrated Tailscale Serve proxy (`tailscale: { mode: "serve" }`) that automatically exposes the gateway at `https://<tailscale-hostname>/` — no manual `tailscale serve` needed.

### 3. Git-Based Vault Sync

The vault is version-controlled with Git. A bare repository at `/srv/nazar/vault.git` serves as the central hub:

- **Laptop/Phone → VPS**: `git push` over SSH (via Tailscale)
- **VPS → Laptop/Phone**: `git pull` to get agent writes
- **Agent writes**: Auto-committed every 5 minutes by a cron job, pushed to bare repo
- **Post-receive hook**: When you push, the working copy at `/srv/nazar/vault/` updates automatically

```
Laptop/Phone ──git push/pull──> SSH (Tailscale) ──> /srv/nazar/vault.git (bare)
                                                         │
                                                    post-receive hook
                                                         │
                                                         ▼
                                              /srv/nazar/vault/ (working copy)
                                                         │
                                                    bind mount
                                                         │
                                                         ▼
                                              nazar-gateway container (/vault)
                                                         │
                                                    cron (5 min)
                                                         │
                                                  auto-commit + push
                                                         ▼
                                              /srv/nazar/vault.git (bare)
```

### 4. Tailscale

All services (SSH, gateway, vault git access) are only reachable via Tailscale's encrypted mesh VPN (`100.x.x.x` addresses). No public ports are needed — everything flows through SSH over Tailscale.

## Data Flow

### Voice Message → Daily Journal

```
Phone (WhatsApp)
    │ voice message
    ▼
OpenClaw Gateway (https://<tailscale-hostname>/)
    │
    ▼
Whisper STT (local, in container)
    │ transcribed text
    ▼
Obsidian skill (obsidian.py)
    │ append with timestamp
    ▼
/vault/01-daily-journey/2026/02-February/2026-02-11.md
    │
    ▼
Auto-commit cron (5 min) → git push → bare repo
    │
    ▼
git pull from laptop/phone gets the update
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
deploy/openclaw.json
    │ copied to VPS at build time
    ▼
/srv/nazar/data/openclaw/openclaw.json
    │ bind-mounted into container
    ▼
/home/node/.openclaw/openclaw.json (inside container)
    │
    ▼
OpenClaw reads config, starts gateway
    │ workspace mount
    ▼
/vault/99-system/openclaw/workspace/ (bind-mounted from host)
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
                                      └── git push/pull to vault.git
              HTTPS/443 ──► integrated tailscale serve ──► loopback ──► nazar-gateway (host network)
```

**Note:** The gateway container runs with `network_mode: host` and binds to loopback. Its integrated Tailscale Serve proxy (`tailscale: { mode: "serve" }`) handles HTTPS termination and exposes the gateway at `https://<tailscale-hostname>/`. Device pairing is auto-approved because connections are localhost.

## File Ownership

| Path | Owner | Why |
|------|-------|-----|
| `/srv/nazar/vault/` | `nazar:vault` (setgid) | Shared access: nazar (uid 1001) + container (uid 1000) via vault group |
| `/srv/nazar/vault.git/` | `nazar:vault` | Bare repo, shared group access |
| `/srv/nazar/data/` | `nazar:nazar` | Persistent container state |
| `/srv/nazar/.env` | `nazar:nazar` | Secrets (API keys, tokens), editable by nazar user |
| `/opt/openclaw/` | `root:root` | Source code for Docker build |

## Extension Points

| Want to... | Do this |
|------------|---------|
| Add a new skill | Create folder in `vault/99-system/openclaw/skills/` |
| Change agent personality | Edit `vault/99-system/openclaw/workspace/SOUL.md` |
| Add an LLM provider | Update `deploy/openclaw.json` models + `.env` |
| Add a new channel | Update `deploy/openclaw.json` channels section |
| Change vault structure | Rename folders, update `AGENTS.md` + `obsidian/SKILL.md` |
