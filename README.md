# Second Brain — AI-Assisted Personal Knowledge Management

An AI-assisted personal knowledge management system built on Obsidian, powered by an AI agent (Nazar) running on OpenClaw, synchronized across devices via Git, and hosted on a hardened Debian VPS behind Tailscale.

---

## 🚀 Quick Start (AI-Assisted VPS Setup)

The fastest way to get started is using **Claude Code** or **Kimi Code** directly on your VPS for an interactive, guided setup:

```bash
# 1. Buy a VPS (Hetzner, OVH, DigitalOcean - Debian 13 or Ubuntu 22.04+)
# 2. SSH into your fresh VPS
ssh root@<your-vps-ip>

# 3. Run the bootstrap script
curl -fsSL https://raw.githubusercontent.com/alexradunet/second-brain-stack/main/bootstrap/bootstrap.sh | bash

# 4. Follow the instructions to launch your AI assistant
#    The AI will guide you through the complete setup interactively!
```

**Or manually:**

```bash
# Install Node.js and an AI assistant
apt update && apt install -y nodejs npm
curl -fsSL https://claude.ai/install.sh | sh  # or install Kimi Code

# Clone this repo
cd ~ && mkdir -p nazar_deploy && cd nazar_deploy
git clone https://github.com/alexradunet/second-brain-stack.git .

# Launch the AI assistant and ask for guidance
claude
# Then type: "I'm a new user. Please guide me through setting up this VPS."
```

📖 **[Complete Bootstrap Guide →](docs/bootstrap-guide.md)**  
🤖 **[AI Assistant Instructions →](bootstrap/AI_BOOTSTRAP.md)**

---

## What Is This?

Three integrated layers working together:

1. **Content Layer** (`vault/`) — An Obsidian vault organized with the PARA method (Projects, Areas, Resources, Archive)
2. **Intelligence Layer** (OpenClaw Gateway) — The Nazar AI agent that processes voice messages, manages daily journals, and answers questions about your notes
3. **Infrastructure Layer** (`deploy/`) — Docker containers running on a hardened VPS with Git-based vault synchronization

```
second-brain/
├── vault/                ← Obsidian vault (PARA structure + agent config)
│   ├── 00-inbox/         ← Quick capture
│   ├── 01-daily-journey/ ← Daily notes (YYYY/MM-MMMM/YYYY-MM-DD.md)
│   ├── 02-projects/      ← Active projects with goals/deadlines
│   ├── 03-areas/         ← Life areas requiring ongoing attention
│   ├── 04-resources/     ← Reference material
│   ├── 05-arhive/        ← Completed/inactive items
│   └── 99-system/        ← Agent workspace, skills, templates
├── deploy/               ← Docker stack for VPS deployment
│   ├── docker-compose.yml
│   ├── Dockerfile.nazar
│   └── scripts/          ← VPS setup scripts
├── bootstrap/            ← AI-assisted setup files
│   ├── bootstrap.sh      ← One-liner bootstrap script
│   └── AI_BOOTSTRAP.md   ← Instructions for AI assistants
└── docs/                 ← Project documentation
```

---

## Key Features

| Feature                  | Description                                            |
| ------------------------ | ------------------------------------------------------ |
| **🔒 Secure by Default** | Tailscale VPN + hardened SSH + no public ports         |
| **🎙️ Voice Processing**  | Whisper STT + Piper TTS for voice notes                |
| **📱 Multi-Device Sync** | Git-based sync across laptop, phone, tablet            |
| **🤖 AI Agent**          | Nazar manages your daily journal and answers questions |
| **📓 PARA Method**       | Organized by Projects, Areas, Resources, Archive       |
| **🐳 Containerized**     | Single Docker container, easy to deploy                |

---

## Documentation

| Document                                       | Description                                   |
| ---------------------------------------------- | --------------------------------------------- |
| **[Bootstrap Guide](docs/bootstrap-guide.md)** | 🌟 AI-assisted VPS setup walkthrough          |
| **[VPS Cheatsheet](docs/vps-setup-cheatsheet.md)** | Quick reference for VPS management        |
| **[Architecture](docs/architecture.md)**       | System design, components, data flow          |
| **[Vault Structure](docs/vault-structure.md)** | PARA vault layout and conventions             |
| **[Agent System](docs/agent.md)**              | Nazar agent — workspace, personality, memory  |
| **[Skills Reference](docs/skills.md)**         | Available skills (obsidian, voice, vps-setup) |
| **[Deployment Guide](docs/deployment.md)**     | Traditional scripted deployment               |
| **[Security Model](docs/security.md)**         | Hardening, Tailscale, secrets management      |
| **[Git Sync](docs/git-sync.md)**               | Multi-device vault synchronization            |
| **[Troubleshooting](docs/troubleshooting.md)** | Common issues and fixes                       |

---

## Usage Patterns

### Daily Capture (Voice)

1. Send a voice message to your agent (WhatsApp, Telegram, etc.)
2. Nazar transcribes it with Whisper
3. Text is appended to today's daily note with timestamp
4. Auto-syncs to all your devices

### Daily Journal

1. Open Obsidian on any device
2. Navigate to `01-daily-journey/YYYY/MM-MMMM/YYYY-MM-DD.md`
3. Write or review your day's notes
4. Git sync happens automatically every 5 minutes

### Knowledge Queries

Ask Nazar about anything in your vault:

- "What did I decide about X last month?"
- "Summarize my notes from the project meeting"
- "What are my active projects with deadlines this week?"

---

## Technology Stack

| Component            | Technology                             |
| -------------------- | -------------------------------------- |
| **Gateway**          | Node.js 22 (OpenClaw framework)        |
| **Voice Processing** | Python 3 + Whisper (STT) + Piper (TTS) |
| **Containerization** | Docker + Docker Compose                |
| **Sync**             | Git over SSH                           |
| **Networking**       | Tailscale (WireGuard VPN)              |
| **OS**               | Debian 13                              |
| **PKM App**          | Obsidian                               |

---

## Security Model

Defense-in-depth with 6 layers:

1. **Network:** Tailscale VPN + UFW firewall — zero public ports
2. **Authentication:** SSH keys + gateway tokens — no passwords
3. **Container:** Docker isolation — agent only sees `/vault`
4. **Agent Sandbox:** Group chats run in sandboxed Docker containers
5. **Secrets:** API keys in `.env`, never in vault
6. **Auto-Patching:** Unattended security upgrades daily

---

## Contributing

This is a personal knowledge management system — fork it and make it yours:

1. Fork the repository
2. Customize `vault/99-system/openclaw/workspace/SOUL.md` for your agent's personality
3. Fill in `vault/99-system/openclaw/workspace/USER.md` with your details
4. Deploy to your own VPS
5. Share improvements via pull requests

---

## License

MIT License — feel free to use, modify, and share.

---

_Built with Obsidian, OpenClaw, and a lot of voice notes._
