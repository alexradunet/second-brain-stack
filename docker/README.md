# Nazar Second Brain - Docker Setup

Docker-based deployment of OpenClaw + Syncthing with shared vault volume.

**Architecture**: Single `debian` user + Docker containers (no separate service user needed)

## Quick Start (OVHcloud VPS)

```bash
# On fresh Debian 13 VPS as debian user
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

See [VPS-GUIDE.md](VPS-GUIDE.md) for the full OVHcloud Debian 13 VPS deployment guide.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     VPS (Single debian user)                        │
│                                                                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │   OpenClaw   │◄──►│  Syncthing   │    │   SSH/       │          │
│  │   Gateway    │    │    Sync      │    │  Tailscale   │          │
│  │  Container   │    │  Container   │    │              │          │
│  └──────┬───────┘    └──────┬───────┘    └──────────────┘          │
│         └───────────────────┼───────────────────┘                   │
│                  ┌──────────┴──────────┐                            │
│                  │   ~/nazar/vault     │                            │
│                  │   (bind mount)      │                            │
│                  └─────────────────────┘                            │
└─────────────────────────────────────────────────────────────────────┘
         ▲                                      ▲
         │ SSH Tunnel                           │ Syncthing
         │ (localhost:18789)                    │ Protocol
         ▼                                      ▼
   ┌──────────┐                           ┌──────────┐
   │  Laptop  │◄─────────────────────────►│  Phone   │
   │ Obsidian │      Real-time Sync       │ Obsidian │
   └──────────┘                           └──────────┘
```

## Features

- **Single User**: No separate service user - Docker provides isolation
- **SSH Tunnel Access**: Secure access without exposing ports
- **Optional Tailscale**: Multi-device VPN (alternative to SSH tunnel)
- **Persistent State**: Vault and configs survive container restarts
- **Shared Volume**: OpenClaw and Syncthing share vault via bind mount
- **Simple Management**: `nazar-cli` helper for common operations

## Directory Structure

```
~/nazar/
├── docker/
│   ├── docker-compose.yml      # Main compose file
│   ├── Dockerfile.openclaw     # OpenClaw container build
│   ├── .env                    # Environment configuration
│   ├── setup.sh                # Setup script
│   ├── setup-security.sh       # Security hardening script
│   ├── nazar-cli.sh            # Management CLI
│   ├── README.md               # This file
│   ├── VPS-GUIDE.md            # VPS deployment guide
│   ├── SECURITY.md             # Security guide
│   └── MIGRATION.md            # Migration guide
│
├── vault/                      # Shared vault (Syncthing sync target)
│   ├── 00-inbox/
│   ├── 01-daily-journey/
│   ├── 02-projects/
│   ├── 03-areas/
│   ├── 04-resources/
│   ├── 05-archive/
│   └── 99-system/
│
├── .openclaw/                  # OpenClaw configuration
│   ├── openclaw.json          # Gateway config
│   └── workspace/             # Agent workspace (SOUL.md, skills)
│
├── syncthing/
│   └── config/                # Syncthing database & config
│
└── backups/                   # Automated backups
```

## Deployment Modes

### 1. SSH Tunnel (Default, Recommended for Single User)

Access services via SSH tunnel - no public ports exposed.

```bash
# On laptop
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@vps-ip

# Then open:
# - OpenClaw: http://localhost:18789
# - Syncthing: http://localhost:8384
```

**Pros**: Most secure, simplest, works behind any firewall  
**Cons**: Requires active SSH connection

### 2. Tailscale (For Multi-Device Access)

Use Tailscale VPN for mesh networking between all devices.

```bash
# During setup, choose Tailscale mode
# Enter your auth key from https://login.tailscale.com/admin/settings/keys
```

**Pros**: Always-on, multiple devices, no SSH needed  
**Cons**: Requires Tailscale account, slightly more complex

## Configuration

### Environment Variables (.env)

```bash
# Deployment mode: "sshtunnel" or "tailscale"
DEPLOYMENT_MODE=sshtunnel

# Host Paths
VAULT_HOST_PATH=/home/debian/nazar/vault
OPENCLAW_CONFIG_PATH=/home/debian/nazar/.openclaw
OPENCLAW_WORKSPACE_PATH=/home/debian/nazar/.openclaw/workspace
SYNCTHING_CONFIG_PATH=/home/debian/nazar/syncthing/config

# Gateway configuration
OPENCLAW_GATEWAY_BIND=127.0.0.1  # Use 0.0.0.0 for Tailscale
OPENCLAW_GATEWAY_PORT=18789

# Tailscale (if using)
TAILSCALE_HOSTNAME=nazar
TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxx

# Container user (should match debian user UID)
CONTAINER_UID=1000
CONTAINER_GID=1000
```

