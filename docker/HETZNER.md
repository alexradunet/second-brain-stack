# Hetzner VPS Deployment Guide

Complete guide for running Nazar Second Brain on Hetzner Cloud VPS using Docker.

## Overview

This guide deploys OpenClaw + Syncthing on a Hetzner VPS with:
- **Single user**: `debian` (admin) - no separate service user needed
- **Docker isolation**: All services run in containers
- **SSH tunnel access**: Secure access without exposing ports
- **Persistent state**: Vault and configs survive container restarts
- **~$5/month**: Hetzner CX11 (1 vCPU, 2GB RAM) or similar

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Hetzner VPS                                 │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Docker Engine                        │   │
│  │                                                         │   │
│  │  ┌──────────────┐      ┌──────────────┐                │   │
│  │  │   OpenClaw   │◄────►│  Syncthing   │                │   │
│  │  │   Gateway    │      │    Sync      │                │   │
│  │  │  Container   │      │  Container   │                │   │
│  │  └──────┬───────┘      └──────┬───────┘                │   │
│  │         │                     │                        │   │
│  │         └──────────┬──────────┘                        │   │
│  │                    │                                   │   │
│  │         ┌──────────┴──────────┐                        │   │
│  │         │   ~/nazar/vault     │                        │   │
│  │         │   (bind mount)      │                        │   │
│  │         └─────────────────────┘                        │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  SSH Access: ssh -L 18789:localhost:18789 debian@<vps-ip>      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │     Laptop      │
                    │  Obsidian +     │
                    │  Syncthing      │
                    └─────────────────┘
```

## Prerequisites

- Hetzner Cloud account
- SSH key added to Hetzner
- Local machine with SSH client

## Step 1: Provision VPS

1. **Create Server** in Hetzner Console:
   - **Location**: Closest to you (e.g., Nuremberg, Falkenstein)
   - **Image**: Ubuntu 22.04 or Debian 12
   - **Type**: CX11 (1 vCPU, 2GB RAM, ~€4.51/month)
   - **SSH Key**: Select your key
   - **Name**: `nazar` (or your preference)

2. **Wait for provisioning** (takes ~1 minute)

3. **Note the IP address** (e.g., `78.46.x.x`)

## Step 2: Initial Server Setup

Connect and run setup:

```bash
# SSH into the VPS
ssh root@YOUR_VPS_IP

# Create debian user (if not exists) and set up SSH
adduser debian
usermod -aG sudo debian
mkdir -p /home/debian/.ssh
cp /root/.ssh/authorized_keys /home/debian/.ssh/
chown -R debian:debian /home/debian/.ssh
chmod 700 /home/debian/.ssh
chmod 600 /home/debian/.ssh/authorized_keys

# Optional but recommended: Run security hardening
# This script implements OVHcloud security best practices
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh -o /tmp/setup-security.sh
sudo bash /tmp/setup-security.sh

# Switch to debian user
su - debian
```

## Step 3: Install Docker

```bash
# Update and install dependencies
sudo apt-get update
sudo apt-get install -y git curl ca-certificates

# Install Docker
curl -fsSL https://get.docker.com | sh

# Add debian user to docker group
sudo usermod -aG docker debian

# Verify (logout and login again for group change)
docker --version
docker compose version
```

**Logout and login again** for docker group to take effect:
```bash
exit
ssh debian@YOUR_VPS_IP
```

## Step 4: Deploy Nazar Second Brain

### Option A: Quick Deploy (Recommended)

```bash
# Download and run setup script
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash

# Or clone and run
git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar-repo
cd ~/nazar-repo/docker
bash setup.sh
```

### Option B: Manual Deploy

```bash
# Create directory structure
mkdir -p ~/nazar/docker
mkdir -p ~/nazar/vault
mkdir -p ~/nazar/.openclaw/workspace
mkdir -p ~/nazar/syncthing/config

# Download Docker files
cd ~/nazar/docker
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/Dockerfile.openclaw -o Dockerfile.openclaw
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/.env.example -o .env

