# OpenClaw Configuration

OpenClaw is the AI framework that powers the Nazar agent.

## Configuration Location

| File | Purpose |
|------|---------|
| `~/nazar/.openclaw/openclaw.json` | Main configuration |
| `~/nazar/.openclaw/devices/paired.json` | Approved devices |
| `~/nazar/.openclaw/devices/pending.json` | Pending device approvals |
| `~/nazar/.openclaw/workspace/` | Agent workspace (SOUL.md, skills, memory) |

## Initial Configuration

After installation, run the setup wizard:

```bash
# Using CLI
nazar-cli configure

# Or directly
cd ~/nazar/docker
docker compose exec -it openclaw openclaw configure
```

This interactive wizard will guide you through:
1. **Model selection** (Claude, GPT-4, etc.)
2. **API key entry** (encrypted storage)
3. **Channel setup** (WhatsApp, Telegram, Web)

## Manual Configuration

### openclaw.json Structure

```json
{
  "name": "nazar",
  "workspace": {
    "path": "/home/node/.openclaw/workspace"
  },
  "sandbox": {
    "mode": "non-main"
  },
  "gateway": {
    "enabled": true,
    "bind": "0.0.0.0",
    "port": 18789,
    "auth": {
      "type": "token",
      "token": "your-secure-token-here"
    }
  },
  "models": {},
  "channels": {},
  "tools": {
    "allowed": [
      "read_file",
      "write_file",
      "edit_file",
      "shell",
      "web_search",
      "task"
    ],
    "sandbox": {
      "binds": [
        "/vault:/vault:rw"
      ]
    }
  },
  "limits": {
    "maxConcurrentAgents": 4,
    "maxConcurrentSubagents": 8
  }
}
```

### Key Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `name` | Agent name | `nazar` |
| `workspace.path` | Agent workspace path | `/home/node/.openclaw/workspace` |
| `sandbox.mode` | Sandbox mode: `off`, `non-main`, `all` | `non-main` |
| `gateway.bind` | Bind address | `0.0.0.0` (in container) |
| `gateway.port` | Gateway port | `18789` |
| `gateway.auth.token` | Access token | Auto-generated |

### Sandbox Modes

- `off`: No sandboxing
- `non-main`: Sandbox non-main sessions (group chats)
- `all`: Sandbox all sessions

## Device Pairing

New devices must be approved before accessing the Control UI.

### List Pending Devices

```bash
docker compose exec openclaw openclaw devices list
```

### Approve a Device

```bash
docker compose exec openclaw openclaw devices approve <request-id>
```

## Gateway Access

### Via SSH Tunnel (Recommended)

```bash
# On laptop
ssh -N -L 18789:localhost:18789 debian@vps-ip

# Then open: http://localhost:18789
```

### Via Tailscale

If using Tailscale mode, access via:
```
https://nazar/
```

## API Keys

API keys are stored encrypted in the OpenClaw configuration. Set them via:

```bash
# Interactive configuration
docker compose exec -it openclaw openclaw configure

# Or set environment variable in .env
echo "ANTHROPIC_API_KEY=sk-ant-..." >> ~/nazar/docker/.env
docker compose restart openclaw
```

## Troubleshooting

### Gateway Won't Start

```bash
# Check config validity
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | jq .

# Check logs
docker compose logs -f openclaw

# Verify token
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | grep token
```

### Can't Access Gateway

```bash
# Check if container is running
docker compose ps

# Verify port binding
docker compose exec openclaw netstat -tlnp

# Test health
docker compose exec openclaw openclaw health
```

### Regenerate Token

```bash
# Generate new token
TOKEN=$(openssl rand -hex 32)
docker compose exec openclaw \
    sed -i "s/\"token\": \"[^\"]*\"/\"token\": \"$TOKEN\"/" \
    /home/node/.openclaw/openclaw.json
docker compose restart openclaw
echo "New token: $TOKEN"
```

## Advanced Configuration

### Custom Workspace Path

The workspace path in the container is fixed at `/home/node/.openclaw/workspace`, but you can change the host path in `docker-compose.yml`:

```yaml
volumes:
  - /custom/path:/home/node/.openclaw/workspace:rw
```

### Environment Variables

Set in `~/nazar/docker/.env`:

```bash
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

### Custom Tools

Add custom tool bindings in `openclaw.json`:

```json
{
  "tools": {
    "sandbox": {
      "binds": [
        "/vault:/vault:rw",
        "/custom/path:/custom:ro"
      ]
    }
  }
}
```

Restart after changes:
```bash
docker compose restart openclaw
```
