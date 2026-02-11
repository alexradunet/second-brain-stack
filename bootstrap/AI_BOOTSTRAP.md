# AI Assistant Bootstrap Instructions

**READ THIS FIRST** when a user asks you to guide them through VPS setup.

---

## Your Role

You are guiding a user through setting up the Nazar Second Brain on their fresh VPS. This is an **interactive, step-by-step** process. Explain each step before executing it.

---

## Pre-Flight Checks

Before starting, verify:

1. **You are running on the VPS** — Check if `/root` or typical VPS files exist
2. **The user is root or has sudo** — Check `whoami` and `sudo -l`
3. **This is a fresh Debian/Ubuntu system** — Check `cat /etc/os-release`
4. **Required tools are available** — `git`, `curl`, `nodejs` (or install them)

---

## Setup Phases

Guide the user through these phases in order:

### Phase 1: System Preparation

**Ask the user:**
- "What VPS provider are you using?" (Hetzner, OVH, etc.)
- "Do you want to create a dedicated deploy user, or use the default (debian/ubuntu)?"
- "Do you have a GitHub repository for your vault already, or should we create a local bare repo?"

**Actions:**
1. Update package lists: `apt update`
2. Install prerequisites: `apt install -y curl git ufw fail2ban`
3. If Node.js is not installed, install it (needed for later)

### Phase 2: Security Hardening

**Explain:** "We'll secure SSH to prevent unauthorized access."

**Actions:**
1. **Check current SSH config:**
   ```bash
   cat /etc/ssh/sshd_config | grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)"
   ```

2. **If root login is enabled, warn the user and ask for confirmation before disabling:**
   - "SSH root login is currently enabled. For security, I recommend disabling it and using a regular user with sudo. Proceed?"
   - **CRITICAL:** Before disabling root SSH, ensure the deploy user can SSH in with keys!

3. **Verify deploy user has SSH keys:**
   ```bash
   # Check if root has authorized_keys to copy
   if [ -f /root/.ssh/authorized_keys ]; then
       mkdir -p /home/debian/.ssh
       cp /root/.ssh/authorized_keys /home/debian/.ssh/
       chown -R debian:debian /home/debian/.ssh
       chmod 700 /home/debian/.ssh
       chmod 600 /home/debian/.ssh/authorized_keys
   fi
   ```

4. **Apply hardening (only after confirmation):**
   ```bash
   # Backup original
   cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)
   
   # Create hardened config in sshd_config.d (cleaner than modifying main file)
   cat > /etc/ssh/sshd_config.d/hardened.conf << 'EOF'
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
   
   # Only allow the deploy user (adjust if using ubuntu or other)
   AllowUsers debian
   EOF
   
   # Validate config before restarting
   sshd -t || echo "SSH config invalid!"
   
   # Restart SSH
   systemctl restart sshd
   ```

5. **Configure UFW firewall:**
   ```bash
   ufw default deny incoming
   ufw default allow outgoing
   ufw allow 22/tcp comment 'SSH'
   ufw --force enable
   ```

6. **Enable Fail2Ban:**
   ```bash
   systemctl enable fail2ban
   systemctl start fail2ban
   ```

7. **Enable unattended upgrades:**
   ```bash
   apt install -y unattended-upgrades apt-listchanges
   
   # Configure unattended-upgrades (non-interactive)
   cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
   Unattended-Upgrade::Allowed-Origins {
       "${distro_id}:${distro_codename}";
       "${distro_id}:${distro_codename}-security";
   };
   Unattended-Upgrade::AutoFixInterruptedDpkg "true";
   Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
   Unattended-Upgrade::Remove-Unused-Dependencies "true";
   Unattended-Upgrade::Automatic-Reboot "true";
   Unattended-Upgrade::Automatic-Reboot-Time "04:00";
   EOF
   
   cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
   APT::Periodic::Update-Package-Lists "1";
   APT::Periodic::Unattended-Upgrade "1";
   APT::Periodic::AutocleanInterval "7";
   EOF
   
   systemctl enable unattended-upgrades
   systemctl restart unattended-upgrades
   ```

### Phase 3: Tailscale Installation

**Explain:** "Tailscale creates a secure VPN mesh so you can access your VPS privately without exposing ports to the internet."

**Actions:**
1. Install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. Start Tailscale (this will output an auth URL):
   ```bash
   tailscale up
   ```

3. **Instruct the user:**
   - "Please open the authentication URL in your browser and log in with your Tailscale account."
   - "Once done, run `tailscale status` to verify you're connected."

4. **After user confirms Tailscale is connected**, get the Tailscale IP:
   ```bash
   tailscale ip -4
   ```

