---
name: vps-setup
description: Provision a fresh Debian 13 VPS with hardened security, Tailscale networking, Docker, and the Nazar (OpenClaw + Git vault sync) stack. Designed to be read by Claude Code running on the VPS to walk the user through setup interactively.
---

# VPS Setup Skill

Interactive guide for Claude Code to provision a fresh Debian 13 VPS into a secure Nazar deployment host.

## Prerequisites

Before starting, confirm with the user:

1. **Fresh Debian 13 VPS** — OVH, Hetzner, or similar
2. **Root SSH access** — user can SSH in as root (initial setup)
3. **Tailscale account** — user has a Tailscale account at https://login.tailscale.com
4. **Deploy repo** — the `deploy/` git repo is available (locally or on a git remote)
5. **API keys ready** — Anthropic, Kimi, or other LLM provider keys (entered during `openclaw configure`)

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
# Verify: ssh debian@<tailscale-ip>
sudo bash lock-ssh-to-tailscale.sh  # Lock SSH to Tailscale
sudo bash install-docker.sh       # Install Docker
# Then deploy the stack with: /srv/nazar/deploy/scripts/setup-vps.sh
sudo bash audit-vps.sh            # Verify everything
```

## Execution Order (Manual Reference)

Run these phases in order. Each phase has a verification step — do not proceed until it passes.

---

## Phase 1: Verify Default User

**Why:** Running services as root is dangerous. Use the cloud provider's default `debian` user.

```bash
# Verify debian user exists and can sudo
su - debian -c "sudo whoami"
# Expected: root

# If debian doesn't have passwordless sudo:
echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian
chmod 0440 /etc/sudoers.d/debian
```

**Verify:**
```bash
su - debian -c "sudo whoami"
# Expected: root
```

**Ask the user:** "Can you SSH into the VPS as the `debian` user? Try: `ssh debian@<vps-ip>`"

**Important:** After setup is complete, only the `debian` user should be used for SSH access. The SSH hardening in Phase 2 sets `AllowUsers debian`, which prevents login as any other user (including root).

---

## Phase 2: Harden SSH

**Why:** Disable password auth and root login. SSH keys only.

```bash
# Backup original config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Apply hardened settings
sudo tee /etc/ssh/sshd_config.d/nazar.conf > /dev/null << 'EOF'
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

# Only allow the debian user
AllowUsers debian
EOF

# Validate config before restarting
sudo sshd -t
```

**CRITICAL:** Before restarting SSH, confirm the user can log in as `debian` with their SSH key. If they can't, they'll be locked out.

```bash
# Only after user confirms they can SSH as debian:
sudo systemctl restart sshd
```

**Verify:**
```bash
# From user's machine (new terminal):
ssh debian@<vps-ip>
# Should work with key, password should be rejected
```

---

## Phase 3: Firewall (UFW)

**Why:** Block everything except what we need. Tailscale will handle internal access. No public ports needed — vault sync uses Git over SSH through Tailscale.

```bash
sudo apt-get update && sudo apt-get install -y ufw

# Default: deny incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (keep this until Tailscale is confirmed working)
sudo ufw allow 22/tcp comment "SSH"

# Enable firewall
sudo ufw --force enable
```

**Note:** No Syncthing ports needed. Vault sync uses Git over SSH (through Tailscale). The gateway uses host networking with loopback binding, exposed automatically via integrated Tailscale Serve.

**Verify:**
```bash
sudo ufw status verbose
# Should show: 22/tcp ALLOW (only SSH, nothing else)
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

**Why:** Zero-config VPN. All internal services are only accessible via Tailscale IPs (100.x.x.x). No ports exposed to the public internet.

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
# Note this IP — it's how you'll access gateway and vault git repo
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
ssh debian@<tailscale-ip>
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

**Why:** Container isolates the OpenClaw gateway from the host.

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

# Add debian user to docker group (no sudo needed for docker commands)
sudo usermod -aG docker debian
```

**Important:** The user must log out and back in for the docker group to take effect.

**Note:** The provisioning script also adds an `openclaw` CLI alias to `/home/debian/.bashrc`:
```bash
alias openclaw="sudo docker exec -it nazar-gateway node dist/index.js"
```
This allows running OpenClaw commands directly (e.g., `openclaw configure`, `openclaw devices list`) without typing the full `docker exec` command.

```bash
# Log out and back in, then verify:
exit
# SSH back in
ssh debian@<tailscale-ip>
```

**Verify:**
```bash
docker run --rm hello-world
# Should print: Hello from Docker!
docker compose version
# Should print: Docker Compose version v2.x.x
```

---

## Phase 8: Deploy the Nazar Stack

**Why:** This is what we're here for — get OpenClaw running with Git-based vault sync.

**Note:** The docker-compose uses `network_mode: host` for the gateway container and includes integrated Tailscale Serve mode. The Tailscale CLI is included in the Dockerfile. The gateway binds to loopback and is automatically exposed at `https://<tailscale-hostname>/` via Tailscale Serve.

### Option A: Push deploy repo from local machine

From the user's local machine:
```bash
scp -r C:\Second_Brain\deploy\ debian@<tailscale-ip>:/srv/nazar/deploy/
```

### Option B: Clone from git remote

If the deploy repo has been pushed to GitHub/GitLab:
```bash
sudo mkdir -p /srv/nazar
sudo chown debian:debian /srv/nazar
git clone <repo-url> /srv/nazar/deploy
```

### Run the setup script

```bash
sudo bash /srv/nazar/deploy/scripts/setup-vps.sh
```

