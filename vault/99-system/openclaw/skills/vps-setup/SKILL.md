---
name: vps-setup
description: Provision a fresh Debian 13 VPS with hardened security, Tailscale networking, Docker, and the Nazar (OpenClaw + Syncthing) stack. Designed to be read by Claude Code running on the VPS to walk the user through setup interactively.
---

# VPS Setup Skill

Interactive guide for Claude Code to provision a fresh Debian 13 VPS into a secure Nazar deployment host.

## Prerequisites

Before starting, confirm with the user:

1. **Fresh Debian 13 VPS** — OVH, Hetzner, or similar
2. **Root SSH access** — user can SSH in as root (initial setup)
3. **Tailscale account** — user has a Tailscale account at https://login.tailscale.com
4. **Deploy repo** — the `deploy/` git repo is available (locally or on a git remote)
5. **API keys ready** — Anthropic, Kimi, or other LLM provider keys

## Scripts

This skill includes automation scripts for each phase:

| Script | Purpose | Run as |
|--------|---------|--------|
| `scripts/provision-vps.sh` | **Master script** — runs ALL phases end-to-end | root |
| `scripts/secure-vps.sh` | Phases 1-5 only (user, SSH, firewall, fail2ban, auto-updates) | root |
| `scripts/install-tailscale.sh` | Install + authenticate Tailscale | root |
| `scripts/lock-ssh-to-tailscale.sh` | Remove public SSH, Tailscale-only access | root |
| `scripts/install-docker.sh` | Install Docker CE + Compose plugin | root |
| `scripts/audit-vps.sh` | Security + health check (read-only, safe to run anytime) | root |

### Quick Start (one command)

```bash
# Copy scripts to VPS, then:
sudo bash provision-vps.sh --deploy-repo /srv/nazar/deploy
```

### Step by Step (if you prefer control)

```bash
sudo bash secure-vps.sh           # Harden the server
sudo bash install-tailscale.sh    # Install + auth Tailscale
# Verify: ssh nazar@<tailscale-ip>
sudo bash lock-ssh-to-tailscale.sh  # Lock SSH to Tailscale
sudo bash install-docker.sh       # Install Docker
# Then deploy the stack with: /srv/nazar/deploy/scripts/setup-vps.sh
sudo bash audit-vps.sh            # Verify everything
```

## Execution Order (Manual Reference)

Run these phases in order. Each phase has a verification step — do not proceed until it passes.

---

## Phase 1: Create a Non-Root User

**Why:** Running services as root is dangerous. Create a dedicated user for all operations.

```bash
# Create user with home directory
adduser --disabled-password --gecos "Nazar Service" nazar

# Add to sudo group
usermod -aG sudo nazar

# Allow passwordless sudo (for automation)
echo "nazar ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nazar
chmod 0440 /etc/sudoers.d/nazar

# Copy root's authorized_keys to the new user
mkdir -p /home/nazar/.ssh
cp /root/.ssh/authorized_keys /home/nazar/.ssh/authorized_keys
chown -R nazar:nazar /home/nazar/.ssh
chmod 700 /home/nazar/.ssh
chmod 600 /home/nazar/.ssh/authorized_keys
```

**Verify:**
```bash
su - nazar -c "sudo whoami"
# Expected: root
```

**Ask the user:** "Can you SSH into the VPS as the `nazar` user? Try: `ssh nazar@<vps-ip>`"

**Important:** After setup is complete, only the `nazar` user should be used for SSH access. The default cloud provider user (e.g., `debian` on OVH/Hetzner) should not be used. The SSH hardening in Phase 2 sets `AllowUsers nazar`, which prevents login as any other user.

---

## Phase 2: Harden SSH

**Why:** Disable password auth and root login. SSH keys only.

```bash
# Backup original config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Apply hardened settings
sudo tee /etc/ssh/sshd_config.d/hardened.conf > /dev/null << 'EOF'
# Disable root login
PermitRootLogin no

# Disable password authentication (keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Limit authentication attempts
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30

# Disable unused auth methods
KbdInteractiveAuthentication no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding yes  # Required for VSCode Remote SSH

# Only allow the nazar user
AllowUsers nazar
EOF

# Validate config before restarting
sudo sshd -t
```