5. **Optional but recommended:** Lock SSH to Tailscale only
   - Ask: "Would you like to lock SSH access to Tailscale only? This prevents anyone from even attempting SSH from the public internet."
   - If yes:
     ```bash
     # Get Tailscale interface name (usually tailscale0)
     TAILSCALE_IF=$(ip -o link show | grep -i tailscale | awk -F': ' '{print $2}' | head -1)
     
     # Update UFW to only allow SSH on Tailscale interface
     ufw delete allow 22/tcp
     ufw allow in on $TAILSCALE_IF to any port 22 proto tcp comment 'SSH via Tailscale only'
     ```

### Phase 4: Docker Installation

**Explain:** "Docker will run the Nazar gateway container."

**Actions:**
1. **Add swap if low memory** (Docker builds need RAM):
   ```bash
   TOTAL_MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
   if [ "$TOTAL_MEM" -lt 2048 ] && [ ! -f /swapfile ]; then
       echo "Low memory (${TOTAL_MEM}MB). Adding 2GB swap..."
       fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
       chmod 600 /swapfile
       mkswap /swapfile
       swapon /swapfile
       echo '/swapfile none swap sw 0 0' >> /etc/fstab
   fi
   ```

2. Install Docker:
   ```bash
   curl -fsSL https://get.docker.com | sh
   ```

3. Add deploy user to docker group:
   ```bash
   usermod -aG docker debian  # or whatever deploy user was chosen
   ```

4. Install Docker Compose plugin:
   ```bash
   apt install -y docker-compose-plugin
   ```

5. Verify installation:
   ```bash
   docker --version
   docker compose version
   ```
   
   **Note:** The deploy user must log out and back in for docker group to take effect, or run `newgrp docker`.

### Phase 5: Deploy User Setup

**Actions:**
1. Create deploy user if not exists:
   ```bash
   id debian || useradd -m -s /bin/bash -G sudo debian
   ```

2. Ensure deploy user has SSH key:
   ```bash
   mkdir -p /home/debian/.ssh
   # If root has authorized_keys, copy them
   if [ -f /root/.ssh/authorized_keys ]; then
       cp /root/.ssh/authorized_keys /home/debian/.ssh/
       chown -R debian:debian /home/debian/.ssh
       chmod 700 /home/debian/.ssh
       chmod 600 /home/debian/.ssh/authorized_keys
   fi
   ```

3. Set up passwordless sudo for deploy user:
   ```bash
   echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian
   chmod 440 /etc/sudoers.d/debian
   ```

### Phase 6: Nazar Installation

**Explain:** "Now we'll set up the Nazar stack - the vault repository, configuration, and containers."

**Actions:**

1. **Copy deploy files from the cloned repo to /srv/nazar:**
   ```bash
   NAZAR_ROOT=/srv/nazar
   DEPLOY_DIR=~/nazar_deploy/deploy  # Note: deploy/ is a subdirectory of the repo
   
   mkdir -p $NAZAR_ROOT
   
   # Check if deploy directory exists in the cloned repo
   if [ -d "$DEPLOY_DIR" ]; then
       cp -r $DEPLOY_DIR/* $NAZAR_ROOT/
   else
       echo "Error: deploy/ directory not found in $DEPLOY_DIR"
       echo "Make sure you cloned the full repository, not just the deploy folder"
       echo "Expected structure: ~/nazar_deploy/deploy/"
       ls -la ~/nazar_deploy/  # Show what's actually there
       exit 1
   fi
   ```

2. **Run the main setup script:**
   ```bash
   cd $NAZAR_ROOT
   NAZAR_ROOT=/srv/nazar DEPLOY_USER=debian bash scripts/setup-vps.sh
   ```

   This script will:
   - Create the vault directory structure
   - Initialize git repositories
   - Set up auto-commit cron
   - Clone OpenClaw source
   - Build and start containers

3. **Monitor the build process** — this takes 10-15 minutes on a 2-core VPS.

4. **After the script completes, verify:**
   ```bash
   cd /srv/nazar
   docker compose ps
   ```

### Phase 7: Initial Configuration

**Explain:** "The containers are running. Now we need to configure the OpenClaw gateway."

**Actions:**
1. Create the `openclaw` command alias for the deploy user:
   ```bash
   cat >> /home/debian/.bashrc << 'EOF'
   alias openclaw='sudo docker exec -it nazar-gateway node dist/index.js'
   EOF
   ```

2. **Instruct the user:**
   - "The basic setup is complete! Now you need to configure the gateway."
   - "Please log out and log back in as the deploy user, then run:"
   - "`openclaw configure`"
   - "This interactive wizard will set up your LLM providers, API keys, and channels."

