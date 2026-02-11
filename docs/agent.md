# Agent System — Nazar

Nazar is an AI agent that lives inside your Obsidian vault. It processes voice messages, manages your daily journal, answers questions about your notes, and proactively checks on things during heartbeats.

## How It Works

Nazar runs on OpenClaw, an open-source agent gateway. OpenClaw receives messages from WhatsApp/Telegram/web, routes them to Nazar, and Nazar reads/writes files in your vault to respond.

The agent's "brain" lives at `vault/99-system/openclaw/workspace/`. When OpenClaw starts a session, Nazar reads these files to know who it is, who you are, and how to behave.

## Workspace Files

All at `vault/99-system/openclaw/workspace/`:

### `SOUL.md` — Personality

Defines who Nazar is: values, tone, boundaries. Key principles:

- Be genuinely helpful, not performatively helpful
- Have opinions — don't be a bland search engine
- Be resourceful before asking questions
- Earn trust through competence
- Remember you're a guest in someone's life

Edit this to change how Nazar behaves.

### `AGENTS.md` — Behavior Rules

Operational guidelines:

- **Session startup**: Read SOUL.md → USER.md → recent memory files
- **Memory system**: Daily logs in `memory/YYYY-MM-DD.md`, curated long-term memory in `MEMORY.md`
- **Safety rules**: Never exfiltrate data, ask before external actions, trash over rm
- **Group chat etiquette**: When to speak, when to stay silent, how to use reactions
- **Heartbeat behavior**: What to check proactively, when to reach out vs stay quiet
- **Vault structure reference**: Lists all vault folders with descriptions

### `USER.md` — Your Profile

What Nazar knows about you: name, timezone, preferences, projects, personality. Nazar fills this in during the first conversation and updates it over time.

### `IDENTITY.md` — Agent Identity

Nazar's self-concept: chosen name, creature type, vibe, emoji, avatar. Filled in during the bootstrap conversation.

### `BOOTSTRAP.md` — First Run

Instructions for Nazar's first conversation. Guides the initial "who am I, who are you" exchange. Deleted after first run.

### `TOOLS.md` — Environment Notes

Agent's personal cheat sheet for environment-specific details: camera names, SSH hosts, preferred TTS voices, device nicknames.

### `HEARTBEAT.md` — Periodic Tasks

Checklist for heartbeat polls. Nazar checks this periodically and acts on any tasks listed. Keep it small to limit token usage.

### `MEMORY.md` — Long-Term Memory

Created as needed. Curated memories distilled from daily logs. Only loaded in direct (main) sessions — never in group chats for security.

## Memory Model

Nazar wakes up fresh each session. Continuity comes from files:

```
Conversation happens
    │
    ▼
Nazar writes to memory/2026-02-11.md (raw daily log)
    │
    ▼
During heartbeats, Nazar reviews recent daily logs
    │
    ▼
Distills important things into MEMORY.md (curated)
    │
    ▼
Next session, reads MEMORY.md + recent daily logs
```

**Daily logs** (`memory/YYYY-MM-DD.md`) — raw, everything that happened
**MEMORY.md** — curated wisdom, updated periodically, like a human's long-term memory

## Skills

Skills are self-contained modules that give Nazar capabilities. Each skill has a `SKILL.md` that documents its API and usage.

Located at `vault/99-system/openclaw/skills/`:

### Obsidian Skill (`obsidian/`)
- Read/write vault notes
- Create daily notes with correct path format
- Append timestamped entries to daily journal
- Create notes in any folder
- Read Obsidian configuration

### Voice Skill (`voice/`)
- Transcribe audio → text (Whisper STT, local)
- Generate speech (Piper TTS, local)
- Full pipeline: voice message → transcription → daily note with timestamp
- Convert WAV → Opus for WhatsApp voice replies

### VPS Setup Skill (`vps-setup/`)
- Guide for provisioning a Debian VPS
- Automated scripts for security hardening, Tailscale, service setup
- Security audit script

## Configuration

Agent configuration lives in `deploy/openclaw.json` and `openclaw configure`:

- **Models**: Configured via `openclaw configure` (not hardcoded)
- **Channels**: Configured via `openclaw configure` (WhatsApp, etc.)
- **Sandbox**: `non-main` mode — group/channel sessions are sandboxed, direct chats have full access
- **Gateway**: Token auth on port 18789
- **Compaction**: `safeguard` mode for context management

## Creating a New Skill

1. Create `vault/99-system/openclaw/skills/your-skill/`
2. Write `SKILL.md` with frontmatter (`name`, `description`) and usage docs
3. Optionally add Python modules and CLI scripts
4. Use `os.environ.get("VAULT_PATH", "/vault")` for paths — never hardcode
5. Import the obsidian skill for vault operations

See `vault/99-system/openclaw/docs/skills.md` for details.
