# Troubleshooting

Common issues and how to fix them.

## Access Issues

### Can't reach gateway via Tailscale

**Symptom:** `https://<tailscale-hostname>/` not loading.

**Cause:** The gateway uses integrated Tailscale Serve mode (`tailscale: { mode: "serve" }` in docker-compose) and manages its own proxy automatically. No manual `tailscale serve` is needed for the gateway.

**Check:**
```bash
# Is the gateway container running?
docker compose ps nazar-gateway

# Check gateway logs for Tailscale Serve errors
docker compose logs nazar-gateway | grep -i tailscale

# Verify the container is using host networking
docker inspect nazar-gateway --format='{{.HostConfig.NetworkMode}}'
# Expected: host
```

**Fix:** If the gateway container is running but not reachable, restart it to re-establish the Tailscale Serve proxy:
```bash
docker compose restart nazar-gateway
```

---

### Can't reach Syncthing UI via Tailscale IP

**Symptom:** `http://<tailscale-ip>:8384` times out or refuses connection, but `curl http://127.0.0.1:8384` works locally on the VPS.

**Cause:** Syncthing UI is bound to `127.0.0.1` in `docker-compose.yml` (by design — no public exposure). Tailscale traffic arrives on the `tailscale0` interface, not the loopback, so `127.0.0.1`-bound ports reject it.

**Fix:** Use `tailscale serve` to proxy Tailscale traffic to localhost:

```bash
sudo tailscale serve --bg --tcp 8384 tcp://127.0.0.1:8384
```

After this, Syncthing UI is reachable at `http://<tailscale-ip>:8384` from your tailnet.

To check active proxies:
```bash
tailscale serve status
```

To remove the proxy:
```bash
sudo tailscale serve --tcp=8384 off
```

**Note:** `tailscale serve` proxies persist across reboots as long as Tailscale is running. No UFW rules are needed — traffic stays within the Tailscale tunnel.

---

### Locked out of SSH (Tailscale down)

**Symptom:** Can't SSH via Tailscale IP, Tailscale appears down on VPS.

**Fix:**
1. Use your VPS provider's web console (OVH KVM, Hetzner Console)
2. Log in as `nazar`
3. Re-enable public SSH: `sudo ufw allow 22/tcp`
4. SSH in normally: `ssh nazar@<public-ip>`
5. Fix Tailscale: `sudo tailscale up`
6. Verify Tailscale SSH: `ssh nazar@<tailscale-ip>` (from another terminal)
7. Re-lock: `sudo bash lock-ssh-to-tailscale.sh`

### Can't reach gateway or Syncthing UI (containers running)

**Symptom:** `https://<tailscale-hostname>/` or `http://<tailscale-ip>:8384` not loading, but containers are running.

**Check:**
```bash
# Is Tailscale running?
tailscale status

# Are containers running?
docker compose ps

# Is Syncthing UI port bound correctly?
ss -tlnp | grep 8384
# Should show 127.0.0.1 — this is correct and expected

# Is the gateway container using host networking?
docker inspect nazar-gateway --format='{{.HostConfig.NetworkMode}}'
# Expected: host

# Is the manual tailscale serve proxy active for Syncthing UI?
tailscale serve status
```

**Fix:**
- **Gateway:** The gateway manages its own Tailscale Serve proxy. Restart the container: `docker compose restart nazar-gateway`
- **Syncthing UI:** If `tailscale serve status` shows no proxy for port 8384, set it up: `sudo tailscale serve --bg --tcp 8384 tcp://127.0.0.1:8384`


### Control UI shows "pairing required"

**Symptom:** Opening `https://<tailscale-hostname>/` in a browser shows a pairing/approval prompt instead of the Control UI.

**Cause:** This is expected on first connection from a new browser/device. The gateway requires device approval before granting access.

**Fix:**

```bash
# SSH into the VPS, then:
openclaw devices list                     # List pending pairing requests
openclaw devices approve <request-id>     # Approve the pending request
```

After approval, refresh the browser. The device is remembered for subsequent visits.

---

### VSCode Remote SSH fails with "TCP port forwarding disabled"

**Symptom:** VSCode Remote SSH connection fails with `administratively prohibited` or `AllowTcpForwarding` error.

**Cause:** SSH hardening disabled TCP forwarding, which VSCode needs for its SOCKS proxy.

**Fix:**
```bash
sudo sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config.d/hardened.conf
sudo sshd -t && sudo systemctl restart sshd
```

## Container Issues

### Containers won't start

**Check logs:**
```bash
cd /srv/nazar
docker compose logs nazar-gateway
docker compose logs nazar-syncthing
```

**Common causes:**
- `.env` file missing or malformed
- Port already in use: `ss -tlnp | grep <port>`
- Docker daemon not running: `sudo systemctl start docker`

### Gateway container unhealthy

```bash
docker inspect nazar-gateway --format='{{.State.Health.Status}}'
docker inspect nazar-gateway --format='{{range .State.Health.Log}}{{.Output}}{{end}}' | tail -5
```

**Fix:** Usually a startup timing issue. Wait 30 seconds or restart:
```bash
docker compose restart nazar-gateway
```

