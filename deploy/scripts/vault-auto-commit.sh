#!/bin/bash
# vault-auto-commit.sh — Commits and pushes agent writes to the bare repo
# Installed as crontab for nazar: */5 * * * *
# Only commits if there are actual changes.
set -uo pipefail

VAULT_WORK="/srv/nazar/vault"
LOG="/srv/nazar/data/git-sync.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') auto-commit: $*" >> "$LOG"; }

cd "$VAULT_WORK" || { log "ERROR: cannot cd to $VAULT_WORK"; exit 1; }

# Stage all changes (new, modified, deleted)
git add -A

# Exit if nothing to commit
if git diff --cached --quiet; then
    exit 0
fi

# Count what changed
CHANGED=$(git diff --cached --stat | tail -1)

git commit -m "auto: vault changes ($(date '+%Y-%m-%d %H:%M'))" --quiet 2>>"$LOG"
git push origin main --quiet 2>>"$LOG"

log "committed and pushed — $CHANGED"
