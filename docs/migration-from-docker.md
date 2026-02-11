# Migration Guide: Docker/Git → Direct/Syncthing

This guide helps you migrate from the old Docker + Git sync setup to the new direct execution + Syncthing setup.

## Overview of Changes

| Aspect | Old (Docker + Git) | New (Direct + Syncthing) |
|--------|-------------------|-------------------------|
| **Vault Location** | `/srv/nazar/vault/` | `/home/nazar/vault/` |
| **Sync Method** | Git over SSH | Syncthing |
| **OpenClaw** | Docker container | Direct npm install |
| **User** | `debian` runs everything | `debian` admin, `nazar` service |
| **Config** | `/srv/nazar/data/openclaw/` | `/home/nazar/.openclaw/` |

## Migration Steps

### 1. Backup Your Current Setup

```bash
# As debian user on old VPS
# Backup vault
tar czf ~/vault-backup-$(date +%Y%m%d).tar.gz -C /srv/nazar vault

# Backup OpenClaw config
tar czf ~/openclaw-backup-$(date +%Y%m%d).tar.gz -C /srv/nazar/data openclaw

# Download to local machine
scp debian@<old-vps>:~/vault-backup-*.tar.gz .
scp debian@<old-vps>:~/openclaw-backup-*.tar.gz .
```

### 2. Provision New VPS (or Reset Existing)

If using a new VPS:
```bash
# SSH to new VPS as root
ssh root@<new-vps-ip>

# Run new bootstrap
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash
```

If reusing existing VPS:
```bash
# Warning: This removes old setup!
# Stop and remove Docker containers
cd /srv/nazar && docker compose down
sudo rm -rf /srv/nazar

# Remove old cron jobs
crontab -r -u debian 2>/dev/null || true

# Run new bootstrap as root
sudo bash bootstrap/bootstrap.sh
```

### 3. Restore Your Vault

```bash
# As debian user on new VPS
# Copy backup to VPS
scp vault-backup-*.tar.gz debian@<new-vps>:~

# Extract to nazar user's vault
ssh debian@<new-vps>
sudo tar xzf ~/vault-backup-*.tar.gz -C /home/nazar/
sudo chown -R nazar:nazar /home/nazar/vault
```

### 4. Restore OpenClaw Config (Optional)

```bash
# Extract old config
sudo tar xzf ~/openclaw-backup-*.tar.gz -C /tmp/

# Copy relevant files (not everything - paths are different!)
sudo cp /tmp/openclaw/models.json /home/nazar/.openclaw/ 2>/dev/null || true
sudo cp /tmp/openclaw/channels.json /home/nazar/.openclaw/ 2>/dev/null || true
sudo chown -R nazar:nazar /home/nazar/.openclaw
```

**Note**: You may need to re-run `openclaw configure` to fix paths.

### 5. Set Up Syncthing

```bash
# Start Syncthing
sudo bash nazar/scripts/setup-syncthing.sh

# Get device ID
sudo -u nazar syncthing cli show system | grep myID
```

On your other devices:
1. Open Syncthing
2. Add the VPS device (using the ID above)
3. Share the vault folder

On VPS:
1. Access `http://<tailscale-ip>:8384`
2. Accept the device connection
3. Accept the folder share

### 6. Start OpenClaw

```bash
# Start OpenClaw
sudo bash nazar/scripts/setup-openclaw.sh

# Configure
sudo -u nazar openclaw configure
```

### 7. Verify Everything

```bash
# Check services
nazar-status

# Check sync
sudo -u nazar syncthing cli show connections

# Check gateway
curl -sk https://<tailscale-hostname>/
```

## Post-Migration Cleanup

### On Old VPS (if not resetting)

```bash
# Stop old services
cd /srv/nazar && docker compose down

# Remove old containers and images
docker system prune -a

# Optional: Remove Docker entirely
sudo apt remove docker-ce docker-ce-cli containerd.io

# Clean up directories
sudo rm -rf /srv/nazar
sudo rm -rf /opt/openclaw
```

### Update Your Devices

**Laptop/Desktop**:
1. Remove old Git remote if you were using one
2. Ensure Syncthing is syncing the vault folder
3. Open vault in Obsidian from Syncthing location

**Phone**:
1. If using Obsidian Git plugin, you can remove it
2. Ensure Syncthing app is syncing the vault
3. Open vault in Obsidian

## Troubleshooting Migration

### Vault Not Syncing

Check folder paths match:
```bash
# On VPS
ls /home/nazar/vault

# Should match your local vault structure
```

### OpenClaw Config Issues

It's often easier to reconfigure than migrate:
```bash
# Reset config
sudo -u nazar rm -rf ~/.openclaw
sudo -u nazar mkdir -p ~/.openclaw

# Reconfigure
sudo -u nazar openclaw configure
```

### Missing Voice Models

Reinstall voice tools:
```bash
sudo -u nazar bash -c '
    python3 -m venv ~/.local/venv-voice
    source ~/.local/venv-voice/bin/activate
    pip install openai-whisper piper-tts
'
```

## Rollback Plan

If something goes wrong, you can go back to the old setup:

1. **Stop new services**:
   ```bash
   sudo -u nazar systemctl --user stop openclaw syncthing
   ```

2. **Restore from backup**:
   ```bash
   # Restore old vault
   sudo rm -rf /home/nazar/vault
   sudo tar xzf ~/vault-backup-*.tar.gz -C /srv/nazar/
   
   # Restart Docker setup
   cd /srv/nazar && docker compose up -d
   ```

## Benefits of New Setup

After migration, you'll enjoy:

- **Real-time sync** — No more waiting for Git cron jobs
- **No merge conflicts** — Syncthing handles conflicts gracefully
- **Lower resource usage** — No Docker overhead
- **Simpler debugging** — Direct process access, no containers
- **Better mobile experience** — Native Syncthing apps

## Questions?

If you encounter issues during migration:

1. Check [troubleshooting.md](troubleshooting.md)
2. Review service logs: `nazar-logs`
3. Check Syncthing logs: `sudo -u nazar journalctl --user -u syncthing -f`
