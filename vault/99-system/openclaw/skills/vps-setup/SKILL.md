---
name: vps-setup
description: AI-assisted provisioning of an OVHcloud Debian 13 VPS with hardened security, Tailscale networking, and the Nazar (OpenClaw + Syncthing vault sync) stack. Optimized for Claude Code and Kimi Code AI agents with checkpoint/resume, JSON output, and idempotent operations.
---

# VPS Setup Skill (AI Agent Optimized)

Interactive guide for AI agents (Claude Code, Kimi Code) to provision a fresh OVHcloud Debian 13 VPS into a secure Nazar deployment host.

## For AI Agents: Quick Decision Tree

```
User says: "Set up my VPS"
    │
    ▼
┌─────────────────────────┐
│ 1. CHECK CURRENT STATE  │ ◄── Run: nazar-ai-setup --json status
└─────────────────────────┘
    │
    ├──► Not started ──► Run full setup
    │
    ├──► In progress ──► Ask user: "Continue from X?"
    │
    └──► Failed ───────► Ask user: "Retry or troubleshoot?"
```

## Prerequisites (Confirm with User)

1. **Fresh OVHcloud Debian 13 VPS** — ordered from the OVHcloud control panel
2. **Root SSH access** — for initial bootstrap (will create `debian` user)
3. **Tailscale account** — user has a Tailscale account at https://login.tailscale.com
4. **SSH keys** — configured for root access (critical: will disable password auth)
5. **API keys ready** — Anthropic, OpenAI, etc. (for `openclaw configure` later)

## AI Agent Recommended Workflow

### Phase 0: Validation (Always Start Here)

```bash
# Check current state (JSON for machine parsing)
nazar-ai-setup --json status

# Run pre-flight validation
nazar-ai-setup validate
```

**Parse the JSON output to determine next action.**

### Phase 1: Bootstrap (As Root)

If validation passes and setup hasn't started:

```bash
# Download the AI setup script
curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/vault/99-system/openclaw/skills/vps-setup/scripts/nazar-ai-setup.sh \
    -o /usr/local/bin/nazar-ai-setup && chmod +x /usr/local/bin/nazar-ai-setup

# Run full setup (will prompt for decisions)
nazar-ai-setup run
```

**Or run phases individually (better for error handling):**

```bash
# As root
nazar-ai-setup run validate   # Pre-flight
nazar-ai-setup run user       # Create debian user
nazar-ai-setup run security   # Harden SSH, firewall, fail2ban

# Switch to debian user
su - debian
nazar-ai-setup run docker      # Install Docker
nazar-ai-setup run services   # Deploy OpenClaw + Syncthing
nazar-ai-setup run tailscale   # Setup Tailscale (may need user auth)
nazar-ai-setup run verify      # Final checks
```

### Phase 2: Tailscale Authorization (Requires User)

If Tailscale shows "pending_auth":

> **Ask user:** "Please open this URL in your browser to authorize Tailscale: [URL]"

Then verify:

```bash
tailscale status
nazar-ai-setup --json status  # Should show tailscale.completed
```

### Phase 3: Post-Infrastructure (Requires User)

Once infrastructure is complete:

> **Inform user:** "Infrastructure is ready. Next steps require your interaction:"
> 1. **Syncthing** — Open http://localhost:8384 (via SSH tunnel) and add your devices
> 2. **OpenClaw** — Run: `docker compose exec -it openclaw openclaw configure`

## Scripts Reference

| Script | Purpose | Run As | AI-Optimized |
|--------|---------|--------|--------------|
| `nazar-ai-setup.sh` | Master script with checkpoints/resume | any | **Yes** |
| `secure-vps.sh` | Security hardening (SSH, UFW, fail2ban) | root | No |
| `install-tailscale.sh` | Install Tailscale | root | No |
| `lock-ssh-to-tailscale.sh` | Lock SSH to Tailscale only | root | No |
| `audit-vps.sh` | Security audit | root | No |

**AI agents should prefer `nazar-ai-setup.sh`** — it tracks state and is idempotent.

## State File Format

The setup tracks progress in `~/.nazar-setup-state` (JSON):

```json
{
  "version": "1.0.0",
  "started": "2026-01-15T10:30:00Z",
  "completed": null,
  "current_phase": "services",
  "phases": {
    "validate": { "status": "completed", "result": "success" },
    "user": { "status": "completed", "result": "debian_user_configured" },
    "security": { "status": "completed", "result": "hardening_applied" },
    "docker": { "status": "completed", "result": "docker_installed" },
    "services": { "status": "running" },
    "tailscale": { "status": "pending" },
    "verify": { "status": "pending" }
  }
}
```

**Parse this to resume interrupted setups.**

## Execution Phases (Detailed)

### Phase 1: Validate Default User

**Why:** Running services as root is dangerous. Use the cloud provider's default `debian` user.

