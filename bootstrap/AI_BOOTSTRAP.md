# AI Assistant Bootstrap Instructions

**READ THIS FIRST** when a user asks you to guide them through VPS setup.

---

## Your Role

You are guiding a user through setting up the Nazar Second Brain on their fresh VPS. This is an **interactive, step-by-step** process. Explain each step before executing it.

**Architecture Overview:**
- **No Docker** — Services run directly as systemd user services
- **Two users** — `debian` (admin with sudo) and `nazar` (service, no sudo)
- **Syncthing sync** — Real-time vault sync (not Git)
- **Tailscale networking** — All access through VPN

---

## Pre-Flight Checks

Before starting, verify:

1. **You are running on the VPS** — Check if `/root` or typical VPS files exist
2. **The user is root or has sudo** — Check `whoami` and `sudo -l`
3. **This is a fresh Debian/Ubuntu system** — Check `cat /etc/os-release`
4. **Required tools are available** — `git`, `curl` (or install them)

---

## Setup Phases

Guide the user through these phases in order:

### Phase 1: System Preparation

**Ask the user:**
- "What VPS provider are you using?" (Hetzner, OVH, etc.)
- "Do you have a Tailscale account?" (needed for secure access)

**Actions:**
1. Update package lists: `apt update`
2. Install prerequisites: `apt install -y curl git ufw fail2ban`
3. Verify system meets requirements

### Phase 2: Run Bootstrap Script

**Explain:** "We'll run the bootstrap script that sets up users, installs software, and hardens security."

**Action:**
```bash
# Run the bootstrap script
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/bootstrap/bootstrap.sh | bash
```

**What this does:**
- Creates `debian` (admin) and `nazar` (service) users
- Installs Node.js 22, OpenClaw, Syncthing, Tailscale
- Hardens SSH (keys only, no root, no passwords)
- Configures firewall and fail2ban
- Sets up systemd user services

### Phase 3: Tailscale Installation

**Explain:** "Tailscale creates a secure VPN mesh so you can access your VPS privately without exposing ports to the internet."

**Actions:**
1. Start Tailscale:
   ```bash
   sudo tailscale up
   ```

2. **Instruct the user:**
   - "Please open the authentication URL in your browser and log in with your Tailscale account."
   - "Once done, run `tailscale status` to verify you're connected."

3. **After user confirms Tailscale is connected**, get the Tailscale IP:
   ```bash
   tailscale ip -4
   ```

4. **Optional but recommended:** Lock SSH to Tailscale only
   - Ask: "Would you like to lock SSH access to Tailscale only? This prevents anyone from even attempting SSH from the public internet."
   - If yes:
     ```bash
     # First verify: ssh debian@<tailscale-ip>
     # Then lock down
     sudo ufw delete allow 22/tcp
     sudo ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH via Tailscale only'
     ```

### Phase 4: Clone Repository

**Explain:** "Now we'll clone the repository and copy the vault to the service user."

**Actions:**

1. Switch to debian user:
   ```bash
   su - debian
   ```

2. Clone the repository:
   ```bash
   git clone https://github.com/alexradunet/easy-para-system-claw-vps.git ~/nazar
   cd ~/nazar
   ```

3. Copy vault to nazar user:
   ```bash
   sudo cp -r vault/* /home/nazar/vault/
   sudo chown -R nazar:nazar /home/nazar/vault
   ```

### Phase 5: Start Syncthing

**Explain:** "Syncthing will synchronize the vault between your devices in real-time."

**Action:**
```bash
sudo bash ~/nazar/nazar/scripts/setup-syncthing.sh
```

**Instructions for user:**
1. Access `http://<tailscale-ip>:8384`
2. Set admin username and password (important!)
3. Note the Device ID
4. On laptop/phone, add this VPS device and share the vault folder

### Phase 6: Start OpenClaw

**Explain:** "OpenClaw is the AI gateway that powers the Nazar agent."

**Action:**
```bash
sudo bash ~/nazar/nazar/scripts/setup-openclaw.sh
```

**Then configure:**
```bash
sudo -u nazar openclaw configure
```

**Instructions for user:**
- This interactive wizard sets up LLM providers, API keys, and channels
- The gateway will be available at `https://<tailscale-hostname>/`

### Phase 7: Device Pairing

**Explain:** "The first time you access the web UI, you need to approve your browser."

**Action:**
```bash
# List pending devices
sudo -u nazar openclaw devices list

# Approve your browser
sudo -u nazar openclaw devices approve <request-id>
```

### Phase 8: Security Verification