3. **Provide the Tailscale access URL:**
   ```bash
   HOSTNAME=$(tailscale status --json | grep -o '"HostName": "[^"]*"' | cut -d'"' -f4)
   echo "Your gateway will be accessible at: https://${HOSTNAME}/"
   ```

### Phase 8: Vault Setup Instructions

**Explain to the user how to sync their vault:**

**Option A: Starting Fresh**
```bash
# On your laptop
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/nazar-vault
```

**Option B: Existing Vault**
```bash
# On your laptop, in your existing vault directory
git remote add origin debian@<tailscale-ip>:/srv/nazar/vault.git
git push -u origin main
```

**Option C: Using GitHub as Remote**
- If the user wants to use GitHub instead, help them:
  1. Set `VAULT_GIT_REMOTE` in the setup script
  2. Re-run setup

### Phase 9: Security Verification

**Run the security audit:**
```bash
bash /srv/nazar/vault/99-system/openclaw/skills/vps-setup/scripts/audit-vps.sh
```

**Check all items pass.** If any fail, fix them before considering setup complete.

---

## Important Reminders

### Before Disabling Root SSH
- Ensure the deploy user can SSH in: `ssh debian@<tailscale-ip>`
- Ensure deploy user has sudo access
- Have a backup way to access the VPS (VNC/console from provider)

### Before Locking SSH to Tailscale
- Ensure Tailscale is connected and working
- Verify you can SSH via Tailscale IP
- Test from your local machine: `ssh debian@<tailscale-ip>`

### Docker Build Considerations
- The build takes 10-15 minutes on 2-core VPS
- Requires ~3GB disk space for the image
- May fail on low-memory VPS (<2GB) — add swap if needed

---

## Common Issues & Solutions

### Issue: Docker build fails with out of memory
**Solution:** Add swap
```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Issue: Permission denied on vault
**Solution:** Fix ownership
```bash
chown -R debian:vault /srv/nazar/vault
find /srv/nazar/vault -type d -exec chmod 2775 {} +
```

### Issue: Container fails to start
**Solution:** Check logs
```bash
cd /srv/nazar
docker compose logs nazar-gateway
```

### Issue: Git push rejected
**Solution:** Pull first
```bash
cd /srv/nazar/vault
git pull --rebase origin main
```

---

## Post-Setup Checklist

After setup is complete, verify:

- [ ] SSH works via Tailscale: `ssh debian@<tailscale-ip>`
- [ ] Containers are running: `docker compose ps`
- [ ] Gateway responds: `curl -sk https://<tailscale-hostname>/`
- [ ] Vault git works: `git clone debian@<tailscale-ip>:/srv/nazar/vault.git /tmp/test-clone`
- [ ] Security audit passes: `bash audit-vps.sh`
- [ ] User can run `openclaw configure`

---

## Important Notes for AI Assistants

### Before Making Destructive Changes
- **SSH Hardening:** Always confirm the user has another way in (console/VNC) before disabling root SSH
- **Tailscale Lock:** Verify `ssh debian@<tailscale-ip>` works before locking public SSH
- **Docker Group:** Remind user to log out/in or run `newgrp docker` after adding to docker group

### Cloud Provider Quirks
- **Hetzner:** May have cloud-init that overwrites SSH config on reboot
- **OVH:** Often has different default users (check `id ubuntu` or `id debian`)
- **AWS:** Uses `ubuntu` or `ec2-user`, check `/home` directory

### If Docker Build Fails
1. Check memory: `free -h`
2. Add more swap if needed
3. Try build with limited parallelism: `DOCKER_BUILDKIT=0 docker compose build`

---

## User Handoff

Once setup is complete, provide the user with:

1. **Tailscale hostname:** `https://<hostname>.<tailnet>.ts.net/`
2. **SSH command:** `ssh debian@<tailscale-ip>`
3. **Vault clone command:** `git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/nazar-vault`
4. **Next steps:**
   - Run `openclaw configure` to set up models and channels
   - Clone vault to laptop and open in Obsidian
   - Install Obsidian Git plugin for auto-sync

### Backup Reminder
**Important:** Remind the user to set up backups for their vault:
```bash
# The vault is at /srv/nazar/vault/ on the VPS
# Git provides distributed backup (each clone is a full backup)
# For additional safety, consider:
# - Regular git push to GitHub/GitLab as remote
# - Local backups on laptop/phone
# - VPS snapshots (if provider supports it)
```

---

*Remember: Go slow, explain each step, and confirm with the user before making destructive changes.*
