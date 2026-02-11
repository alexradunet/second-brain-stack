# VPS Setup Cheatsheet

Quick reference for managing your Nazar Second Brain VPS after initial setup.

---

## Quick Connect

```bash
# Connect via Tailscale (recommended)
ssh debian@100.87.216.31

# Or use the Tailscale hostname
ssh debian@vps-672d3569
```

---

## Bash Aliases (Configured on VPS)

The following aliases are configured in `~/.nazar_aliases` and sourced from `~/.bashrc`:

### OpenClaw CLI Aliases

| Alias | Description |
|-------|-------------|
| `dopenclaw` | Run openclaw commands inside the container |
| `dclaw` | Shorthand for `dopenclaw` |
| `nazar-cli` | Alternative shorthand |

**Examples:**
```bash
# Check system health
dopenclaw doctor

# Fix auto-detected issues
dopenclaw doctor --fix

# Configure API keys and channels
dopenclaw configure

# List connected devices
dopenclaw devices list

# Approve a pending device
dopenclaw devices approve <request-id>
```

### Docker Compose Aliases

| Alias | Description |
|-------|-------------|
| `dnazar` or `dn` | Docker compose for Nazar stack |
| `dps` | Show container status |
| `dlogs` | Follow gateway logs |
| `drestart` | Restart the gateway container |
| `dstart` | Start the gateway container |
| `dstop` | Stop the gateway container |

**Examples:**
```bash
# Check status
dps

# View logs
dlogs

# Restart gateway
drestart

# Full compose commands
dnazar up -d
dnazar down
dnazar pull
dnazar build --no-cache
```

---

## Essential Commands

### Container Management

```bash
# View container status
docker compose -f /srv/nazar/deploy/docker-compose.yml ps

# View logs (last 50 lines)
docker compose -f /srv/nazar/deploy/docker-compose.yml logs --tail 50 openclaw-gateway

# Follow logs in real-time
docker compose -f /srv/nazar/deploy/docker-compose.yml logs -f openclaw-gateway

# Restart gateway
docker compose -f /srv/nazar/deploy/docker-compose.yml restart openclaw-gateway

# Shell into container
docker compose -f /srv/nazar/deploy/docker-compose.yml exec openclaw-gateway bash

# Update/rebuild after config changes
docker compose -f /srv/nazar/deploy/docker-compose.yml pull
docker compose -f /srv/nazar/deploy/docker-compose.yml up -d
```

### Vault Git Operations

```bash
# Check vault status
cd /srv/nazar/vault && git status

# View recent commits
cd /srv/nazar/vault && git log --oneline -10

# Manual sync (pull changes from bare repo)
cd /srv/nazar/vault && git pull origin main

# View sync log
tail -f /srv/nazar/data/git-sync.log

# Trigger auto-commit manually
/srv/nazar/scripts/vault-auto-commit.sh
```

### System Status

```bash
# Quick status check
echo "=== Tailscale ===" && tailscale status
echo "=== Docker ===" && docker compose -f /srv/nazar/deploy/docker-compose.yml ps
echo "=== Firewall ===" && sudo ufw status
echo "=== Fail2Ban ===" && sudo fail2ban-client status sshd
echo "=== Vault Git ===" && git -C /srv/nazar/vault log --oneline -3
echo "=== Sync Log ===" && tail -5 /srv/nazar/data/git-sync.log
```

---

## Device Pairing / Approval

When accessing the Control UI for the first time from a new browser/device:

1. **Open** `https://vps-claw.tail697e8f.ts.net/`
2. You'll see "pairing required" — this is normal
3. **SSH into VPS** and approve:

```bash
ssh debian@100.87.216.31

# Option 1: Using the alias (if device shows in pending)
dopenclaw devices list
dopenclaw devices approve <request-id>
drestart

# Option 2: Manual approval (if alias doesn't work)
sudo cat /srv/nazar/data/openclaw/devices/pending.json
# Copy the request ID, then:
sudo python3 << 'PYEOF'
import json
with open('/srv/nazar/data/openclaw/devices/pending.json', 'r') as f:
    pending = json.load(f)
with open('/srv/nazar/data/openclaw/devices/paired.json', 'r') as f:
    paired = json.load(f)
for device_id, device_info in pending.items():
    paired[device_id] = device_info
    print(f'Approved: {device_id}')
with open('/srv/nazar/data/openclaw/devices/paired.json', 'w') as f:
    json.dump(paired, f, indent=2)
with open('/srv/nazar/data/openclaw/devices/pending.json', 'w') as f:
    json.dump({}, f)
PYEOF
drestart
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `/srv/nazar/deploy/.env` | Environment variables, API tokens |
| `/srv/nazar/data/openclaw/openclaw.json` | OpenClaw agent configuration |
| `/srv/nazar/vault/99-system/openclaw/workspace/` | Agent personality, memory, tools |
| `~/.nazar_aliases` | Bash aliases for easy commands |

---

## Troubleshooting

### Gateway shows "pairing required"

See **Device Pairing** section above.

### Container won't start

```bash
# Check logs
docker compose -f /srv/nazar/deploy/docker-compose.yml logs openclaw-gateway

# Check config validity
cat /srv/nazar/data/openclaw/openclaw.json | jq .

# Fix config issues
dopenclaw doctor --fix
```

### Git sync not working

```bash
# Check permissions
ls -la /srv/nazar/vault.git/
ls -la /srv/nazar/vault/

# Fix permissions
sudo chown -R debian:vault /srv/nazar/vault /srv/nazar/vault.git
sudo find /srv/nazar/vault -type d -exec chmod 2775 {} +
sudo find /srv/nazar/vault -type f -exec chmod 664 {} +

# Check cron
crontab -l

# Manual sync test
cd /srv/nazar/vault && git push origin main
```

### Locked out of SSH

If Tailscale is down:
1. Use VPS provider's web console (OVH KVM, etc.)
2. Re-enable public SSH: `sudo ufw allow 22/tcp`
3. SSH via public IP: `ssh debian@51.38.141.38`
4. Fix Tailscale: `sudo tailscale up`
5. Re-lock: `sudo ufw delete allow 22/tcp`

---

## Security Audit

Run the built-in security audit:

```bash
sudo bash /srv/nazar/vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

Checks: root login disabled, SSH key-only, firewall active, Fail2Ban running, auto-updates enabled, Tailscale connected, no secrets in vault.

---

## Local Vault Clone (for Obsidian)

From your local machine:

```bash
# Clone vault
git clone debian@100.87.216.31:/srv/nazar/vault.git ~/nazar-vault

# Or if using Tailscale on local machine
git clone debian@100.87.216.31:/srv/nazar/vault.git ~/nazar-vault

# Change remote to Tailscale IP (if needed)
cd ~/nazar-vault
git remote set-url origin debian@100.87.216.31:/srv/nazar/vault.git
```

Then point Obsidian to `~/nazar-vault`.

---

## Important Paths Summary

```
/srv/nazar/
├── deploy/
│   ├── docker-compose.yml      # Container config
│   ├── .env                    # Secrets (tokens, API keys)
│   └── openclaw.json           # Agent defaults
├── vault/                      # Working copy (Obsidian vault)
├── vault.git/                  # Bare repo for sync
├── data/
│   ├── openclaw/              # Runtime config
│   │   ├── openclaw.json      # Active config
│   │   └── devices/           # Paired/pending devices
│   └── git-sync.log           # Sync log
├── scripts/
│   └── vault-auto-commit.sh   # Auto-commit script
└── .nazar_aliases             # Bash aliases (symlinked from ~)
```

---

*Last updated: 2026-02-11*
