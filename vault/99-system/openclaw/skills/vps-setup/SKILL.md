---
name: vps-setup
description: Provision a fresh OVHcloud Debian 13 VPS with hardened security, Tailscale networking, and the Nazar (OpenClaw + Syncthing vault sync) stack. Designed to be read by Claude Code running on the VPS to walk the user through setup interactively.
---

# VPS Setup Skill

Interactive guide for Claude Code to provision a fresh OVHcloud Debian 13 VPS into a secure Nazar deployment host.

## Prerequisites

Before starting, confirm with the user:

1. **Fresh OVHcloud Debian 13 VPS** — ordered from the OVHcloud control panel
2. **Root SSH access** — user can SSH in as root (initial setup)
3. **Tailscale account** — user has a Tailscale account at https://login.tailscale.com
4. **Repository** — the `easy-para-system-claw-vps` repo is available (locally or on a git remote)
5. **API keys ready** — Anthropic, Kimi, or other LLM provider keys (entered during `openclaw configure`)

## Scripts

This skill includes automation scripts for each phase:

| Script | Purpose | Run as |
|--------|---------|--------|
| `scripts/secure-vps.sh` | Phases 1-5 only (user, SSH, firewall, fail2ban, auto-updates) | root |
| `scripts/install-tailscale.sh` | Install + authenticate Tailscale | root |
| `scripts/lock-ssh-to-tailscale.sh` | Remove public SSH, Tailscale-only access | root |
| `scripts/audit-vps.sh` | Security + health check (read-only, safe to run anytime) | root |

The recommended path is to use the **Docker setup script** which handles service installation end-to-end.

### Quick Start (one command)

```bash
# On VPS as debian user:
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

### Step by Step (if you prefer control)

```bash
sudo bash secure-vps.sh           # Harden the server (Phases 1-5)
sudo bash install-tailscale.sh    # Install + auth Tailscale (Phase 6)
# Verify: ssh debian@<tailscale-ip>
sudo bash lock-ssh-to-tailscale.sh  # Lock SSH to Tailscale
sudo bash audit-vps.sh            # Verify security
# Then run Docker setup for service deployment (Phase 7)
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

**Why:** Block everything except what we need. Tailscale will handle internal access. No public ports needed — vault sync uses Syncthing over Tailscale.

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

**Note:** No Syncthing ports needed in UFW. Syncthing communicates through the Tailscale mesh network. The gateway binds to loopback and is exposed via Tailscale Serve.

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
# Note this IP — it's how you'll access the gateway and Syncthing
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

## Phase 7: Deploy Services (Docker)

**Why:** Install Docker and deploy OpenClaw + Syncthing in containers with a shared vault volume. No separate service user needed — Docker provides isolation.

### Option A: One-line setup (recommended)

```bash
# As debian user:
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

### Option B: Clone and run

```bash
su - debian
git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar-deploy
cd ~/nazar-deploy/docker
bash setup.sh
```

The setup script:
- Installs Docker and Docker Compose (if not present)
- Creates directory structure (`~/nazar/vault`, `~/nazar/.openclaw`, `~/nazar/syncthing`)
- Generates `openclaw.json` with a secure gateway token
- Builds the OpenClaw container image
- Starts OpenClaw + Syncthing containers
- Optionally runs security hardening (`setup-security.sh`)

**Verify:**
```bash
cd ~/nazar/docker

# Check containers are running
docker compose ps
# Expected: nazar-openclaw and nazar-syncthing both "Up"

# Check OpenClaw health
docker compose exec openclaw openclaw health

# Check vault directory
ls ~/nazar/vault/
# Should show: 00-inbox, 01-daily-journey, ..., 99-system
```

---

## Phase 8: Post-Infrastructure Setup

Infrastructure provisioning is complete. The user now configures the services through their own UIs:

1. **Syncthing** — Open the Syncthing GUI (via SSH tunnel at `http://localhost:8384`), add devices, and share the vault folder (`/var/syncthing/vault` inside container)
2. **OpenClaw** — Run the onboarding wizard: `docker compose exec -it openclaw openclaw configure`

