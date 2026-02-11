# VPS Setup Cheatsheet

Quick reference for managing your Nazar Second Brain VPS after initial setup.

---

## Quick Connect

```bash
# Connect via Tailscale (recommended)
ssh debian@<tailscale-ip>

# Or use the Tailscale hostname
ssh debian@<tailscale-hostname>
```

---

## Bash Aliases (Configured on VPS)

The following aliases are configured for the `debian` user:

### OpenClaw & Service Management

| Alias | Description |
|-------|-------------|
| `nazar-status` | Check OpenClaw and Syncthing status |
| `nazar-logs` | View OpenClaw logs |
| `nazar-restart` | Restart OpenClaw service |
| `nazar-audit` | Run security audit |
| `nazar-backup` | Create encrypted backup |

**Examples:**
```bash
# Check system status
nazar-status

# View logs
nazar-logs

# Restart OpenClaw
nazar-restart

# Run security audit
nazar-audit
```

### Direct Commands (as debian user)

```bash
# OpenClaw CLI
sudo -u nazar openclaw doctor
sudo -u nazar openclaw configure
sudo -u nazar openclaw devices list
sudo -u nazar openclaw devices approve <request-id>

# Syncthing CLI
sudo -u nazar syncthing cli show system
sudo -u nazar syncthing cli show connections
sudo -u nazar syncthing cli show folders
```

---

## Essential Commands

### Service Management

```bash
# View service status
sudo -u nazar systemctl --user status openclaw
sudo -u nazar systemctl --user status syncthing

# View logs
sudo -u nazar journalctl --user -u openclaw --tail 50
sudo -u nazar journalctl --user -u syncthing --tail 50

# Follow logs in real-time
sudo -u nazar journalctl --user -u openclaw -f

# Restart services
sudo -u nazar systemctl --user restart openclaw
sudo -u nazar systemctl --user restart syncthing

# Stop services
sudo -u nazar systemctl --user stop openclaw
sudo -u nazar systemctl --user stop syncthing
```

### Syncthing Operations

```bash
# Check Syncthing status
sudo -u nazar syncthing cli show system

# List connected devices
sudo -u nazar syncthing cli show connections

# List folders
sudo -u nazar syncthing cli show folders

# View pending devices (waiting to connect)
sudo -u nazar syncthing cli show pending-devices

# Accept a device
sudo -u nazar syncthing cli config devices add --device-id <DEVICE-ID>
```

### Fix Syncthing Issues

If sync is not working:

```bash
# Check Tailscale connectivity
ssh debian@<tailscale-ip> "tailscale status"

# Check Syncthing is listening
ssh debian@<tailscale-ip> "sudo -u nazar ss -tlnp | grep syncthing"

# Restart Syncthing
ssh debian@<tailscale-ip> "sudo -u nazar systemctl --user restart syncthing"

# Check for conflicts
ssh debian@<tailscale-ip> "find /home/nazar/vault -name '*.sync-conflict-*'"
```

### System Status

```bash
# Quick status check
echo "=== Tailscale ===" && tailscale status
echo "=== Services ===" && nazar-status
echo "=== Firewall ===" && sudo ufw status
echo "=== Disk Space ===" && df -h /home/nazar
echo "=== Memory ===" && free -h
```

---

## Device Pairing / Approval

When accessing the Control UI for the first time from a new browser/device:

1. **Open** `https://<tailscale-hostname>/`
2. You'll see "pairing required" — this is normal
3. **SSH into VPS** and approve:

```bash
ssh debian@<tailscale-ip>

# List pending devices
sudo -u nazar openclaw devices list

# Approve
sudo -u nazar openclaw devices approve <request-id>

# Restart OpenClaw to apply
sudo -u nazar systemctl --user restart openclaw
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `/home/nazar/.openclaw/openclaw.json` | OpenClaw configuration |
| `/home/nazar/.openclaw/.env` | API keys and secrets |
| `/home/nazar/.local/state/syncthing/config.xml` | Syncthing configuration |
| `/home/nazar/vault/99-system/openclaw/workspace/` | Agent personality, memory, tools |
| `/home/debian/.bashrc` | Bash aliases and environment |

---

## Troubleshooting

### Gateway shows "pairing required"

See **Device Pairing** section above.

### OpenClaw won't start

```bash
# Check logs
sudo -u nazar journalctl --user -u openclaw -n 50

