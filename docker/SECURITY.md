# Security Guide for Nazar Second Brain

This document describes the security measures implemented in the Docker-based Nazar Second Brain deployment, based on OVHcloud's "How to secure a VPS" guide.

## Security Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     Security Layers                             │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Network                                               │
│    - SSH tunnel or Tailscale VPN (no public ports)              │
│    - UFW firewall (blocks all incoming except SSH)              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Authentication                                        │
│    - SSH key authentication only                                │
│    - Password authentication disabled                           │
│    - Root login disabled                                        │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Intrusion Prevention                                  │
│    - Fail2ban (blocks IPs after 3 failed attempts)              │
│    - Automatic security updates                                 │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: Container Isolation                                   │
│    - Services run as non-root (UID 1000)                        │
│    - Read-only root filesystems                                 │
│    - No new privileges                                          │
├─────────────────────────────────────────────────────────────────┤
│  Layer 5: Data Protection                                       │
│    - API keys in .env file, never in vault                      │
│    - Encrypted backups recommended                              │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Security Setup

```bash
# Run automated security hardening
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh | sudo bash

# Or during main setup, answer "yes" when prompted for security hardening
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
```

## Detailed Security Measures

### 1. SSH Hardening

**Configuration file:** `/etc/ssh/sshd_config.d/nazar-security.conf`

Implemented settings:
```
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
MaxAuthTries 3
MaxSessions 5
X11Forwarding no
```

**Why:** Prevents brute-force attacks and eliminates password-based vulnerabilities.

**Verification:**
```bash
# Check SSH config
sudo sshd -t

# Test connection (from another terminal)
ssh debian@your-vps-ip
```

### 2. Firewall (UFW)

**Status:** Active with minimal rules

Default policy:
- Incoming: DENY
- Outgoing: ALLOW
- Allowed: SSH port only

```bash
# Check status
sudo ufw status verbose

# View logs
sudo ufw logging on
sudo tail -f /var/log/ufw.log
```

**Note:** Syncthing sync protocol works over outgoing connections (allowed by default). Direct incoming connections to Syncthing ports are blocked.

### 3. Fail2ban

**Configuration:** `/etc/fail2ban/jail.local`

Default settings:
- Max retries: 3
- Ban time: 1 hour
- Find time: 10 minutes
- Ignored IPs: Localhost, Docker networks

```bash
# Check status
sudo fail2ban-client status
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client status sshd | grep "Banned IP list"

# Unban an IP (if needed)
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>
```

### 4. Automatic Updates

**Configuration:** `/etc/apt/apt.conf.d/50unattended-upgrades`

- Security updates: Automatic
- Reboot: Yes, at 4:00 AM
- Unused packages: Auto-removed

```bash
# Check status
sudo systemctl status unattended-upgrades

# View logs
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log
```

### 5. Docker Security

Container security features:
- **User:** Non-root (UID 1000)
- **Read-only root:** Enabled
- **No new privileges:** Enabled
- **Tmpfs:** For /tmp and /var/tmp
- **Resource limits:** CPU and memory capped

```bash
# Check container security options
docker inspect nazar-openclaw | grep -A5 "SecurityOpt"
docker inspect nazar-openclaw | grep -A5 "User"
```

## Security Checklist

Use this checklist after setup:

- [ ] SSH key authentication working
- [ ] Password authentication disabled
- [ ] Root login disabled
- [ ] UFW firewall active
- [ ] Fail2ban running
- [ ] Auto-updates enabled
- [ ] Docker containers running as non-root
- [ ] Gateway token is strong (32+ hex chars)
- [ ] API keys in .env file, not in vault
- [ ] Backups configured

Run automated check:
```bash
sudo nazar-security-audit
```

## Access Methods

### SSH Tunnel (Recommended for Single User)

Most secure - no ports exposed to internet.