These steps are handled by each service's own onboarding flow and are outside the scope of this infrastructure skill.

---

## Phase 9: Final Security Audit

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
# Expected: active, only SSH (or SSH on tailscale0 if locked down)

# 4. Fail2ban running
sudo fail2ban-client status
# Expected: Number of jail: 1 (sshd)

# 5. Auto-updates enabled
systemctl is-enabled unattended-upgrades
# Expected: enabled

# 6. Tailscale connected (if using Tailscale mode)
tailscale status
# Expected: shows connected devices

# 7. Docker containers running
cd ~/nazar/docker && docker compose ps
# Expected: nazar-openclaw and nazar-syncthing both "Up"

# 8. OpenClaw healthy
docker compose exec openclaw openclaw health

# 9. Vault syncing
docker compose exec syncthing syncthing cli show connections
# Expected: shows connected devices

# 10. No secrets in vault
grep -r "sk-ant\|sk-" ~/nazar/vault/ 2>/dev/null | head -5
# Expected: no output (no API keys in vault files)

# 11. Config has no placeholder tokens
grep -E "GENERATE_NEW_TOKEN|GENERATE_SECURE_TOKEN|CHANGE_ME" ~/nazar/.openclaw/openclaw.json
# Expected: no output (token has been generated)
```

Or run the security audit:

```bash
sudo nazar-security-audit
```

---

## Troubleshooting

### Locked out of SSH
If SSH is locked to Tailscale and Tailscale goes down:
- Use OVHcloud KVM console (control panel → your VPS → KVM)
- Re-enable public SSH: `sudo ufw allow 22/tcp`

### Containers not starting
```bash
cd ~/nazar/docker

# Check logs
docker compose logs

# Check disk space
df -h

# Fix permissions
chown -R 1000:1000 ~/nazar

# Rebuild and restart
docker compose down
docker compose up -d --build
```

### Syncthing not syncing
```bash
cd ~/nazar/docker

# Check connections
docker compose exec syncthing syncthing cli show connections

# Check folder errors
docker compose exec syncthing syncthing cli show folders

# Restart Syncthing
docker compose restart syncthing
```

### OpenClaw config issues
```bash
cd ~/nazar/docker

# Check config
docker compose exec openclaw cat /home/node/.openclaw/openclaw.json | jq .

# Reconfigure
docker compose exec -it openclaw openclaw configure
```

### Out of memory (small VPS)
Add swap:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Quick Reference

| Service | Access | URL |
|---------|--------|-----|
| SSH | Direct or Tailscale | `ssh debian@<vps-ip>` |
| Gateway | SSH tunnel | `http://localhost:18789` (via `ssh -L 18789:localhost:18789`) |
| Syncthing GUI | SSH tunnel | `http://localhost:8384` (via `ssh -L 8384:localhost:8384`) |

| Path (Host) | Path (Container) | Contents |
|------|------------------|----------|
| `~/nazar/vault/` | `/vault` (OpenClaw), `/var/syncthing/vault` (Syncthing) | Obsidian vault |
| `~/nazar/.openclaw/` | `/home/node/.openclaw/` | OpenClaw config + devices |
| `~/nazar/.openclaw/workspace/` | `/home/node/.openclaw/workspace/` | Agent workspace |
| `~/nazar/syncthing/config/` | `/var/syncthing/config/` | Syncthing database |

| Command | Purpose |
|---------|---------|
| `nazar-cli status` | Show container status and resource usage |
| `nazar-cli logs` | View service logs |
| `nazar-cli restart` | Restart all containers |
| `nazar-cli backup` | Create backup of vault and configs |
| `nazar-cli token` | Show gateway token |
| `nazar-cli tunnel` | Show SSH tunnel command |
| `nazar-cli syncthing-id` | Show Syncthing Device ID |