### OpenClaw Configuration

Created automatically at `~/nazar/.openclaw/openclaw.json`:

```json
{
  "name": "nazar",
  "workspace": {
    "path": "/home/node/.openclaw/workspace"
  },
  "gateway": {
    "enabled": true,
    "bind": "0.0.0.0",
    "port": 18789,
    "auth": {
      "type": "token",
      "token": "<auto-generated>"
    }
  },
  "tools": {
    "sandbox": {
      "binds": ["/vault:/vault:rw"]
    }
  }
}
```

## Management Commands

### Using nazar-cli

```bash
# Install
sudo ln -s ~/nazar/docker/nazar-cli.sh /usr/local/bin/nazar-cli

# Common commands
nazar-cli status      # Show service status
nazar-cli logs        # Show all logs
nazar-cli logs openclaw  # Show OpenClaw logs only
nazar-cli restart     # Restart services
nazar-cli backup      # Create backup
nazar-cli restore     # Restore from backup
nazar-cli token       # Show gateway token
nazar-cli tunnel      # Show SSH tunnel command
```

### Using docker compose directly

```bash
cd ~/nazar/docker

# Start
docker compose up -d

# View logs
docker compose logs -f
docker compose logs -f openclaw

# Stop
docker compose down

# Restart
docker compose restart

# Update
docker compose pull
docker compose up -d --build

# Execute commands
docker compose exec openclaw openclaw configure
docker compose exec syncthing syncthing cli show system
```

## Post-Infrastructure Setup

Once containers are running, configure the services through their own UIs:

1. **Syncthing** — Open the Syncthing GUI (via SSH tunnel at `http://localhost:8384`), add your devices, and share the vault folder
2. **OpenClaw** — Run the onboarding wizard: `docker compose exec -it openclaw openclaw configure`

## Backup and Restore

### Automated Backup

```bash
nazar-cli backup
# Creates: ~/nazar/backups/nazar-backup-YYYYMMDD_HHMMSS.tar.gz
```

Add to crontab for daily backups:
```bash
0 3 * * * /usr/local/bin/nazar-cli backup
```

### Manual Backup

```bash
cd ~/nazar/docker
docker compose down

tar -czf nazar-backup.tar.gz ~/nazar/vault ~/nazar/.openclaw ~/nazar/syncthing

docker compose up -d
```

### Restore

```bash
nazar-cli restore nazar-backup-20250211_120000.tar.gz
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker compose logs

# Check disk space
df -h

# Check permissions
ls -la ~/nazar/

# Fix permissions
chown -R 1000:1000 ~/nazar
```

## Updates

```bash
# Update images and restart
cd ~/nazar/docker
docker compose pull
docker compose up -d --build

# Clean old images
docker image prune -f
```

## Uninstall

```bash
cd ~/nazar/docker

# Stop and remove containers
docker compose down -v

# Remove images
docker rmi nazar-openclaw syncthing/syncthing

# Remove data (optional)
rm -rf ~/nazar
```

## Security

Security hardening is available based on OVHcloud's "How to secure a VPS" guide.

```bash
# Run automated security hardening
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh | sudo bash

# Or during main setup, answer "yes" when prompted

# Run security audit anytime
sudo nazar-security-audit
```

Security features:
- SSH key authentication only (passwords disabled)
- UFW firewall (blocks all incoming except SSH)
- Fail2ban (blocks IPs after failed login attempts)
- Automatic security updates
- Docker container isolation

See [SECURITY.md](SECURITY.md) for detailed security information.

## Documentation

| Document | Description |
|----------|-------------|
| [VPS-GUIDE.md](VPS-GUIDE.md) | OVHcloud Debian 13 VPS deployment guide |
| [SECURITY.md](SECURITY.md) | Security hardening and best practices |
| [MIGRATION.md](MIGRATION.md) | Migration from systemd setup |

---

*For issues or contributions, see the main project repository.*
