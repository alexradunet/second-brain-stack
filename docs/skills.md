# Skills Reference

Skills are self-contained modules that extend Nazar's capabilities. Each skill lives in `vault/99-system/openclaw/skills/<name>/` with a `SKILL.md`, optional Python code, and optional CLI scripts.

## Available Skills

### Obsidian (`obsidian/`)

Vault operations: read/write notes, manage daily journal, work with templates.

**Python API** (`obsidian.py`):
```python
from obsidian import (
    get_vault_config,       # Load .obsidian/ config
    get_daily_note_path,    # Path for today's note
    create_daily_note,      # Create/overwrite daily note
    append_to_daily_note,   # Append with timestamp
    create_note,            # Create note in any folder
    read_note,              # Read a note
    note_exists,            # Check if note exists
    list_daily_notes,       # List daily notes by year/month
    get_attachment_path,    # Get attachment path
)
```

**CLI** (`scripts/obsidian-cli.py`):
```bash
obsidian-cli.py config                    # Show vault config
obsidian-cli.py daily-path                # Today's note path
obsidian-cli.py create-daily -c "content" # Create daily note
obsidian-cli.py append -c "entry"         # Append to daily note
obsidian-cli.py create "Title" -c "body"  # New note in 00-inbox
obsidian-cli.py read "path/to/note.md"    # Read a note
obsidian-cli.py list-daily --year 2026    # List daily notes
```

**Environment variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_PATH` | `/home/nazar/vault` | Path to Obsidian vault root |

---

### Voice (`voice/`)

Local speech-to-text (Whisper) and text-to-speech (Piper) with daily journal integration.

**Python API** (`voice.py`):
```python
from voice import (
    transcribe_audio,           # Audio → text
    transcribe_with_timestamp,  # Audio → (timestamp, text)
    transcribe_and_save,        # Audio → transcribe → daily note
    generate_speech,            # Text → WAV
    speak,                      # Quick TTS
    convert_to_opus,            # WAV → OGG/Opus (WhatsApp)
)
```

**CLI** (`scripts/voice-cli.py`):
```bash
voice-cli.py transcribe audio.ogg              # Transcribe
voice-cli.py transcribe audio.ogg --save       # Transcribe + save to daily note
voice-cli.py speak "Hello world"               # Generate speech
voice-cli.py speak "text" --opus               # Speech → Opus for WhatsApp
voice-cli.py daily-note audio.ogg              # Full pipeline
```

**Standalone transcription** (`scripts/transcribe.py`):
```bash
transcribe.py audio.ogg small    # Transcribe with timestamps
```

**Environment variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_PATH` | `/home/nazar/vault` | Obsidian vault root |
| `VOICE_VENV` | `/home/nazar/.local/venv-voice` | Python venv with Whisper/Piper |
| `WHISPER_MODEL_DIR` | `/home/nazar/.local/share/whisper` | Whisper model cache |
| `PIPER_MODEL_DIR` | `/home/nazar/.local/share/piper` | Piper voice models |

---

### VPS Setup (`vps-setup/`)

Automated provisioning and security hardening for a Debian VPS.

**Scripts:**
| Script | Purpose |
|--------|---------|
| `provision-vps.sh` | Master script — runs all phases end-to-end |
| `secure-vps.sh` | User creation, SSH hardening, firewall, fail2ban, auto-updates |
| `install-tailscale.sh` | Install + authenticate Tailscale |
| `lock-ssh-to-tailscale.sh` | Remove public SSH, Tailscale-only access |
| `install-node.sh` | Install Node.js 22 for OpenClaw |
| `audit-vps.sh` | Security + health audit (read-only) |

**Usage:**
```bash
# Full provisioning (one command)
sudo bash bootstrap/bootstrap.sh

# Or step by step
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/secure-vps.sh
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/install-tailscale.sh
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/lock-ssh-to-tailscale.sh
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/install-node.sh
sudo bash vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

No environment variables — all paths are detected or hardcoded to standard locations.

---

## Creating a New Skill

### File Structure

```
vault/99-system/openclaw/skills/my-skill/
├── SKILL.md              # Required: documentation + metadata
├── my_skill.py           # Optional: Python module
└── scripts/              # Optional: CLI tools
    └── my-cli.py
```

### SKILL.md Template

```markdown
---
name: my-skill
description: One-line description of what this skill does.
---

# My Skill

## Purpose
What it does and when to use it.

## Usage
Code examples, CLI commands.

## Requirements
Dependencies, env vars.
```

### Rules

1. **Use environment variables for paths** — `os.environ.get("VAULT_PATH", "/vault")`
2. **Never hardcode** `/home/debian/` or any absolute user path
3. **Use relative imports** for sibling skills — `sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))`
4. **Keep it self-contained** — each skill should work independently
5. **Document everything** — SKILL.md is what the agent reads to use your skill