This creates:
- `/srv/nazar/vault/` — git working copy (empty initially, or with initial commit)
- `/srv/nazar/vault.git/` — bare Git repo with post-receive hook
- `/srv/nazar/data/openclaw/` — OpenClaw config + state
- `/srv/nazar/scripts/vault-auto-commit.sh` — cron script for agent writes
- `/srv/nazar/.env` — secrets file with auto-generated gateway token
- `vault` group with debian user
- Cron job: auto-commit every 5 minutes

### Configure models, API keys, and channels

```bash
openclaw configure
```

This interactive wizard walks through model selection, API key entry, and channel setup (WhatsApp, etc.). No manual `.env` editing needed.

**Verify:**
```bash
docker compose ps
# Gateway should be "healthy" or "running"

curl -sk https://<tailscale-hostname>/
# Gateway should respond (via integrated Tailscale Serve)

docker compose exec nazar-gateway ls /vault/
# Should show vault folders (empty until you push content)

# Check git sync infrastructure
git -C /srv/nazar/vault log --oneline -3
ls /srv/nazar/vault.git/hooks/post-receive
crontab -u debian -l | grep vault-auto-commit
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

## Phase 9: Connect Your Devices (Vault Sync)

**Why:** Sync the Obsidian vault from user's devices to the VPS using Git.

### Laptop Setup

```bash
# Clone the vault over Tailscale SSH
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/vault

# Open in Obsidian, install Obsidian Git plugin
# Configure: auto-pull 5 min, auto-push after commit, auto-commit 5 min
```

### Phone Setup (Android)

1. Install Obsidian + Obsidian Git plugin
2. Configure repository URL: `debian@<tailscale-ip>:/srv/nazar/vault.git`
3. Requires Tailscale running on the phone
4. Set auto-pull and auto-push intervals

### Phone Setup (iOS)

1. Install Obsidian + Obsidian Git plugin, or
2. Use Working Copy app to clone, then open in Obsidian via Files

### First-time sync (vault already on laptop)

If you already have a vault locally:

```bash
cd ~/vault
git init
git remote add origin debian@<tailscale-ip>:/srv/nazar/vault.git
git add -A
git commit -m "initial vault"
git push -u origin main
```

**Verify:**
```bash
# After push:
ssh debian@<tailscale-ip> "ls /srv/nazar/vault/"
# Should show: 00-inbox, 01-daily-journey, ..., 99-system
```

---

## Phase 10: Final Security Audit

Run through this checklist:

```bash
# 1. No root SSH
grep "PermitRootLogin" /etc/ssh/sshd_config.d/nazar.conf
# Expected: PermitRootLogin no

# 2. No password auth
grep "PasswordAuthentication" /etc/ssh/sshd_config.d/nazar.conf
# Expected: PasswordAuthentication no

# 3. Firewall active
sudo ufw status
# Expected: active, only SSH on tailscale0

# 4. Fail2ban running
sudo fail2ban-client status
# Expected: Number of jail: 1 (sshd)

# 5. Auto-updates enabled
systemctl is-enabled unattended-upgrades
# Expected: enabled

# 6. Tailscale connected
tailscale status
# Expected: shows connected devices

# 7. Docker container healthy
cd /srv/nazar && docker compose ps
# Expected: gateway running/healthy

# 8. Gateway using host network with loopback binding
docker inspect nazar-gateway --format='{{.HostConfig.NetworkMode}}'
# Expected: host

# 9. Vault git sync working
git -C /srv/nazar/vault log --oneline -3
# Expected: shows commits
ls /srv/nazar/vault.git/hooks/post-receive
# Expected: exists and is executable
crontab -u debian -l | grep vault-auto-commit
# Expected: shows cron entry

# 10. No secrets in vault
grep -r "sk-ant\|sk-" /srv/nazar/vault/ 2>/dev/null | head -5
# Expected: no output (no API keys in vault files)

# 11. No legacy Syncthing ports
sudo ufw status | grep -E "22000|21027"
# Expected: no output (ports closed)
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

### Git push rejected
The auto-commit cron may have committed agent writes. Pull first:
```bash
git pull --rebase origin main
git push
```

### Container can't write to vault
Fix permissions:
```bash
sudo chown -R debian:vault /srv/nazar/vault
sudo find /srv/nazar/vault -type d -exec chmod 2775 {} +
sudo find /srv/nazar/vault -type f -exec chmod 0664 {} +
```

---

## Quick Reference

| Service | Access | URL |
|---------|--------|-----|
| SSH | Tailscale | `ssh debian@<tailscale-ip>` |
| Gateway | Tailscale (automatic) | `https://<tailscale-hostname>/` |
| Vault (git) | Tailscale (SSH) | `git clone debian@<tailscale-ip>:/srv/nazar/vault.git` |

| Path | Contents |
|------|----------|
| `/srv/nazar/vault/` | Obsidian vault (git working copy) |
| `/srv/nazar/vault.git/` | Bare Git repo (push/pull target) |
| `/srv/nazar/data/openclaw/` | OpenClaw config + state |
| `/srv/nazar/scripts/` | Auto-commit cron script |
| `/srv/nazar/.env` | Secrets (API keys, tokens) |
| `/srv/nazar/deploy/` | Deployment repo |
| `/opt/openclaw/` | OpenClaw source (for Docker build) |

| Alias | Command | Purpose |
|-------|---------|---------|
| `openclaw` | `sudo docker exec -it nazar-gateway node dist/index.js` | OpenClaw CLI (added to `~/.bashrc` during provisioning) |