# Check config validity
sudo -u nazar jq . /home/nazar/.openclaw/openclaw.json

# Fix config issues
sudo -u nazar openclaw doctor --fix

# Verify Node.js
node --version  # Should be 22+

# Reinstall if needed
sudo npm install -g openclaw@latest
```

### Syncthing not syncing

```bash
# Check permissions
ls -la /home/nazar/vault

# Fix permissions
sudo chown -R nazar:nazar /home/nazar/vault

# Check device connections
sudo -u nazar syncthing cli show connections

# Check for errors
sudo -u nazar journalctl --user -u syncthing -n 50
```

### Locked out of SSH

If Tailscale is down:
1. Use VPS provider's web console (OVH KVM, Hetzner Console, etc.)
2. Re-enable public SSH: `sudo ufw allow 22/tcp`
3. SSH via public IP: `ssh debian@<public-ip>`
4. Fix Tailscale: `sudo tailscale up`
5. Re-lock: `sudo ufw delete allow 22/tcp`

---

## Syncthing Architecture

Understanding the sync flow:

```
Laptop Syncthing ◄────► VPS Syncthing ◄────► Phone Syncthing
      ~/vault              ~/vault              ~/vault
           \_____________/
           Tailscale VPN
```

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **Vault Directory** | Obsidian vault files | `/home/nazar/vault` |
| **Syncthing Config** | Device/folder settings | `/home/nazar/.local/state/syncthing/` |
| **GUI** | Web interface | `http://<tailscale-ip>:8384` |

### Conflict Handling

Syncthing creates `.sync-conflict-YYYYMMDD-HHMMSS.md` files when the same file is edited on multiple devices.

To resolve:
1. Compare versions in Obsidian
2. Merge manually
3. Delete conflict file

---

## Security Audit

Run the built-in security audit:

```bash
nazar-audit
```

For enhanced security checks:
```bash
# If you ran the security hardening
nazar-check-integrity  # File integrity
nazar-check-canary     # Check canary tokens
nazar-check-audit      # Audit log summary
```

Checks: root login disabled, SSH key-only, firewall active, Fail2Ban running, auto-updates enabled, Tailscale connected, no secrets in vault.

---

## Local Vault Setup (for Obsidian)

From your local machine:

```bash
# Install Syncthing on laptop
# macOS: brew install syncthing
# Windows: download from syncthing.net
# Linux: apt install syncthing

# Start Syncthing
syncthing serve

# Access GUI: http://localhost:8384
# Add VPS device ID (get from VPS: sudo -u nazar syncthing cli show system | grep myID)
# Share vault folder with VPS
```

Then point Obsidian to the Syncthing-synced vault folder.

---

## Important Paths Summary

```
/home/nazar/                    # Service user home
├── vault/                      # Obsidian vault (mode 700)
│   ├── 00-inbox/
│   ├── 01-daily-journey/
│   ├── ...
│   └── 99-system/openclaw/
│       ├── workspace/          # Agent memory/personality
│       └── skills/             # Agent capabilities
├── .openclaw/                  # OpenClaw config (mode 700)
│   ├── openclaw.json          # Main configuration
│   ├── .env                   # API keys
│   └── devices/               # Paired/pending devices
└── .local/state/syncthing/     # Syncthing data

/home/debian/                   # Admin user home
├── bin/                        # Helper scripts
│   ├── nazar-status
│   ├── nazar-logs
│   ├── nazar-restart
│   ├── nazar-audit
│   └── nazar-backup
└── nazar/                      # Repository clone

/etc/systemd/user/              # Systemd user services
├── openclaw.service           # OpenClaw gateway
└── syncthing.service          # Syncthing sync
```

---

*Last updated: 2026-02-11*