### Build fails (out of memory)

**Symptom:** `pnpm install` or model download crashes during `docker compose build`.

**Fix:** Add swap:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
# Then retry
docker compose build
```

### Container can't write to vault

**Symptom:** Permission denied errors in gateway logs.

**Fix:**
```bash
sudo chown -R 1000:1000 /srv/nazar/vault /srv/nazar/data
```

Containers run as uid 1000 — the vault must be owned by that uid.

## Syncthing Issues

### Devices not connecting

```bash
# Check firewall
sudo ufw status | grep -E "22000|21027"

# Check Syncthing logs
docker compose logs nazar-syncthing | tail -30

# Verify Syncthing is listening
ss -tulnp | grep -E "22000|21027"
```

If using a cloud VPS, also check the provider's firewall/security group settings (separate from UFW).

### Sync conflicts

```bash
# Find conflict files
find /srv/nazar/vault -name "*.sync-conflict-*"

# Resolve: keep the version you want, delete the conflict file
```

### Vault empty after setup

Syncthing needs time to complete initial sync. Check progress in the UI at `http://<tailscale-ip>:8384`.

If the folder shows "Unshared" — you need to accept the folder share on the VPS side.

## Voice Processing Issues

### Transcription not working

```bash
# Check if voice tools are in the container
docker compose exec nazar-gateway python3 -c "from faster_whisper import WhisperModel; print('ok')"

# Check if models exist
docker compose exec nazar-gateway ls /opt/models/whisper/
docker compose exec nazar-gateway ls /opt/models/piper/
```

If models are missing, rebuild the image:
```bash
docker compose build --no-cache nazar-gateway
docker compose up -d
```

### High memory during transcription

Whisper `small` model uses ~1GB RAM. On low-memory VPS:
- Ensure swap is enabled
- Use `tiny` or `base` model instead of `small`

## Configuration Issues

### Agent not loading workspace

```bash
# Check workspace mount
docker compose exec nazar-gateway ls /home/node/.openclaw/workspace/
# Should show: SOUL.md, AGENTS.md, USER.md, etc.

# If empty, check the volume mount path
grep workspace docker-compose.yml
```

The workspace path depends on `OPENCLAW_WORKSPACE_PATH` in `.env` (defaults to `99-system/openclaw/workspace`).

### Gateway crashes with "Config invalid"

**Symptom:** `nazar-gateway` keeps restarting. Logs show `Config invalid` and `Unrecognized key`.

**Check:**
```bash
docker logs nazar-gateway 2>&1 | grep -A2 "Config invalid"
```

**Fix:** OpenClaw evolves and may drop config keys between versions. Run the built-in doctor:
```bash
docker compose exec nazar-gateway openclaw doctor --fix
docker compose restart nazar-gateway
```

Or manually edit `/srv/nazar/data/openclaw/openclaw.json` to remove the offending keys listed in the error.

**Known invalid keys:** `tools.elevated.ask` (removed in recent OpenClaw versions).

---

### API key not working

```bash
# Check .env has the key
grep ANTHROPIC_API_KEY /srv/nazar/.env

# Check container sees it
docker compose exec nazar-gateway env | grep ANTHROPIC

# Test the key
docker compose exec nazar-gateway node -e "
  fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'content-type': 'application/json',
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({model:'claude-sonnet-4-5-20250929',max_tokens:10,messages:[{role:'user',content:'hi'}]})
  }).then(r => r.json()).then(console.log)
"
```

### Changes to .env not taking effect

`.env` is read at container start. After editing:
```bash
cd /srv/nazar && docker compose restart
```

## Security Issues

### Suspicious SSH attempts

```bash
# Check Fail2Ban status
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client get sshd banip

# Check auth log
sudo journalctl -u sshd --since "1 hour ago" | grep "Failed"
```

### Run a full security audit

```bash
sudo bash /srv/nazar/vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

## General Diagnostics

### Quick status check

```bash
# Everything at a glance
echo "=== Tailscale ===" && tailscale status
echo "=== Docker ===" && cd /srv/nazar && docker compose ps
echo "=== Firewall ===" && sudo ufw status
echo "=== Fail2Ban ===" && sudo fail2ban-client status sshd
echo "=== Disk ===" && df -h /
echo "=== Memory ===" && free -h
```

### Collect debug info

```bash
# Save to a file for sharing
{
  echo "=== Date ===" && date
  echo "=== Uptime ===" && uptime
  echo "=== Memory ===" && free -h
  echo "=== Disk ===" && df -h /
  echo "=== Docker ===" && docker compose ps 2>/dev/null
  echo "=== Tailscale ===" && tailscale status 2>/dev/null
  echo "=== UFW ===" && sudo ufw status
  echo "=== Recent gateway logs ===" && docker compose logs --tail 20 nazar-gateway 2>/dev/null
  echo "=== Recent syncthing logs ===" && docker compose logs --tail 20 nazar-syncthing 2>/dev/null
} > /tmp/nazar-debug.txt 2>&1

cat /tmp/nazar-debug.txt
```