# Create .env
cat > .env << 'EOF'
DEPLOYMENT_MODE=sshtunnel
VAULT_HOST_PATH=/home/debian/nazar/vault
OPENCLAW_CONFIG_PATH=/home/debian/nazar/.openclaw
OPENCLAW_WORKSPACE_PATH=/home/debian/nazar/.openclaw/workspace
SYNCTHING_CONFIG_PATH=/home/debian/nazar/syncthing/config
OPENCLAW_GATEWAY_BIND=127.0.0.1
OPENCLAW_GATEWAY_PORT=18789
CONTAINER_UID=1000
CONTAINER_GID=1000
EOF

# Generate token
TOKEN=$(openssl rand -hex 32)

# Create OpenClaw config
mkdir -p ~/nazar/.openclaw/workspace
cat > ~/nazar/.openclaw/openclaw.json << EOF
{
  "name": "nazar",
  "workspace": { "path": "/home/node/.openclaw/workspace" },
  "sandbox": { "mode": "non-main" },
  "gateway": {
    "enabled": true,
    "bind": "0.0.0.0",
    "port": 18789,
    "auth": { "type": "token", "token": "$TOKEN" }
  },
  "models": {},
  "channels": {},
  "tools": {
    "allowed": ["read_file", "write_file", "edit_file", "shell", "web_search", "task"],
    "sandbox": { "binds": ["/vault:/vault:rw"] }
  },
  "limits": { "maxConcurrentAgents": 4, "maxConcurrentSubagents": 8 }
}
EOF

# Fix permissions
chown -R 1000:1000 ~/nazar

# Build and start
docker compose up -d --build
```

## Step 5: Access Services

### Open SSH Tunnel (on your laptop)

```bash
# Single tunnel for OpenClaw
ssh -N -L 18789:localhost:18789 debian@YOUR_VPS_IP

# Single tunnel for Syncthing
ssh -N -L 8384:localhost:8384 debian@YOUR_VPS_IP

# Both services at once
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@YOUR_VPS_IP

# Background mode (add -f)
ssh -f -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@YOUR_VPS_IP
```

### Access Services

| Service | URL (with tunnel) |
|---------|-------------------|
| OpenClaw Gateway | http://localhost:18789 |
| Syncthing GUI | http://localhost:8384 |

### Get Gateway Token

```bash
# On VPS
cd ~/nazar/docker
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | grep token

# Or use CLI
./nazar-cli.sh token
```

## Step 6: Syncthing Setup

1. **Get VPS Device ID**:
   ```bash
   cd ~/nazar/docker
   docker compose exec syncthing syncthing cli show system | grep myID
   ```

2. **On your laptop**:
   - Install Syncthing
   - Add VPS as device (enter Device ID)
   - Share your vault folder

3. **Accept on VPS**:
   - Open Syncthing GUI (via tunnel)
   - Accept device request
   - Accept folder share
   - Set folder path to `/var/syncthing/vault`

## Step 7: Configure OpenClaw

```bash
# Run configuration wizard
cd ~/nazar/docker
docker compose exec -it openclaw openclaw configure

# Configure LLM providers, channels, etc.
```

## Management Commands

### Install CLI Helper

```bash
cd ~/nazar/docker
chmod +x nazar-cli.sh
sudo ln -s $(pwd)/nazar-cli.sh /usr/local/bin/nazar-cli

# Now you can use:
nazar-cli status
nazar-cli logs
nazar-cli restart
nazar-cli backup
nazar-cli tunnel  # Show SSH tunnel commands
```

### Docker Compose Directly

```bash
cd ~/nazar/docker

# Status
docker compose ps

# Logs
docker compose logs -f
docker compose logs -f openclaw

# Start/Stop/Restart
docker compose up -d
docker compose down
docker compose restart