```bash
# On laptop
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@vps-ip

# Access:
# - OpenClaw: http://localhost:18789
# - Syncthing: http://localhost:8384
```

### Tailscale (For Multi-Device)

Mesh VPN - requires Tailscale account.

```bash
# In .env
DEPLOYMENT_MODE=tailscale
TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxx

# Access via Tailscale IPs
```

## Threat Model

### Protected Against

| Threat | Mitigation |
|--------|-----------|
| Brute-force SSH | Fail2ban + key-only auth |
| Password attacks | Password auth disabled |
| Root compromise | Root login disabled |
| Network scanning | UFW blocks all incoming |
| Container escape | Non-root + no-new-privileges |
| Unpatched vulnerabilities | Auto-updates |

### Additional Considerations

| Concern | Recommendation |
|---------|---------------|
| Physical access | Use encrypted VPS provider |
| Provider compromise | Use client-side encryption |
| Backup security | Encrypt backups with GPG |
| Key management | Use hardware security key |

## Hardening Further

### Change SSH Port

```bash
# Edit config
sudo nano /etc/ssh/sshd_config.d/nazar-security.conf

# Add:
Port 49152  # Choose a port between 49152-65535

# Update firewall
sudo ufw delete allow 22/tcp
sudo ufw allow 49152/tcp comment 'SSH'
sudo ufw reload

# Restart SSH
sudo systemctl restart sshd

# Connect with new port
ssh -p 49152 debian@your-vps-ip
```

### Enable 2FA for SSH

```bash
# Install Google Authenticator
sudo apt-get install libpam-google-authenticator

# Set up for user
google-authenticator

# Configure PAM
sudo nano /etc/pam.d/sshd
# Add: auth required pam_google_authenticator.so

# Update SSH config
sudo nano /etc/ssh/sshd_config
# Set: ChallengeResponseAuthentication yes
# Set: AuthenticationMethods publickey,keyboard-interactive

sudo systemctl restart sshd
```

### Encrypted Backups

```bash
# Install GPG if needed
sudo apt-get install gnupg

# Generate key
gpg --full-generate-key

# Create encrypted backup
nazar-cli backup
gpg -c ~/nazar/backups/nazar-backup-*.tar.gz

# Result: nazar-backup-*.tar.gz.gpg
rm ~/nazar/backups/nazar-backup-*.tar.gz  # Remove unencrypted
```

### Audit Logging

```bash
# Install auditd
sudo apt-get install auditd

# Monitor sensitive files
sudo auditctl -w /home/debian/nazar/.openclaw/ -p rwxa -k openclaw_config
sudo auditctl -w /home/debian/nazar/vault/ -p rwxa -k vault_access

# View audit logs
sudo ausearch -k openclaw_config -ts recent
```

## Incident Response

### If You Suspect Compromise

1. **Isolate:** Disconnect from network if possible
   ```bash
   sudo ufw reset
   sudo ufw default deny incoming
   sudo ufw default deny outgoing
   ```

2. **Preserve logs:**
   ```bash
   sudo cp /var/log/auth.log ~/incident-auth.log
   sudo cp /var/log/fail2ban.log ~/incident-fail2ban.log
   docker logs nazar-openclaw > ~/incident-openclaw.log
   ```

3. **Check active connections:**
   ```bash
   sudo ss -tlnp
   sudo netstat -tulpn
   docker ps
   ```

4. **Review recent activity:**
   ```bash
   sudo last
   sudo tail -n 100 /var/log/auth.log
   sudo fail2ban-client status
   ```

### Recovery

1. Restore from clean backup
2. Change all passwords/tokens
3. Rotate API keys
4. Review and reapply security hardening

## Resources

- [OVHcloud: How to secure a VPS](https://docs.ovh.com/gb/en/vps/tips-for-securing-a-vps/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [Fail2ban Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [UFW Essentials](https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands)

---

*Security is a process, not a product. Regularly review and update your security posture.*
