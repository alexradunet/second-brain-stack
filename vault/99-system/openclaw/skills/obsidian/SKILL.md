---
name: obsidian
description: Work with Obsidian vault structure, daily notes, templates, and vault configuration. Understands the vault's folder structure, daily note patterns, and core settings.
---

# Obsidian Vault Skill

Understanding and working with your Obsidian vault structure.

## Vault Overview

**Vault Location:** `/vault/` (configurable via `VAULT_PATH` env var)

**Structure (PARA method):**
```
📁 00-inbox/              - Quick capture (new file default location)
📁 01-daily-journey/      - Daily notes (YYYY/MM-MMMM/YYYY-MM-DD.md)
📁 02-projects/           - Active projects with clear goals and deadlines
📁 03-areas/              - Life areas requiring ongoing attention
📁 04-resources/          - Reference material and knowledge base
📁 05-archive/             - Completed or inactive items
📁 99-system/             - Agent workspace, skills, templates, docs
📁 .obsidian/             - Obsidian configuration
```

## Key Configuration

### Daily Notes
- **Folder:** `01-daily-journey/`
- **Format:** `YYYY/MM-MMMM/YYYY-MM-DD.md`
- **Example:** `01-daily-journey/2026/02-February/2026-02-10.md`

### New Files
- **Default Location:** `00-inbox/`
- **Attachments:** `./attachments/` (relative to note)

### Core Plugins Enabled
- Daily Notes ✅
- Templates ✅
- Properties (YAML frontmatter) ✅
- Graph View ✅
- Backlinks ✅
- Sync ✅

## Usage

### Create Daily Note

```python
from obsidian import create_daily_note, get_daily_note_path

# Get path for today
path = get_daily_note_path()  # Returns: 01-daily-journey/2026/02-February/2026-02-10.md

# Create with template
create_daily_note(content="# My Day\n\nStarted strong...")
```

### Append to Today's Note

```python
from obsidian import append_to_daily_note

append_to_daily_note("## Evening\n\nHad dinner with friends.")
```

### Create New Note

```python
from obsidian import create_note

# Goes to 00-inbox/ by default
create_note("Project Idea", "# Idea\n\nThis is a new project...")

# Or specify folder
create_note("Project Idea", "# Idea...", folder="02-projects/")
```

### Read Vault Config

```python
from obsidian import get_vault_config

config = get_vault_config()
print(config['daily_notes']['folder'])  # 01-daily-journey/
```

## File Operations

All operations respect the vault structure:
- Daily notes auto-create folders (YYYY/MM-MMMM/)
- New files default to 00-inbox/
- Attachments use relative ./attachments/ path
- YAML frontmatter preserved
