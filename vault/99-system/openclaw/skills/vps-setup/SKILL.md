---
name: vps-setup
description: Provision a fresh Debian 13 VPS with hardened security, Tailscale networking, and the Nazar (OpenClaw + Syncthing vault sync) stack. Designed to be read by Claude Code running on the VPS to walk the user through setup interactively.
---

# VPS Setup Skill

Interactive guide for Claude Code to provision a fresh Debian 13 VPS into a secure Nazar deployment host.

## Prerequisites

Before starting, confirm with the user:

1. **Fresh Debian 13 VPS** — OVH, Hetzner, or similar
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

The recommended path is to use the **bootstrap script** (`bootstrap/bootstrap.sh`) which runs all phases end-to-end.

### Quick Start (one command)

```bash
# On VPS as root:
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | sudo bash
```

### Step by Step (if you prefer control)

```bash
sudo bash secure-vps.sh           # Harden the server
sudo bash install-tailscale.sh    # Install + auth Tailscale
# Verify: ssh debian@<tailscale-ip>
sudo bash lock-ssh-to-tailscale.sh  # Lock SSH to Tailscale
# Then run bootstrap.sh for service setup
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

## Phase 7: Run Bootstrap (Install Services)

**Why:** This sets up the `nazar` service user, installs Node.js, OpenClaw, Syncthing, and creates systemd services.

### Option A: One-line bootstrap (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | sudo bash
```

### Option B: Clone and run

```bash
su - debian
git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar
cd ~/nazar
sudo bash bootstrap/bootstrap.sh
```

The bootstrap script:
- Creates `nazar` service user (no sudo, locked password)
- Installs Node.js 22, OpenClaw, Syncthing
- Hardens SSH (if not already done)
- Configures UFW, Fail2Ban, auto-updates
- Creates systemd user services (`openclaw.service`, `syncthing.service`)
- Generates a secure gateway token
- Installs voice tools (Whisper, Piper)
- Creates helper scripts in `/home/debian/bin/`

**Verify:**
```bash
# Check nazar user exists
id nazar
# Expected: uid=...(nazar) gid=...(nazar) groups=...(nazar)

# Check services exist
ls /etc/systemd/user/openclaw.service /etc/systemd/user/syncthing.service
# Both should exist

# Check OpenClaw config
ls /home/nazar/.openclaw/openclaw.json
# Should exist with no placeholder tokens
```

---

## Phase 8: Deploy Vault and Start Services

**Why:** Get the vault content onto the VPS and start OpenClaw + Syncthing.

### Copy vault content

```bash
# As debian user
sudo cp -r ~/nazar/vault/* /home/nazar/vault/
sudo chown -R nazar:nazar /home/nazar/vault
```

### Start Syncthing

```bash
sudo bash ~/nazar/nazar/scripts/setup-syncthing.sh
```

### Start OpenClaw

```bash
sudo bash ~/nazar/nazar/scripts/setup-openclaw.sh
```

### Configure OpenClaw

```bash
sudo -u nazar openclaw configure
```

This interactive wizard walks through model selection, API key entry, and channel setup (WhatsApp, etc.).

**Verify:**
```bash
# Services running
sudo -u nazar systemctl --user status openclaw
sudo -u nazar systemctl --user status syncthing
# Both should be "active (running)"

# Gateway responds
curl -sk https://<tailscale-hostname>/
# Should get a response

# Vault has content
ls /home/nazar/vault/
# Should show: 00-inbox, 01-daily-journey, ..., 99-system
```

### Device pairing (first browser access)

The first time a browser connects to the Control UI at `https://<tailscale-hostname>/`, the gateway requires device pairing. Approve it from the CLI:

```bash
sudo -u nazar openclaw devices list              # List pending pairing requests
sudo -u nazar openclaw devices approve <request-id>   # Approve the device
```

---

## Phase 9: Connect Your Devices (Vault Sync)

**Why:** Sync the Obsidian vault across all your devices using Syncthing.

### Get VPS Syncthing device ID

