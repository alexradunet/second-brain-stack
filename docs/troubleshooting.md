# Troubleshooting

Common issues and their solutions for the Docker-based setup.

## Quick Diagnostics

Run this to check everything:

```bash
#!/bin/bash
cd ~/nazar/docker

echo "=== Docker Containers ==="
docker compose ps

echo ""
echo "=== Container Logs (last 20 lines) ==="
docker compose logs --tail=20

echo ""
echo "=== Firewall ==="
sudo ufw status | head -5

echo ""
echo "=== Disk Space ==="
df -h ~ | tail -1

echo ""
echo "=== Memory ==="
free -h | grep Mem

echo ""
echo "=== Security Audit ==="
sudo nazar-security-audit 2>/dev/null || echo "Run: sudo nazar-cli security"
```

## Docker Issues

### Containers Won't Start

**Symptom**: `docker compose up` fails or containers exit immediately

**Check**:
```bash
# View logs
docker compose logs

# Check disk space
df -h

# Check permissions
ls -la ~/nazar/
```

**Fix**:
```bash
# Fix ownership (containers run as UID 1000)
sudo chown -R 1000:1000 ~/nazar

# Restart containers
docker compose restart

# If still failing, try rebuild
docker compose down
docker compose up -d --build
```

### Permission Denied on Vault

**Symptom**: OpenClaw can't read/write vault files

**Fix**:
```bash
# Fix ownership
sudo chown -R 1000:1000 ~/nazar/vault
sudo chmod -R u+rw ~/nazar/vault
```

## Syncthing Issues

### Devices Not Connecting

**Symptom**: Devices show as "Disconnected" in Syncthing GUI

**Check**:
```bash
# 1. Syncthing is running
docker compose ps

# 2. Syncthing is listening
docker compose exec syncthing netstat -tlnp

# 3. Device IDs are correct
docker compose exec syncthing syncthing cli show system | grep myID

# 4. Check connections
docker compose exec syncthing syncthing cli show connections
```

**Fix**:
- Ensure Syncthing is running: `docker compose up -d syncthing`
- Re-add device IDs if changed
- Check Syncthing logs: `docker compose logs -f syncthing`

### Sync Conflicts

**Symptom**: Files like `note.md.sync-conflict-20260211-143022.md`

**Fix**:
1. Open both files in Obsidian
2. Compare and merge changes manually
3. Delete the `.sync-conflict-*` file

**Prevent**:
- Enable "Auto Save" in Obsidian
- Avoid editing the same file simultaneously on multiple devices

### Slow Sync

**Check**:
```bash
# Connection type (relay vs direct)
docker compose exec syncthing syncthing cli show connections | grep type

# Should show "type": "tcp-client" or "type": "tcp-server"
# "type": "relay-client" means using relay (slower)
```

**Fix**:
- Ensure both devices are on the same network or have direct internet access
- Check if firewall is blocking direct connections
- Consider enabling UPnP on your router

## OpenClaw Issues

### Gateway Won't Start

**Symptom**: Container keeps restarting or won't start

**Check**:
```bash
# View logs
docker compose logs -f openclaw

# Check config
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json

# Validate JSON
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | jq .
```

**Fix**:
```bash
# Fix invalid JSON
# Edit ~/nazar/.openclaw/openclaw.json and fix syntax errors

# Restart
docker compose restart openclaw
```

### Can't Access Gateway

**Symptom**: Connection refused or timeout

**Check**:
```bash
# 1. Container is running
docker compose ps

# 2. OpenClaw is listening
docker compose exec openclaw netstat -tlnp

# 3. SSH tunnel is active (if using SSH tunnel mode)
# Check if you ran: ssh -L 18789:localhost:18789 debian@vps-ip

# 4. Token is correct
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | grep token
```

**Fix**:
- Start containers: `docker compose up -d`
- Open SSH tunnel: `ssh -N -L 18789:localhost:18789 debian@vps-ip`
- Check firewall: `sudo ufw status`

### Token Lost or Forgotten

**Fix**:
```bash
# Retrieve token
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | grep token

# Or use CLI
nazar-cli token

# To generate new token:
TOKEN=$(openssl rand -hex 32)
docker compose exec openclaw \
    sed -i "s/\"token\": \"[^\"]*\"/\"token\": \"$TOKEN\"/" \
    /home/node/.openclaw/openclaw.json
docker compose restart openclaw
echo "New token: $TOKEN"
```

## SSH Tunnel Issues

### Can't Establish SSH Connection

**Symptom**: `ssh: connect to host ... port 22: Connection refused`

**Check**:
```bash
# From VPS, check SSH is running
sudo systemctl status sshd

# Check SSH port
grep "^Port" /etc/ssh/sshd_config

# Check firewall
sudo ufw status
```

**Fix**:
```bash
# If SSH service not running
sudo systemctl start sshd

# If blocked by firewall
sudo ufw allow 22/tcp
```

### Tunnel Disconnects

**Symptom**: SSH tunnel drops after period of inactivity

**Fix**:
```bash
# Use autossh for persistent tunnels
sudo apt-get install autossh
autossh -M 0 -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@vps-ip

# Or add to SSH config (~/.ssh/config)
Host nazar-tunnel
    HostName vps-ip
    User debian
    LocalForward 18789 localhost:18789
    LocalForward 8384 localhost:8384
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## Security Issues

### Fail2ban Blocking Your IP

**Symptom**: Can't SSH into VPS

**Fix** (requires console access via provider's panel):
```bash
# Check banned IPs
sudo fail2ban-client status sshd

# Unban your IP
sudo fail2ban-client set sshd unbanip <YOUR_IP>
```

### UFW Blocking Connections

**Symptom**: Services inaccessible

**Fix**:
```bash
# Check status
sudo ufw status verbose

# Reset if needed (be careful!)
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw --force enable
```

## Performance Issues

### High Memory Usage

**Symptom**: VPS running out of memory

**Check**:
```bash
# Memory usage
free -h

# Container memory
docker stats --no-stream
```

**Fix**:
```bash
# Add swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Or reduce container memory limits in docker-compose.yml
```

### High CPU Usage

**Check**:
```bash
# CPU usage by container
docker stats --no-stream

# Top processes
docker compose exec openclaw top
```

**Fix**:
- Check OpenClaw logs for infinite loops
- Restart containers: `docker compose restart`
- Check if processing large files

## Backup and Recovery

### Corrupted Vault

**Symptom**: Sync errors, missing files

**Fix**:
1. Stop Syncthing: `docker compose stop syncthing`
2. Restore from backup:
   ```bash
   cd ~
   tar -xzf nazar/backups/nazar-backup-*.tar.gz
   ```
3. Fix permissions: `sudo chown -R 1000:1000 ~/nazar`
4. Restart: `docker compose up -d`

### Lost Configuration

**Fix**:
```bash
# If .openclaw directory is lost
# 1. Regenerate config
mkdir -p ~/nazar/.openclaw/workspace

# 2. Create new openclaw.json with setup script
# Or manually create minimal config

# 3. Reconfigure
docker compose exec -it openclaw openclaw configure
```

## Getting Help

If issues persist:

1. **Check logs**: `docker compose logs -f`
2. **Run diagnostics**: `nazar-cli status`
3. **Security audit**: `nazar-cli security`
4. **Open issue**: Include logs and diagnostics output
