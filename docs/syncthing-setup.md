# Syncthing Setup Guide

Syncthing provides real-time synchronization of your Obsidian vault across all devices.

## Architecture

```
┌─────────────┐                        ┌─────────────┐                        ┌─────────────┐
│   Laptop    │ ◄─────── Internet ────► │     VPS     │ ◄─────── Internet ────► │    Phone    │
│  Syncthing  │   or SSH Tunnel/VPN    │  Syncthing  │   or SSH Tunnel/VPN    │  Syncthing  │
│  ~/vault    │ ◄───── sync vault ────► │ ~/nazar/    │ ◄───── sync vault ────► │  ~/vault    │
└─────────────┘                        │   vault     │                        └─────────────┘
                                       └─────────────┘
```

## Initial Setup

### On the VPS

After running the Docker setup:

```bash
# Get your device ID
docker compose exec syncthing syncthing cli show system | grep myID

# Or use CLI
nazar-cli syncthing-id
```

Access the GUI via SSH tunnel:
```bash
# On laptop
ssh -N -L 8384:localhost:8384 debian@vps-ip

# Then open: http://localhost:8384
```

**First-time GUI setup:**
1. Set admin username and password (important!)
2. Note the Device ID (Settings → General → Device ID)
3. Access via SSH tunnel only (localhost:8384)

### On Your Laptop

1. **Install Syncthing:**
   - macOS: `brew install syncthing`
   - Windows: Download from syncthing.net
   - Linux: `apt install syncthing`

2. **Start Syncthing:**
   ```bash
   syncthing serve
   ```

3. **Access GUI:** `http://localhost:8384`

4. **Add VPS as Device:**
   - Actions → Show ID (copy your laptop's device ID)
   - Add Remote Device → Enter VPS device ID
   - Sharing: Check "Introducer" to auto-share folders

### On Your Phone

1. **Install Syncthing:**
   - Android: F-Droid or Play Store
   - iOS: Möbius Sync (paid) or use alternative

2. **Add VPS Device:**
   - Use QR code scan or enter Device ID manually
   - Accept on VPS side

## Folder Configuration

### On VPS

```bash
# Via GUI or CLI - folder path inside container
docker compose exec syncthing syncthing cli config folders add \
    --id nazar-vault \
    --label "Nazar Vault" \
    --path /var/syncthing/vault

# Share with your devices
docker compose exec syncthing syncthing cli config folders nazar-vault devices add --device-id <LAPTOP-DEVICE-ID>
docker compose exec syncthing syncthing cli config folders nazar-vault devices add --device-id <PHONE-DEVICE-ID>
```

### Recommended Settings

**Folder Settings (`nazar-vault`):**

| Setting | Value | Reason |
|---------|-------|--------|
| Folder Path | `/var/syncthing/vault` | Container path |
| Folder ID | `nazar-vault` | Unique identifier |
| File Versioning | Simple File Versioning | Protect against accidental deletes |
| Keep Versions | 3 | Balance safety vs storage |
| Cleanup Interval | 3600 (1 hour) | Regular cleanup |
| Ignore Permissions | OFF | Respect Linux permissions |

**Device Settings:**

| Setting | Value |
|---------|-------|
| Auto Accept | Enabled (for known folders) |
| Compression | Metadata (default) |
| Rate Limiting | Unlimited on LAN, limit on WAN if needed |

## Security

### Access Control

Always access Syncthing GUI via SSH tunnel:

```bash
# Single tunnel for Syncthing only
ssh -N -L 8384:localhost:8384 debian@vps-ip

# Combined with OpenClaw
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@vps-ip
```

### Firewall

Syncthing sync protocol uses outgoing connections by default. If you want to allow direct incoming connections (optional):

```bash
# Optional: Allow Syncthing discovery on Tailscale interface
sudo ufw allow in on tailscale0 to any port 22000 proto tcp comment 'Syncthing'
sudo ufw allow in on tailscale0 to any port 22000 proto udp comment 'Syncthing'
sudo ufw allow in on tailscale0 to any port 21027 proto udp comment 'Syncthing discovery'
```

## Troubleshooting

### Devices Not Connecting

1. Check that Syncthing is running:
   ```bash
   docker compose ps
   ```

2. Verify Syncthing is listening:
   ```bash
   docker compose exec syncthing netstat -tlnp | grep syncthing
   ```

3. Check device IDs are correct

4. Verify network connectivity between devices

### Sync Conflicts

Syncthing creates conflict files: `filename.sync-conflict-YYYYMMDD-HHMMSS.md`

To resolve:
1. Compare versions in Obsidian
2. Merge manually
3. Delete conflict file

### Permission Issues

Ensure proper ownership:
```bash
chown -R 1000:1000 ~/nazar/vault
```

### Logs

```bash
# Syncthing logs
docker compose logs -f syncthing

# Syncthing CLI
docker compose exec syncthing syncthing cli show system
docker compose exec syncthing syncthing cli show connections
docker compose exec syncthing syncthing cli show folders
```

## CLI Reference

```bash
# Common commands
docker compose exec syncthing syncthing cli show system           # System info
docker compose exec syncthing syncthing cli show config           # Full config
docker compose exec syncthing syncthing cli show connections      # Connected devices
docker compose exec syncthing syncthing cli show folders          # Folder status
docker compose exec syncthing syncthing cli show pending-devices  # Pending devices
docker compose exec syncthing syncthing cli show pending-folders  # Pending folders

# Add device
docker compose exec syncthing syncthing cli config devices add --device-id <ID> --name "My Laptop"

# Add folder
docker compose exec syncthing syncthing cli config folders add --id vault --path /var/syncthing/vault

# Restart
docker compose restart syncthing
```