**CRITICAL:** Before restarting SSH, confirm the user can log in as `nazar` with their SSH key. If they can't, they'll be locked out.

```bash
# Only after user confirms they can SSH as nazar:
sudo systemctl restart sshd
```

**Verify:**
```bash
# From user's machine (new terminal):
ssh nazar@<vps-ip>
# Should work with key, password should be rejected
```

---

## Phase 3: Firewall (UFW)

**Why:** Block everything except what we need. Tailscale will handle internal access.

```bash
sudo apt-get update && sudo apt-get install -y ufw

# Default: deny incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (keep this until Tailscale is confirmed working)
sudo ufw allow 22/tcp comment "SSH"

# Allow Syncthing sync (needed for device discovery and transfer)
sudo ufw allow 22000/tcp comment "Syncthing-TCP"
sudo ufw allow 22000/udp comment "Syncthing-UDP"
sudo ufw allow 21027/udp comment "Syncthing-Discovery"

# Enable firewall
sudo ufw --force enable
```

**Note:** The gateway uses host networking with loopback binding (exposed automatically via integrated Tailscale Serve). Port 8384 (Syncthing UI) is NOT opened in UFW — it's bound to 127.0.0.1 and accessed via manual `tailscale serve` proxy.

**Verify:**
```bash
sudo ufw status verbose
# Should show: 22/tcp, 22000/tcp, 22000/udp, 21027/udp ALLOW
```

---

## Phase 4: Install Fail2Ban

**Why:** Auto-ban IPs that brute-force SSH.

```bash
sudo apt-get install -y fail2ban

sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port = ssh
backend = systemd
maxretry = 3
bantime = 3600
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

**Verify:**
```bash
sudo fail2ban-client status sshd
# Should show: Currently failed: 0, Currently banned: 0
```

---

## Phase 5: Automatic Security Updates

**Why:** Kernel and package vulnerabilities get patched without manual intervention.

```bash
sudo apt-get install -y unattended-upgrades apt-listchanges

sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

sudo systemctl enable unattended-upgrades
sudo systemctl restart unattended-upgrades
```

**Verify:**
```bash
sudo unattended-upgrades --dry-run --debug 2>&1 | head -5
# Should run without errors
```

---

## Phase 6: Install Tailscale

**Why:** Zero-config VPN. All internal services are only accessible via Tailscale IPs (100.x.x.x). No ports exposed to the public internet except SSH and Syncthing sync.

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Start Tailscale — this prints an auth URL
sudo tailscale up
```

**Ask the user:** "Tailscale printed an auth URL. Open it in your browser to authorize this device."

After authorization:

```bash
# Get Tailscale IP
tailscale ip -4
# Note this IP — it's how you'll access gateway and syncthing UI
```

### Lock down SSH to Tailscale only (optional but recommended)

Once Tailscale is confirmed working:

```bash
# Remove public SSH, add Tailscale-only SSH
sudo ufw delete allow 22/tcp
sudo ufw allow in on tailscale0 to any port 22 comment "SSH-via-Tailscale"
sudo ufw reload
```

**CRITICAL:** Before doing this, confirm the user can SSH via the Tailscale IP:
```bash
# From user's machine (must have Tailscale running):
ssh nazar@<tailscale-ip>
```

**Verify:**
```bash
tailscale status
# Should show: this machine + user's other devices
sudo ufw status
# SSH should only be on tailscale0 interface
```

---

## Phase 7: Install Docker

**Why:** Containers isolate the OpenClaw gateway and Syncthing from the host.

```bash
# Install Docker from official repo
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add nazar user to docker group (no sudo needed for docker commands)
sudo usermod -aG docker nazar
```

**Important:** The user must log out and back in for the docker group to take effect.