**Run the security audit:**
```bash
nazar-audit
```

**Check all items pass.** If any fail, fix them before considering setup complete.

### Phase 9: Optional Security Hardening

**Explain:** "We can add additional security layers like audit logging, file integrity monitoring, and encrypted backups."

**Action:**
```bash
sudo bash ~/nazar/system/scripts/setup-all-security.sh
```

This presents a menu of optional enhancements:
- Audit logging
- File integrity monitoring
- Canary tokens
- Encrypted backups
- Automatic security response

---

## Important Reminders

### Before Disabling Root SSH
- Ensure the debian user can SSH in: `ssh debian@<tailscale-ip>`
- Ensure debian user has sudo access
- Have a backup way to access the VPS (VNC/console from provider)

### Before Locking SSH to Tailscale
- Ensure Tailscale is connected and working
- Verify you can SSH via Tailscale IP
- Test from your local machine: `ssh debian@<tailscale-ip>`

### Syncthing Setup
- Ensure all devices are on the same Tailscale network
- Device IDs must be exchanged for pairing
- Initial sync may take time for large vaults

---

## Common Issues & Solutions

### Issue: Syncthing devices not connecting
**Solution:** 
```bash
# Check Tailscale connectivity
tailscale status
ping <other-device-tailscale-ip>

# Check Syncthing is listening
sudo -u nazar ss -tlnp | grep syncthing
```

### Issue: OpenClaw won't start
**Solution:**
```bash
# Check config validity
sudo -u nazar jq . ~/.openclaw/openclaw.json

# Check logs
sudo -u nazar journalctl --user -u openclaw -n 50

# Verify Node.js installation
node --version
which openclaw
```

### Issue: Permission denied on vault
**Solution:**
```bash
sudo chown -R nazar:nazar /home/nazar/vault
```

### Issue: Can't access web UI
**Solution:**
```bash
# Check OpenClaw is running
sudo -u nazar systemctl --user status openclaw

# Check it's listening
sudo -u nazar ss -tlnp | grep 18789

# Check Tailscale serve
tailscale serve status
```

---

## Post-Setup Checklist

After setup is complete, verify:

- [ ] SSH works via Tailscale: `ssh debian@<tailscale-ip>`
- [ ] Syncthing is running: `sudo -u nazar systemctl --user status syncthing`
- [ ] OpenClaw is running: `sudo -u nazar systemctl --user status openclaw`
- [ ] Gateway responds: `curl -sk https://<tailscale-hostname>/`
- [ ] Vault permissions correct: `stat /home/nazar/vault`
- [ ] Security audit passes: `nazar-audit`
- [ ] User can run `sudo -u nazar openclaw configure`

---

## Important Notes for AI Assistants

### Before Making Destructive Changes
- **SSH Hardening:** Always confirm the user has another way in (console/VNC) before disabling root SSH
- **Tailscale Lock:** Verify `ssh debian@<tailscale-ip>` works before locking public SSH
- **Service Restart:** Warn user that restarting OpenClaw will interrupt active conversations

### Cloud Provider Quirks
- **Hetzner:** May have cloud-init that overwrites SSH config on reboot
- **OVH:** Often has different default users (check `id ubuntu` or `id debian`)
- **AWS:** Uses `ubuntu` or `ec2-user`, check `/home` directory

### If OpenClaw Fails to Start
1. Check Node.js version: `node --version` (should be 22+)
2. Check OpenClaw installation: `which openclaw`
3. Check config file is valid JSON: `sudo -u nazar jq . ~/.openclaw/openclaw.json`
4. Check logs: `sudo -u nazar journalctl --user -u openclaw`

---

## User Handoff

Once setup is complete, provide the user with:

1. **Tailscale hostname:** `https://<hostname>.<tailnet>.ts.net/`
2. **SSH command:** `ssh debian@<tailscale-ip>`
3. **Syncthing GUI:** `http://<tailscale-ip>:8384`
4. **Next steps:**
   - Complete `sudo -u nazar openclaw configure` for API keys
   - Set up Syncthing on laptop/phone
   - Open vault in Obsidian
   - Optional: Run security hardening

### Backup Reminder
**Important:** Remind the user to set up backups:
```bash
# Option 1: Use encrypted backup script
sudo bash ~/nazar/system/scripts/setup-backup.sh

# Option 2: Syncthing versioning protects against deletes
# Configure in Syncthing GUI: Folder -> Versioning -> Simple File Versioning
```

---

*Remember: Go slow, explain each step, and confirm with the user before making destructive changes.*
