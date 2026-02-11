# Git-Based Vault Sync

The vault syncs across all devices using Git over SSH (through Tailscale). No extra services, no public ports, full version history.

## How It Works

```
Laptop (Obsidian)  ◄──── git push/pull over SSH ────►  VPS (bare repo)
       ▲                                                      │
       │                                                 post-receive
       │                                                      │
       │                                                      ▼
       │                                            VPS working copy
       │                                               (/srv/nazar/vault)
       │                                                      │
       └──────── git push/pull over SSH ────►  Phone (Obsidian Git)
```

- **Push from laptop/phone**: Changes go to the bare repo on VPS, post-receive hook updates the working copy
- **Agent writes on VPS**: Cron job commits and pushes to bare repo every 5 minutes
- **Pull on laptop/phone**: Get both your synced changes and agent writes

## External Git Remote (GitHub/GitLab)

Instead of the local bare repo, you can use an external git remote. Set `VAULT_GIT_REMOTE` when running setup:

```bash
sudo VAULT_GIT_REMOTE=git@github.com:youruser/vault.git bash scripts/setup-vps.sh
```

This skips creating the local bare repo and post-receive hook. The auto-commit cron still runs and pushes to the external remote. Clients clone directly from GitHub/GitLab instead of the VPS.

## Architecture on VPS

| Path | Purpose |
|------|---------|
| `/srv/nazar/vault/` | Working copy (bind-mounted into gateway container at `/vault`) |
| `/srv/nazar/vault.git/` | Bare repo (push/pull target for clients) |
| `/srv/nazar/vault.git/hooks/post-receive` | Updates working copy when you push |
| `/srv/nazar/scripts/vault-auto-commit.sh` | Cron script: commits agent writes, pushes to bare repo |

Permissions use a shared `vault` group with setgid:
- `debian` user owns the files
- Container (uid 1000) and `debian` both belong to the `vault` group
- `core.sharedRepository=group` ensures git respects group permissions
- Setgid on directories means new files inherit the `vault` group

## Client Setup

### Laptop (Windows/Mac/Linux)

**Prerequisites:** Git installed, Tailscale connected to your tailnet.

```bash
# Clone the vault
git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/vault

# Or if using Tailscale MagicDNS:
git clone debian@<tailscale-hostname>:/srv/nazar/vault.git ~/vault
```

**With Obsidian Git plugin:**
1. Open the cloned vault in Obsidian
2. Install the [Obsidian Git](https://github.com/denolehov/obsidian-git) community plugin
3. Configure:
   - Auto pull interval: 5 minutes
   - Auto push after commit: enabled
   - Auto commit interval: 5 minutes
4. The plugin handles `git pull`, `git add`, `git commit`, `git push` automatically

**Without Obsidian Git (manual):**
```bash
cd ~/vault
git pull                    # Get latest changes
# ... edit files in Obsidian ...
git add -A && git commit -m "vault update" && git push
```

### Phone (Android)

**Option A: Obsidian Git plugin (recommended)**
1. Install Obsidian from Play Store
2. Clone vault using Obsidian Git plugin settings:
   - Repository URL: `debian@<tailscale-ip>:/srv/nazar/vault.git`
   - Requires Tailscale running on the phone
3. Configure auto-pull and auto-push as above

**Option B: Termux + git**
1. Install [Termux](https://f-droid.org/packages/com.termux/)
2. In Termux:
   ```bash
   pkg install git openssh
   git clone debian@<tailscale-ip>:/srv/nazar/vault.git ~/storage/shared/vault
   ```
3. Point Obsidian to `~/storage/shared/vault`
4. Sync manually or via a Termux cron/widget

### Phone (iOS)

**Option A: Obsidian Git plugin**
- Works the same as Android — configure in Obsidian Git plugin settings

**Option B: Working Copy app**
1. Install [Working Copy](https://workingcopy.app/) (Git client for iOS)
2. Clone `debian@<tailscale-ip>:/srv/nazar/vault.git`
3. Open the vault folder in Obsidian via Files integration

## SSH Key Setup

Clients need an SSH key that's authorized on the VPS. The `debian` user's `~/.ssh/authorized_keys` controls access.

```bash
# On your client device, generate a key (if you don't have one):
ssh-keygen -t ed25519 -C "vault-sync"

# Copy your public key to the VPS:
ssh-copy-id debian@<tailscale-ip>

# Test:
ssh debian@<tailscale-ip> "echo ok"
```

## Sync Log

All sync operations are logged:

```bash
tail -f /srv/nazar/data/git-sync.log
```

Example output:
```
2026-02-11 14:30:01 auto-commit: committed and pushed — 3 files changed, 42 insertions(+)
2026-02-11 14:35:22 post-receive: push received
2026-02-11 14:35:22 post-receive: stashed uncommitted agent writes
2026-02-11 14:35:22 post-receive: working copy updated to a1b2c3d
2026-02-11 14:35:22 post-receive: re-applied stashed agent writes
2026-02-11 14:35:22 post-receive: done
```

## .gitignore

The vault excludes device-specific and temporary files:

```
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.DS_Store
Thumbs.db
Desktop.ini
__pycache__/
*.pyc
*.tmp
*.swp
*~
.trash/
.stfolder
.stignore
```

## Common Workflows

### First-time sync (vault already on laptop)

If your vault already exists locally and you're setting up the VPS:

```bash
cd ~/vault
git init
git remote add origin debian@<tailscale-ip>:/srv/nazar/vault.git
git add -A
git commit -m "initial vault"
git push -u origin main
```

### Resolving conflicts

When both you and the agent edit the same file:

```bash
git pull origin main
# Resolve conflicts in your editor
git add -A
git commit -m "resolved conflicts"
git push
```

### Checking what the agent changed

```bash
git log --oneline --author="Nazar" -10
git diff HEAD~1    # See last commit's changes
```

## Comparison with Syncthing

| Feature | Git Sync | Syncthing (previous) |
|---------|----------|---------------------|
| Public ports | None (SSH over Tailscale) | 22000/tcp, 22000/udp, 21027/udp |
| Containers | None (uses SSH) | 1 (nazar-syncthing) |
| Version history | Full git log | None (overwrite sync) |
| Conflict handling | Git merge/rebase | `.sync-conflict-*` files |
| Offline support | Full (commit locally, push later) | Full (syncs when connected) |
| Setup complexity | `git clone` | Device ID exchange + folder sharing |
| Binary files | Works (no LFS needed at ~500KB) | Native support |

## Troubleshooting

See [troubleshooting.md](troubleshooting.md#vault-sync-issues) for common issues.