**Note:** The provisioning script also adds an `openclaw` CLI alias to `/home/nazar/.bashrc`:
```bash
alias openclaw="sudo docker exec -it nazar-gateway node dist/index.js"
```
This allows running OpenClaw commands directly (e.g., `openclaw configure`, `openclaw devices list`) without typing the full `docker exec` command.

```bash
# Log out and back in, then verify:
exit
# SSH back in
ssh nazar@<tailscale-ip>
```

**Verify:**
```bash
docker run --rm hello-world
# Should print: Hello from Docker!
docker compose version
# Should print: Docker Compose version v2.x.x
```

---

## Phase 8: Expose Syncthing UI via Tailscale

**Why:** The Syncthing UI is bound to `127.0.0.1` in Docker (not exposed publicly). Tailscale traffic arrives on the `tailscale0` interface, not loopback, so it can't reach `127.0.0.1`-bound ports directly. `tailscale serve` proxies tailnet traffic to localhost.

**Note:** The gateway does NOT need manual `tailscale serve` setup. It uses integrated Tailscale Serve mode (`tailscale: { mode: "serve" }` in docker-compose) and manages its own proxy automatically, exposing the gateway at `https://<tailscale-hostname>/`.

```bash
# Proxy Syncthing UI (port 8384) — only manual proxy needed
sudo tailscale serve --bg --tcp 8384 tcp://127.0.0.1:8384
```

**Verify:**
```bash
tailscale serve status
# Should show Syncthing UI proxy active for 8384

# From another device on the tailnet:
# https://<tailscale-hostname>/  — Gateway (automatic, HTTPS)
# http://<tailscale-ip>:8384     — Syncthing UI (manual proxy)
```

**Note:** The Syncthing UI proxy persists across reboots as long as Tailscale is running. Only devices on your tailnet can access it.

---

## Phase 9: Deploy the Nazar Stack

**Why:** This is what we're here for — get OpenClaw + Syncthing running.

**Note:** The docker-compose uses `network_mode: host` for the gateway container and includes integrated Tailscale Serve mode. The Tailscale CLI is included in the Dockerfile. The gateway binds to loopback and is automatically exposed at `https://<tailscale-hostname>/` via Tailscale Serve.

### Option A: Push deploy repo from local machine

From the user's local machine:
```bash
scp -r C:\Second_Brain\deploy\ nazar@<tailscale-ip>:/srv/nazar/deploy/
```

### Option B: Clone from git remote

If the deploy repo has been pushed to GitHub/GitLab:
```bash
sudo mkdir -p /srv/nazar
sudo chown nazar:nazar /srv/nazar
git clone <repo-url> /srv/nazar/deploy
```

### Run the setup script

```bash
sudo bash /srv/nazar/deploy/scripts/setup-vps.sh
```

This creates:
- `/srv/nazar/vault/` — empty, will be populated by Syncthing
- `/srv/nazar/data/openclaw/` — OpenClaw config + state
- `/srv/nazar/data/syncthing/` — Syncthing config
- `/srv/nazar/.env` — secrets file with auto-generated gateway token

### Configure secrets

```bash
nano /srv/nazar/.env
```

The user needs to fill in:
- `ANTHROPIC_API_KEY` — their Anthropic API key
- `KIMI_API_KEY` — their Kimi API key (if using)
- `WHATSAPP_NUMBER` — their WhatsApp number

### Restart with secrets

```bash
cd /srv/nazar
docker compose restart
```

**Verify:**
```bash
docker compose ps
# Both containers should be "healthy" or "running"

curl -sk https://vps-claw.tail697e8f.ts.net/
# Gateway should respond (via integrated Tailscale Serve)

curl -s http://127.0.0.1:8384
# Syncthing UI should respond

docker compose exec nazar-gateway ls /vault/
# Should show vault folders (empty until Syncthing syncs)
```

### Device pairing (first browser access)

The first time a browser connects to the Control UI at `https://<tailscale-hostname>/`, the gateway requires device pairing. Approve it from the CLI:

```bash
openclaw devices list              # List pending pairing requests
openclaw devices approve <request-id>   # Approve the device
```

