# Troubleshooting

Common issues and how to fix them.

## Access Issues

### SSH host key verification failed after VPS reinstall

**Symptom:** When trying to SSH into your VPS, you see a scary warning like:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
```

Followed by: `Host key verification failed.`

**Cause:** When you reinstall your VPS (e.g., from the provider's control panel), the server gets a fresh OS installation with new SSH host keys. Your local SSH client remembers the *old* host key and warns you that it doesn't match — this is a security feature to protect against man-in-the-middle attacks.

**Fix:** Remove the old host key from your local `known_hosts` file:

```bash
# On Windows (PowerShell/Git Bash)
ssh-keygen -R 51.38.141.38

# On Linux/macOS
ssh-keygen -R <vps-ip-address>
```

Then reconnect and accept the new key:

```bash
ssh debian@51.38.141.38
# Type "yes" when prompted to confirm the new host key
```

**What this means:**
- SSH stores server fingerprints in `~/.ssh/known_hosts` to verify identity
- After a VPS reinstall, the server legitimately has a new identity
- The warning is expected and safe to bypass in this specific case
- The `-R` flag removes all entries for that host from `known_hosts`

---

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

### Locked out of SSH (Tailscale down)

**Symptom:** Can't SSH via Tailscale IP, Tailscale appears down on VPS.

**Fix:**
1. Use your VPS provider's web console (OVH KVM, Hetzner Console)
2. Log in as `debian`
3. Re-enable public SSH: `sudo ufw allow 22/tcp`
4. SSH in normally: `ssh debian@<public-ip>`
5. Fix Tailscale: `sudo tailscale up`
6. Verify Tailscale SSH: `ssh debian@<tailscale-ip>` (from another terminal)
7. Re-lock: `sudo bash lock-ssh-to-tailscale.sh`

### Can't reach gateway (container running)

**Symptom:** `https://<tailscale-hostname>/` not loading, but container is running.

**Check:**
```bash
# Is Tailscale running?
tailscale status

# Is the container running?
docker compose ps

# Is the gateway container using host networking?
docker inspect nazar-gateway --format='{{.HostConfig.NetworkMode}}'
# Expected: host
```

**Fix:** The gateway manages its own Tailscale Serve proxy. Restart the container:
```bash
docker compose restart nazar-gateway
```

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

### Container won't start

**Check logs:**
```bash
cd /srv/nazar
docker compose logs nazar-gateway
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
# Ensure vault group permissions are correct
sudo chown -R debian:vault /srv/nazar/vault
sudo find /srv/nazar/vault -type d -exec chmod 2775 {} +
sudo find /srv/nazar/vault -type f -exec chmod 0664 {} +
```

The container runs as uid 1000 — which must be a member of the `vault` group. The setgid bit on directories ensures new files inherit the group.

## Vault Sync Issues

### Git push rejected

**Symptom:** `git push` to VPS fails with "non-fast-forward" error.

**Cause:** The auto-commit cron on the VPS committed agent writes, creating commits your local branch doesn't have.

**Fix:**
```bash
# Pull first, then push
git pull --rebase origin main
git push origin main
```

### Merge conflicts after pull

**Symptom:** `git pull` shows merge conflicts.

**Cause:** Both you and the agent edited the same file in the same area.

**Fix:**
```bash
# See conflicted files
git status

# Resolve conflicts in your editor, then:
git add <resolved-files>
git commit
git push
```

### Agent writes not appearing

**Symptom:** The agent made changes to vault files but they don't show up when you `git pull`.

**Check:**
```bash
# On VPS: are there uncommitted changes?
git -C /srv/nazar/vault status

# Is the cron running?
crontab -u debian -l | grep vault-auto-commit

# Check the sync log
tail -20 /srv/nazar/data/git-sync.log
```

**Fix:** If the cron isn't running, reinstall it:
```bash
sudo bash /srv/nazar/deploy/scripts/setup-vps.sh
```

Or manually trigger:
```bash
sudo -u debian /srv/nazar/scripts/vault-auto-commit.sh
```

### Post-receive hook not updating working copy

**Symptom:** You pushed to `vault.git` but `/srv/nazar/vault/` doesn't reflect the changes.

**Check:**
```bash
# Check the sync log
tail -20 /srv/nazar/data/git-sync.log

# Is the hook executable?
ls -la /srv/nazar/vault.git/hooks/post-receive
```

**Fix:** Reinstall the hook:
```bash
sudo cp /srv/nazar/deploy/scripts/vault-post-receive-hook /srv/nazar/vault.git/hooks/post-receive
sudo chmod +x /srv/nazar/vault.git/hooks/post-receive
sudo chown debian:vault /srv/nazar/vault.git/hooks/post-receive
```

### Permission errors in vault

**Symptom:** Git operations fail with permission errors.

**Fix:**
```bash
# Ensure vault group ownership and setgid
sudo chown -R debian:vault /srv/nazar/vault /srv/nazar/vault.git
sudo find /srv/nazar/vault -type d -exec chmod 2775 {} +
sudo find /srv/nazar/vault.git -type d -exec chmod 2775 {} +

# Verify git shared repo config
git -C /srv/nazar/vault config core.sharedRepository group
```

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

API keys are managed by `openclaw configure`. To re-run configuration:

```bash
openclaw configure
```

To verify the container can reach the API:

```bash
openclaw doctor --fix
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
echo "=== Vault Git ===" && git -C /srv/nazar/vault log --oneline -3
echo "=== Sync Log ===" && tail -5 /srv/nazar/data/git-sync.log
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
  echo "=== Vault Git ===" && git -C /srv/nazar/vault log --oneline -5 2>/dev/null
  echo "=== Sync Log ===" && tail -10 /srv/nazar/data/git-sync.log 2>/dev/null
  echo "=== Recent gateway logs ===" && docker compose logs --tail 20 nazar-gateway 2>/dev/null
} > /tmp/nazar-debug.txt 2>&1

cat /tmp/nazar-debug.txt
```