```bash
nazar-ai-setup run validate
```

**AI Decision Logic:**
- If `validate` fails → Stop and report errors to user
- If `user` already completed → Skip

### Phase 2: Harden SSH

**Why:** Disable password auth and root login. SSH keys only.

**⚠️ CRITICAL SAFETY CHECK:**

Before restarting SSH, verify the user can log in as `debian` with their SSH key. If they can't, they'll be locked out.

```bash
# Script handles this, but AI should verify:
ssh -o PasswordAuthentication=no debian@<vps-ip> echo "OK"
```

**AI Decision Logic:**
- Run `nazar-ai-setup run security`
- Parse output for "SSH restarted with hardened config"
- If error → Alert user about potential lockout risk

### Phase 3: Firewall (UFW)

**Why:** Block everything except SSH. Tailscale handles internal access.

```bash
nazar-ai-setup run security  # (includes UFW setup)
```

**Note:** No Syncthing ports needed in UFW. Syncthing communicates through Tailscale.

### Phase 4-5: Fail2Ban + Auto-Updates

Included in `nazar-ai-setup run security`.

### Phase 6: Install Tailscale

**Why:** Zero-config VPN. All services only accessible via Tailscale IPs.

```bash
nazar-ai-setup run tailscale
```

**AI Decision Logic:**
- Check if auth key is available in config
- If no auth key → Output will show auth URL
- **Prompt user:** "Please authorize Tailscale at: [URL]"
- Poll `tailscale status` until connected

### Phase 7: Deploy Services (Docker)

**Why:** OpenClaw + Syncthing in containers with shared vault volume.

```bash
# As debian user
nazar-ai-setup run docker
nazar-ai-setup run services
```

**What it does:**
- Installs Docker
- Creates directory structure (`~/nazar/vault`, `~/.openclaw`, etc.)
- Generates `openclaw.json` with secure token
- Starts containers

### Phase 8: Verify

```bash
nazar-ai-setup run verify
```

**Checks:**
- Docker daemon running
- Containers up
- Vault structure present
- OpenClaw configured
- SSH hardened

## Troubleshooting for AI Agents

### Check Status

```bash
nazar-ai-setup status          # Human-readable
nazar-ai-setup --json status   # Machine-readable
```

### Resume After Interruption

```bash
# Check what phase was running
nazar-ai-setup --json status

# Resume from that phase
nazar-ai-setup run <phase_name>
```

### Common Issues

**1. Permission Denied on Docker**
```bash
# Fix: Add debian to docker group
sudo usermod -aG docker debian
# User must log out and back in
```

**2. Tailscale Auth Pending**
```bash
# Check status
tailscale status

# If not authenticated, user needs to visit auth URL
# Or provide auth key for unattended setup
```

**3. Containers Won't Start**
```bash
# Check logs
cd ~/nazar/docker && docker compose logs

# Fix permissions
chown -R 1000:1000 ~/nazar

# Restart
docker compose restart
```

**4. Locked Out of SSH**
- Use OVHcloud KVM console (control panel → VPS → KVM)
- Fix: `sudo ufw allow 22/tcp`

## Quick Reference

| Command | Purpose |
|---------|---------|
| `nazar-ai-setup status` | Show setup progress |
| `nazar-ai-setup --json status` | Machine-readable status |
| `nazar-ai-setup validate` | Pre-flight checks |
| `nazar-ai-setup run` | Full setup |
| `nazar-ai-setup run <phase>` | Run specific phase |
| `nazar-cli status` | Check service health |
| `nazar-cli logs` | View container logs |
| `nazar-cli backup` | Backup vault |

## Access URLs

| Service | Access Method | URL |
|---------|---------------|-----|
| OpenClaw Gateway | SSH tunnel | `http://localhost:18789` |
| Syncthing GUI | SSH tunnel | `http://localhost:8384` |

**SSH tunnel command:**
```bash
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@<vps-ip>
```

---

## Example AI Agent Session

```
User: "Set up my new OVH VPS"

AI: Let me check the current state and run validation...
[Runs: nazar-ai-setup --json status]
[Runs: nazar-ai-setup validate]

AI: Validation passed. Starting setup...
[Runs: nazar-ai-setup run]

[Setup progresses through phases...]

AI: Tailscale requires authorization. Please visit:
     https://login.tailscale.com/admin/machines and approve this device.
     
[User approves]

AI: Tailscale connected! Continuing...
[Setup completes]

AI: ✓ Setup complete! Your Nazar Second Brain is ready.

    Next steps for you:
    1. Configure Syncthing: http://localhost:8384 (via SSH tunnel)
    2. Configure OpenClaw: docker compose exec -it openclaw openclaw configure
    
    Access commands:
    - SSH tunnel: ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@<ip>
    - Check status: nazar-cli status
    - View logs: nazar-cli logs
```
