# Migration Guide

This guide helps you migrate from a previous setup to the new Docker-based setup.

## From Old Systemd Setup (nazar user)

### Overview

| Aspect | Old (Systemd) | New (Docker) |
|--------|--------------|--------------|
| OpenClaw | npm global + systemd | Docker container |
| Syncthing | Native package + systemd | Docker container |
| User | `debian` + `nazar` | `debian` only |
| Vault location | `/home/nazar/vault` | `~/nazar/vault` |
| Access | Tailscale only | SSH tunnel or Tailscale |

### Migration Steps

#### Step 1: Backup Current Data

```bash
# As debian user on old setup

# Create backup directory
mkdir -p ~/migration-backup-$(date +%Y%m%d)

# Backup vault
cp -r /home/nazar/vault ~/migration-backup-$(date +%Y%m%d)/

# Backup OpenClaw config
cp -r /home/nazar/.openclaw ~/migration-backup-$(date +%Y%m%d)/

# Backup Syncthing config (optional - will get new Device ID)
cp -r /home/nazar/.local/state/syncthing ~/migration-backup-$(date +%Y%m%d)/

# Get current Syncthing Device ID (for reference)
sudo -u nazar syncthing cli show system | grep myID

# Get current OpenClaw token (to keep same token)
grep '"token"' /home/nazar/.openclaw/openclaw.json
```

#### Step 2: Stop Old Services

```bash
# Stop services
sudo -u nazar systemctl --user stop openclaw syncthing
sudo -u nazar systemctl --user disable openclaw syncthing

# Disable lingering
sudo loginctl disable-linger nazar

# Remove systemd services
sudo rm -f /etc/systemd/user/openclaw.service
sudo rm -f /etc/systemd/user/syncthing.service
sudo systemctl daemon-reload
```

#### Step 3: Install Docker (if not present)

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker debian

# Logout and login again for group change
exit
ssh debian@your-vps
```

#### Step 4: Deploy New Docker Setup

```bash
# Run the new setup script
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash

# Or manual setup
mkdir -p ~/nazar/{vault,.openclaw/workspace,syncthing/config}
```

#### Step 5: Migrate Data

```bash
# Copy vault to new location
rsync -av /home/nazar/vault/ ~/nazar/vault/

# Copy OpenClaw config (optional - keep same token)
# Edit to update paths from /home/nazar to container paths
cp /home/nazar/.openclaw/openclaw.json ~/nazar/.openclaw/

# Fix permissions (container uses UID 1000)
chown -R 1000:1000 ~/nazar
```

#### Step 6: Start New Services

```bash
cd ~/nazar/docker
docker compose up -d --build

# Check status
docker compose ps
```

#### Step 7: Reconfigure Syncthing

Your Syncthing will have a **new Device ID** (since config is inside container).

1. **Get new Device ID**:
   ```bash
   docker compose exec syncthing syncthing cli show system | grep myID
   ```

2. **On your other devices**:
   - Remove the old VPS device
   - Add the new Device ID
   - Share the vault folder

3. **Accept on VPS** via Syncthing GUI

#### Step 8: Verify Everything Works

```bash
# Check OpenClaw
docker compose exec openclaw openclaw health

# Check Syncthing
docker compose exec syncthing syncthing cli show connections

# Verify vault sync
ls -la ~/nazar/vault/
```

#### Step 9: Cleanup Old Setup (after verification)

```bash
# Remove old packages (optional)
sudo apt-get remove -y syncthing nodejs
sudo apt-get autoremove -y

# Remove old directories
sudo rm -rf /home/nazar/.openclaw
sudo rm -rf /home/nazar/.local/state/syncthing
sudo rm -rf /home/nazar/vault  # Only after confirming sync works!

# Remove old helper scripts
sudo rm -f /home/debian/bin/nazar-*

# Optionally remove nazar user
sudo userdel nazar
```

## From Other Setups

### Generic Docker Migration

If you have an existing vault elsewhere:

```bash
# 1. Setup new Docker environment
curl -fsSL https://raw.githubusercontent.com/alexradunet/.../docker/setup.sh | bash

# 2. Copy vault
cp -r /path/to/existing/vault/* ~/nazar/vault/

# 3. Fix permissions
chown -R 1000:1000 ~/nazar/vault

# 4. Restart Syncthing
cd ~/nazar/docker
docker compose restart syncthing

# 5. Configure Syncthing with your devices
```

## Rollback

If something goes wrong:

```bash
# Stop Docker services
cd ~/nazar/docker
docker compose down

# Restore from backup
cd ~
tar -xzf migration-backup-*/nazar-backup-*.tar.gz

# Restore old services (if kept)
sudo systemctl daemon-reload
sudo loginctl enable-linger nazar
sudo -u nazar systemctl --user enable openclaw syncthing
sudo -u nazar systemctl --user start openclaw syncthing
```

## Post-Migration Checklist

- [ ] Syncthing shows connected devices
- [ ] Vault is syncing (no conflicts)
- [ ] OpenClaw gateway accessible via SSH tunnel
- [ ] Can authenticate with token
- [ ] Can approve new devices
- [ ] All vault contents present
- [ ] Agent workspace files accessible (SOUL.md, etc.)

## Troubleshooting

### Permission Issues

```bash
# Fix ownership
chown -R 1000:1000 ~/nazar
```

### Syncthing Device ID Changed

This is expected. You need to:
1. Get new ID: `docker compose exec syncthing syncthing cli show system`
2. Add new ID to your devices
3. Remove old device from other devices

### OpenClaw Token Lost

Generate new token:
```bash
TOKEN=$(openssl rand -hex 32)
docker compose exec openclaw \
    sed -i "s/\"token\": \"[^\"]*\"/\"token\": \"$TOKEN\"/" \
    /home/node/.openclaw/openclaw.json
docker compose restart openclaw
echo "New token: $TOKEN"
```

### Vault Not Syncing

```bash
# Check Syncthing logs
docker compose logs syncthing

# Force rescan
docker compose exec syncthing syncthing cli post system scan
```
