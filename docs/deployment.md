# Deployment Guide

How to go from a fresh Debian 13 VPS to a running Nazar instance.

## What Gets Deployed

Direct execution services on the VPS (no Docker):

1. **OpenClaw Gateway** — AI agent gateway (systemd user service)
2. **Syncthing** — Real-time vault synchronization (systemd user service)

Both run under the `nazar` user with restricted permissions.

## Prerequisites

- A Debian 13 VPS (OVH, Hetzner, or similar)
- Root SSH access (initial setup)
- A Tailscale account ([login.tailscale.com](https://login.tailscale.com))

## Quick Deploy (Recommended)

### One-Line Bootstrap

```bash
# On VPS as root
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash
```

Then follow the on-screen instructions.

### Manual Steps After Bootstrap

1. **Start Tailscale:**
   ```bash
   sudo tailscale up
   ```

2. **Clone repository as debian user:**
   ```bash
   su - debian
   git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar
   cd ~/nazar
   ```

3. **Deploy vault:**
   ```bash
   sudo cp -r vault/* /home/nazar/vault/
   sudo chown -R nazar:nazar /home/nazar/vault
   ```

4. **Start Syncthing:**
   ```bash
   sudo bash ~/nazar/nazar/scripts/setup-syncthing.sh
   ```

5. **Start OpenClaw:**
   ```bash
   sudo bash ~/nazar/nazar/scripts/setup-openclaw.sh
   sudo -u nazar openclaw configure
   ```

## Step-by-Step Deploy

### 1. Secure the VPS

The bootstrap script handles this, but if doing manually:

```bash
# Create users
useradd -m -s /bin/bash -G sudo debian
useradd -m -s /bin/bash nazar
passwd -l nazar  # Lock service user

# SSH hardening
cat > /etc/ssh/sshd_config.d/nazar.conf << 'EOF'
PermitRootLogin no
PasswordAuthentication no
AllowUsers debian
EOF
systemctl restart sshd

# Firewall
ufw default deny incoming
ufw allow 22/tcp comment 'SSH'
ufw --force enable

# Fail2Ban
systemctl enable fail2ban
systemctl start fail2ban
```

### 2. Install Software

```bash
# Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# OpenClaw
npm install -g openclaw@latest

# Syncthing
curl -s https://syncthing.net/release-key.txt | gpg --dearmor > /usr/share/keyrings/syncthing-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" > /etc/apt/sources.list.d/syncthing.list
apt-get update
apt-get install -y syncthing

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
```

### 3. Configure Services

See `nazar/scripts/setup-openclaw.sh` and `nazar/scripts/setup-syncthing.sh` for service configuration.

## Directory Layout on VPS

```
/home/nazar/                 <- Service user home
├── vault/                   <- Obsidian vault (mode 700)
│   ├── 00-inbox/
│   ├── 01-daily-journey/
│   ├── ...
│   └── 99-system/
│       └── openclaw/
│           ├── workspace/   <- Agent personality
│           └── skills/      <- Agent capabilities
├── .openclaw/               <- OpenClaw config (mode 700)
│   ├── openclaw.json       <- Main config
│   └── devices/            <- Paired devices
└── .local/
    ├── state/syncthing/    <- Syncthing data
    └── venv-voice/         <- Python voice tools

/home/debian/                <- Admin user home
├── bin/                     <- Helper scripts
│   ├── nazar-status
│   ├── nazar-logs
│   ├── nazar-restart
│   ├── nazar-audit
│   └── nazar-backup
└── nazar/                   <- Repository clone
```

## Services

### OpenClaw Gateway

- **Type:** systemd user service
- **User:** nazar
- **Bind:** 127.0.0.1:18789
- **Expose:** Via Tailscale Serve
- **URL:** `https://<tailscale-hostname>/`

### Syncthing

- **Type:** systemd user service
- **User:** nazar
- **Bind:** 0.0.0.0:8384 (or Tailscale interface)
- **URL:** `http://<tailscale-ip>:8384`

## Ports

| Port | Service | Binding | Access |
|------|---------|---------|--------|
| 22/tcp | SSH | tailscale0 only | `ssh debian@<tailscale-ip>` |
| 8384/tcp | Syncthing GUI | tailscale0 only | `http://<tailscale-ip>:8384` |
| 443 (HTTPS) | OpenClaw | loopback → Tailscale Serve | `https://<tailscale-hostname>/` |

No public ports exposed.

## Management Commands

### Service Management

```bash
# Status
sudo -u nazar systemctl --user status openclaw
sudo -u nazar systemctl --user status syncthing

# Or use helper
nazar-status

# Logs
sudo -u nazar journalctl --user -u openclaw -f
sudo -u nazar journalctl --user -u syncthing -f

# Or use helper
nazar-logs

# Restart
sudo -u nazar systemctl --user restart openclaw
sudo -u nazar systemctl --user restart syncthing

# Or use helper
nazar-restart
```

### OpenClaw CLI

```bash
# Configure
sudo -u nazar openclaw configure

# Health check
sudo -u nazar openclaw doctor

# Device management
sudo -u nazar openclaw devices list
sudo -u nazar openclaw devices approve <id>
```

### Syncthing CLI

```bash
# System info
sudo -u nazar syncthing cli show system

# Connections
sudo -u nazar syncthing cli show connections

# Folders
sudo -u nazar syncthing cli show folders
```

### Security

```bash
# Audit security
nazar-audit

# Check integrity
nazar-check-integrity

# Check canary tokens
nazar-check-canary

# Create backup
nazar-backup
```

## Verification Checklist

```bash
# Services running
sudo -u nazar systemctl --user status openclaw syncthing

# Gateway responds
curl -sk https://<tailscale-hostname>/

# Syncthing accessible
curl -s http://<tailscale-ip>:8384 | head

# Vault permissions correct
stat -c "%a %U:%G" /home/nazar/vault
# Expected: 700 nazar:nazar

# Security audit
nazar-audit

# Tailscale connected
tailscale status
```

## First Browser Access

The first time you open the Control UI (`https://<tailscale-hostname>/`) in a browser, the gateway will require **device pairing**.

To approve:

```bash
# List pending devices
sudo -u nazar openclaw devices list

# Approve
sudo -u nazar openclaw devices approve <request-id>
```

## Post-Deploy Setup

1. **Complete OpenClaw configuration:**
   ```bash
   sudo -u nazar openclaw configure
   ```

2. **Set up Syncthing on your devices:**
   - Get VPS device ID: `sudo -u nazar syncthing cli show system | grep myID`
   - Add to laptop/phone Syncthing
   - Share vault folder

3. **Open vault in Obsidian:**
   - Point Obsidian to the Syncthing-synced vault folder
   - Changes sync automatically

4. **Optional security hardening:**
   ```bash
   sudo bash ~/nazar/system/scripts/setup-all-security.sh
   ```

## Updating

### Update System Packages

```bash
sudo apt update && sudo apt upgrade -y
```

### Update OpenClaw

```bash
sudo npm install -g openclaw@latest
sudo -u nazar systemctl --user restart openclaw
```

### Update Syncthing

```bash
sudo apt update && sudo apt install --only-upgrade syncthing
```

### Update Bootstrap Scripts

```bash
cd ~/nazar
git pull origin main
# Re-run specific setup scripts if needed
```

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues.

Quick checks:

```bash
# All services status
nazar-status

# Check logs
nazar-logs

# Security audit
nazar-audit

# Tailscale connectivity
tailscale status
tailscale netcheck
```
