# Vault Structure

The Obsidian vault at `vault/` uses the **PARA method** (Projects, Areas, Resources, Archive) with numbered kebab-case folders.

## Folder Layout

```
vault/
├── 00-inbox/              Quick capture — new notes land here by default
├── 01-daily-journey/      Daily journal notes
│   └── YYYY/
│       └── MM-MonthName/
│           └── YYYY-MM-DD.md
├── 02-projects/           Active projects with clear goals and deadlines
├── 03-areas/              Life areas requiring ongoing attention
├── 04-resources/          Reference material and knowledge base
├── 05-arhive/             Completed or inactive items
├── 99-system/             System configuration (not user content)
│   ├── openclaw/          AI agent system
│   │   ├── workspace/     Agent personality + memory
│   │   ├── skills/        Agent capabilities
│   │   └── docs/          Agent-specific documentation
│   └── templates/         Obsidian note templates
└── .obsidian/             Obsidian app configuration
```

## PARA Method

| Folder | PARA Category | What Goes Here |
|--------|---------------|----------------|
| `02-projects/` | **Projects** | Tasks with a clear goal and deadline. Move to `05-arhive/` when done. |
| `03-areas/` | **Areas** | Ongoing responsibilities with no end date — health, finances, career. |
| `04-resources/` | **Resources** | Topics of interest, reference material, book notes, saved articles. |
| `05-arhive/` | **Archive** | Completed projects, inactive areas, outdated resources. |

`00-inbox/` and `01-daily-journey/` sit outside PARA as utility folders for capture and journaling.

## Naming Conventions

- **Folders**: kebab-case with numeric prefix (`01-daily-journey/`, not `01 Daily Journey/`)
- **Daily notes**: `YYYY-MM-DD.md` inside `01-daily-journey/YYYY/MM-MonthName/`
- **Templates**: descriptive names with underscores (`daily_note_template.md`)
- **No spaces in folder names**: Prevents quoting issues across shell scripts and cross-platform sync

## Folder Descriptions

### `00-inbox/`
The default capture location. Anything new goes here first. Process regularly — move notes to their permanent home or delete them.

### `01-daily-journey/`
Daily journal entries. Structured by year and month:
```
01-daily-journey/
└── 2026/
    └── 02-February/
        ├── 2026-02-10.md
        └── 2026-02-11.md
```

Voice messages are auto-transcribed and appended here with timestamps:
```markdown
---

**[14:32]**

Transcribed voice note content...
```

### `02-projects/`
Active projects with clear goals and deadlines. Each project gets its own note or subfolder. When a project is finished or paused, move it to `05-arhive/`.

### `03-areas/`
Life areas requiring ongoing attention — health, finances, career, relationships, personal development. These are living documents you tend continuously. Create subfolders per area.

### `04-resources/`
Reference material and knowledge base. Topics of interest, book notes, article summaries, how-to guides. Organize by topic in subfolders.

### `05-arhive/`
Completed or inactive items from other folders. Nothing gets deleted — it just moves here when it's no longer active.

### `99-system/`
System configuration — not user content. Contains:

- **`openclaw/workspace/`** — Agent personality (SOUL.md), behavior rules (AGENTS.md), user profile (USER.md), memory files
- **`openclaw/skills/`** — Agent capabilities (obsidian, voice, vps-setup)
- **`openclaw/docs/`** — Agent-specific documentation
- **`templates/`** — Obsidian note templates (daily, project, person, meeting, weekly review, etc.)

## Templates

Available in `99-system/templates/`:

| Template | Use Case | Suggested Hotkey |
|----------|----------|------------------|
| `daily_note_template.md` | Morning/evening journal entry | `Ctrl+D` |
| `project_template.md` | New project with roadmap | `Ctrl+P` |
| `person_template.md` | New contact/relationship | `Ctrl+Shift+P` |
| `meeting_template.md` | Meeting notes | `Ctrl+M` |
| `weekly_review_template.md` | Weekly reflection + planning | `Ctrl+W` |
| `inbox_quick_capture_template.md` | Quick thought capture | `Ctrl+I` |
| `habit_log_template.md` | Habit tracking entry | — |

### Obsidian Template Setup

1. Settings → Core Plugins → Templates → Enable
2. Settings → Templates → Template folder location → `99-system/templates`
3. Settings → Daily Notes → New file location → `01-daily-journey`
4. Settings → Daily Notes → Date format → `YYYY/MM-MMMM/YYYY-MM-DD`
5. Settings → Files & Links → Default location for new notes → `00-inbox`

## Obsidian Configuration

Key settings in `.obsidian/`:

| Setting | Value |
|---------|-------|
| New file location | `00-inbox/` |
| Daily note folder | `01-daily-journey/` |
| Daily note format | `YYYY/MM-MMMM/YYYY-MM-DD` |
| Attachment folder | `./attachments/` (relative to note) |
| Template folder | `99-system/templates/` |