# Update
docker compose pull
docker compose up -d --build
```

## What Persists Where

| Component | Location | Notes |
|-----------|----------|-------|
| Vault | `~/nazar/vault` | Synced via Syncthing |
| OpenClaw Config | `~/nazar/.openclaw/openclaw.json` | Gateway settings, tokens |
| Agent Workspace | `~/nazar/.openclaw/workspace/` | SOUL.md, skills, memory |
| Syncthing DB | `~/nazar/syncthing/config/` | Device connections, sync state |
| Container state | Docker volumes | Ephemeral, rebuilt on update |

## Security Hardening (Automated)

The setup includes an automated security hardening script based on OVHcloud's "How to secure a VPS" guide.

### Run Security Setup

```bash
# Download and run security hardening
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh | sudo bash
```

This script implements:

| Security Measure | Description |
|-----------------|-------------|
| **SSH Keys Only** | Disables password authentication |
| **Root Login Disabled** | Prevents direct root access |
| **UFW Firewall** | Blocks all incoming except SSH |
| **Fail2ban** | Blocks IPs after 3 failed login attempts |
| **Auto-updates** | Automatic security patches |
| **Docker Security** | Non-root container execution |

### Manual Security Steps

If you prefer manual configuration:

```bash
# 1. Disable Root Login
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 2. Enable UFW Firewall
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw --force enable

# 3. Install Fail2ban
sudo apt-get install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# 4. Enable Auto-updates
sudo apt-get install -y unattended-upgrades
```

### Security Audit

After setup, verify security:

```bash
# Run security audit
sudo nazar-security-audit

# Expected output:
# ✓ Root login disabled
# ✓ Password authentication disabled
# ✓ Firewall (UFW) active
# ✓ Fail2ban running
# ✓ Auto-updates enabled
```

## Backup Strategy

### Automated Backup Script

```bash
# Create backup script
cat > ~/nazar/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="$HOME/nazar/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

cd ~/nazar/docker
docker compose stop

tar -czf "$BACKUP_DIR/nazar-$TIMESTAMP.tar.gz" \
    -C ~/nazar \
    vault .openclaw syncthing

docker compose up -d

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/nazar-*.tar.gz | tail -n +8 | xargs -r rm

echo "Backup completed: $BACKUP_DIR/nazar-$TIMESTAMP.tar.gz"
EOF

chmod +x ~/nazar/backup.sh

# Add to crontab (daily at 3 AM)
(crontab -l 2>/dev/null; echo "0 3 * * * /home/debian/nazar/backup.sh") | crontab -
```

### Manual Backup

```bash
nazar-cli backup
# Creates: ~/nazar/backups/nazar-backup-YYYYMMDD_HHMMSS.tar.gz
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
cd ~/nazar/docker
docker compose logs

# Check disk space
df -h

# Fix permissions
chown -R 1000:1000 ~/nazar
```

### Can't Access Gateway

```bash
# Verify tunnel is active on laptop
ssh -N -L 18789:localhost:18789 debian@YOUR_VPS_IP

# Check OpenClaw logs
docker compose logs openclaw

# Verify token
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | grep token
```

### Syncthing Not Syncing

```bash
# Check device connections
docker compose exec syncthing syncthing cli show connections

# Check folder status
docker compose exec syncthing syncthing cli show folder status nazar-vault

# Restart Syncthing
docker compose restart syncthing
```

### Out of Memory

If using CX11 (2GB RAM) and hitting OOM:

```bash
# Add swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Or upgrade to CX21 (2 vCPU, 4GB RAM)
```

## Upgrading VPS

If you need more resources:

1. **Power off server** in Hetzner Console
2. **Resize** to larger type (e.g., CX21)
3. **Power on**
4. **Restart services**:
   ```bash
   cd ~/nazar/docker
   docker compose up -d
   ```

## Migration to New Server

1. **Backup on old server**:
   ```bash
   nazar-cli backup
   ```

2. **Download backup**:
   ```bash
   scp debian@old-vps:~/nazar/backups/nazar-backup-*.tar.gz .
   ```

3. **Setup new server** (follow this guide)

4. **Restore backup**:
   ```bash
   nazar-cli restore nazar-backup-*.tar.gz
   ```

## Cost Optimization

| Component | Monthly Cost |
|-----------|-------------|
| Hetzner CX11 | ~€4.51 |
| Hetzner CX21 | ~€8.21 |
| Tailscale (free tier) | Free |
| Total (CX11) | ~$5 USD |

## Resources

- [Hetzner Cloud Console](https://console.hetzner.cloud/)
- [OpenClaw Documentation](https://github.com/openclaw/openclaw)
- [Syncthing Documentation](https://docs.syncthing.net/)
- [Project Repository](https://github.com/alexradunet/easy-para-system-claw-vps)

---

*For issues or contributions, see the main project repository.*