### Run onboarding

After deployment and device pairing, run the interactive setup wizard:

```bash
openclaw configure
```

This walks through WhatsApp linking, model configuration, and other initial settings.

---

## Phase 10: Connect Syncthing

**Why:** Sync the Obsidian vault from user's devices to the VPS.

1. Access Syncthing UI: `http://<tailscale-ip>:8384`
2. Get the VPS Device ID from the UI
3. On the user's laptop/phone Syncthing:
   - Add the VPS as a remote device (paste Device ID)
   - Share the vault folder with the VPS device
   - Set the folder path on VPS to `/var/syncthing/vault` (maps to `/srv/nazar/vault` on host)
4. Accept the share on the VPS Syncthing UI

**Verify:**
```bash
# After sync completes:
ls /srv/nazar/vault/
# Should show: 00-inbox, 01-daily-journey, ..., 99-system
```

---

## Phase 11: Final Security Audit

Run through this checklist:

```bash
# 1. No root SSH
grep "PermitRootLogin" /etc/ssh/sshd_config.d/hardened.conf
# Expected: PermitRootLogin no

# 2. No password auth
grep "PasswordAuthentication" /etc/ssh/sshd_config.d/hardened.conf
# Expected: PasswordAuthentication no

# 3. Firewall active
sudo ufw status
# Expected: active, only SSH(tailscale), 22000, 21027

# 4. Fail2ban running
sudo fail2ban-client status
# Expected: Number of jail: 1 (sshd)

# 5. Auto-updates enabled
systemctl is-enabled unattended-upgrades
# Expected: enabled

# 6. Tailscale connected
tailscale status
# Expected: shows connected devices

# 7. Docker containers healthy
cd /srv/nazar && docker compose ps
# Expected: both containers running/healthy

# 8. Gateway using host network with loopback binding
docker inspect nazar-gateway --format='{{.HostConfig.NetworkMode}}'
# Expected: host (gateway manages its own Tailscale Serve proxy)

# 9. Syncthing UI not exposed publicly
ss -tlnp | grep 8384
# Expected: 127.0.0.1:8384 (not 0.0.0.0)

# 10. No secrets in vault
grep -r "sk-ant\|sk-" /srv/nazar/vault/ 2>/dev/null | head -5
# Expected: no output (no API keys in vault files)
```

---

## Troubleshooting

### Locked out of SSH
If SSH is locked to Tailscale and Tailscale goes down:
- Use VPS provider's web console (OVH: KVM, Hetzner: Console)
- Re-enable public SSH: `sudo ufw allow 22/tcp`

### Docker build fails (out of memory)
Small VPS may need swap:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Syncthing can't connect
Check firewall allows 22000 and 21027:
```bash
sudo ufw status | grep -E "22000|21027"
```

### Container can't write to vault
Fix permissions:
```bash
sudo chown -R 1000:1000 /srv/nazar/vault /srv/nazar/data
```

---

## Quick Reference

| Service | Access | URL |
|---------|--------|-----|
| SSH | Tailscale | `ssh nazar@<tailscale-ip>` |
| Gateway | Tailscale (automatic) | `https://<tailscale-hostname>/` |
| Syncthing UI | Tailscale (manual proxy) | `http://<tailscale-ip>:8384` |
| Syncthing sync | Public | Ports 22000, 21027 |

| Path | Contents |
|------|----------|
| `/srv/nazar/vault/` | Obsidian vault (synced) |
| `/srv/nazar/data/openclaw/` | OpenClaw config + state |
| `/srv/nazar/data/syncthing/` | Syncthing config |
| `/srv/nazar/.env` | Secrets (API keys, tokens) |
| `/srv/nazar/deploy/` | Deployment repo |
| `/opt/openclaw/` | OpenClaw source (for Docker build) |

| Alias | Command | Purpose |
|-------|---------|---------|
| `openclaw` | `sudo docker exec -it nazar-gateway node dist/index.js` | OpenClaw CLI (added to `~/.bashrc` during provisioning) |
