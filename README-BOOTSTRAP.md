# Bootstrap Guide

Quick reference for bootstrapping a fresh VPS with the simplified Nazar Second Brain setup.

## Prerequisites

- Fresh Debian 13 or Ubuntu 22.04+ VPS
- Root SSH access
- Tailscale account
- API keys for your LLM provider(s)

## One-Line Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash
```

## What Happens

The bootstrap script will:

1. **Create Users**
   - `debian` — Administrator with sudo access
   - `nazar` — Service user (no sudo, runs OpenClaw + Syncthing)

2. **Install Software**
   - Node.js 22
   - OpenClaw (npm global)
   - Syncthing
   - Tailscale
   - Python 3 + Whisper + Piper (voice tools)

3. **Harden Security**
   - SSH: Keys only, no root login, no passwords
   - Firewall: UFW with minimal rules
   - Fail2Ban: Brute-force protection
   - Auto-updates: Unattended security patches

4. **Configure Services**
   - OpenClaw systemd user service
   - Syncthing systemd user service
   - Helper scripts and aliases

## Post-Bootstrap Steps

### 1. Configure Tailscale

```bash
sudo tailscale up
# Authenticate in browser when prompted
```

### 2. Clone Repository

```bash
su - debian
git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar
cd ~/nazar
```

### 3. Deploy Vault

```bash
# Copy vault to nazar user
sudo cp -r vault/* /home/nazar/vault/
sudo chown -R nazar:nazar /home/nazar/vault
```

### 4. Start Syncthing

```bash
sudo bash nazar/scripts/setup-syncthing.sh
```

Access GUI at `http://<tailscale-ip>:8384` and:
1. Set admin username/password
2. Note the Device ID
3. Add your laptop/phone devices

### 5. Start OpenClaw

```bash
sudo bash nazar/scripts/setup-openclaw.sh
sudo -u nazar openclaw configure
```

Access gateway at `https://<tailscale-hostname>/`

## Directory Structure After Bootstrap

```
/home/nazar/                    # Service user home
├── vault/                      # Obsidian vault (synced via Syncthing)
├── .openclaw/                  # OpenClaw config
│   ├── openclaw.json          # Main config
│   └── devices/               # Paired devices
├── .local/
│   ├── state/syncthing/       # Syncthing data
│   ├── venv-voice/            # Python voice tools
│   └── share/                 # Models (whisper, piper)
└── .config/                   # Application configs

/home/debian/                   # Admin user home
├── bin/                        # Helper scripts
│   ├── nazar-logs
│   ├── nazar-restart
│   └── nazar-status
└── nazar/                      # Repository clone (optional)
```

## Helper Commands

As `debian` user:

```bash
# Status
nazar-status

# Logs
nazar-logs

# Restart OpenClaw
nazar-restart

# Direct OpenClaw CLI
sudo -u nazar openclaw [command]

# Syncthing CLI
sudo -u nazar syncthing cli [command]
```

## Troubleshooting Bootstrap

### Script Fails

Check logs:
```bash
cat /var/log/nazar-bootstrap.log 2>/dev/null || echo "No log file"
```

### Tailscale Not Starting

```bash
# Check status
tailscale status

# Reinstall if needed
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Services Won't Start

```bash
# Check status
sudo -u nazar systemctl --user status openclaw
sudo -u nazar systemctl --user status syncthing

# Check logs
sudo -u nazar journalctl --user -u openclaw
sudo -u nazar journalctl --user -u syncthing
```

## Next Steps

- Read [docs/syncthing-setup.md](docs/syncthing-setup.md) for detailed sync configuration
- Read [docs/openclaw-config.md](docs/openclaw-config.md) for gateway configuration
- Read [system/docs/admin-guide.md](system/docs/admin-guide.md) for administration

## Comparison with Old Setup

| | Old (Docker + Git) | New (Direct + Syncthing) |
|---|---|---|
| Setup time | ~30 min (Docker build) | ~5 min (package install) |
| Resource usage | Higher (containers) | Lower (native) |
| Sync | Git cron (5 min delay) | Syncthing (real-time) |
| Conflicts | Git merge issues | Conflict files (easier) |
| Maintenance | Docker updates, image builds | System packages only |