```bash
sudo -u nazar syncthing cli show system | grep myID
```

### Laptop Setup

1. Install Syncthing on your laptop
2. Add the VPS device (paste the device ID from above)
3. Share the vault folder
4. Open the vault in Obsidian — changes sync in real-time

### Phone Setup (Android)

1. Install the Syncthing app from Play Store
2. Add the VPS device
3. Share the vault folder
4. Install Obsidian and point it to the Syncthing vault folder

### Phone Setup (iOS)

1. Install Möbius Sync (Syncthing client for iOS)
2. Add the VPS device and share the vault folder
3. Open vault in Obsidian via Files integration

### Accept devices on VPS

On VPS, accept the incoming device connections:

1. Access `http://<tailscale-ip>:8384` (Syncthing web UI)
2. Accept device connections
3. Accept folder share requests

**Verify:**
```bash
# Check connections
sudo -u nazar syncthing cli show connections
# Should show your devices

# Check folder status
sudo -u nazar syncthing cli show folders
# vault folder should be syncing
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

# 7. OpenClaw service running
sudo -u nazar systemctl --user status openclaw
# Expected: active (running)

# 8. Syncthing service running
sudo -u nazar systemctl --user status syncthing
# Expected: active (running)

# 9. Vault syncing
sudo -u nazar syncthing cli show connections
# Expected: shows connected devices

# 10. No secrets in vault
grep -r "sk-ant\|sk-" /home/nazar/vault/ 2>/dev/null | head -5
# Expected: no output (no API keys in vault files)

# 11. No legacy Syncthing ports in UFW
sudo ufw status | grep -E "22000|21027"
# Expected: no output (Syncthing uses Tailscale, no UFW ports needed)

# 12. Config has no placeholder tokens
grep -E "GENERATE_NEW_TOKEN|GENERATE_SECURE_TOKEN|CHANGE_ME" /home/nazar/.openclaw/openclaw.json
# Expected: no output (token has been generated)
```

Or run the audit script:

```bash
sudo bash ~/nazar/vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

---

## Troubleshooting

### Locked out of SSH
If SSH is locked to Tailscale and Tailscale goes down:
- Use VPS provider's web console (OVH: KVM, Hetzner: Console)
- Re-enable public SSH: `sudo ufw allow 22/tcp`

### Services not starting
Check systemd user services:
```bash
# Check logs
sudo -u nazar journalctl --user -u openclaw --no-pager -n 20
sudo -u nazar journalctl --user -u syncthing --no-pager -n 20

# Ensure lingering is enabled
loginctl show-user nazar | grep Linger
# If Linger=no:
sudo loginctl enable-linger nazar
```

### Syncthing not syncing
```bash
# Check connections
sudo -u nazar syncthing cli show connections

# Check folder errors
sudo -u nazar syncthing cli show folders

# Ensure Tailscale is connected
tailscale status
```

### OpenClaw config issues
```bash
# Check config
cat /home/nazar/.openclaw/openclaw.json | jq .

# Reconfigure
sudo -u nazar openclaw configure
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
| SSH | Tailscale | `ssh debian@<tailscale-ip>` |
| Gateway | Tailscale (automatic) | `https://<tailscale-hostname>/` |
| Syncthing GUI | Tailscale | `http://<tailscale-ip>:8384` |

| Path | Contents |
|------|----------|
| `/home/nazar/vault/` | Obsidian vault (synced via Syncthing) |
| `/home/nazar/.openclaw/` | OpenClaw config + devices (mode 700) |
| `/home/nazar/.local/state/syncthing/` | Syncthing state |
| `/home/nazar/.local/venv-voice/` | Voice tools (Whisper, Piper) |
| `/home/debian/bin/` | Helper scripts (nazar-status, nazar-logs, etc.) |

| Helper | Purpose |
|--------|---------|
| `nazar-status` | Check OpenClaw + Syncthing service status |
| `nazar-logs` | Tail OpenClaw logs |
| `nazar-restart` | Restart OpenClaw service |
| `nazar-audit` | Run security audit |
