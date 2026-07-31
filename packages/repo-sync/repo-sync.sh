#!/usr/bin/env bash
# repo-sync — Clone-if-absent, fetch/commit/rebase/push for a git repo.
#
# Usage:
#   repo-sync --repo <url> --path <dir> --commit-prefix "vault sync" --log-dir <dir>
#
# REQ-009: Shared sync script for both human notes and agent notes.
# Portable: bash + git + coreutils + findutils + openssh only.
#
# TODO: REQ-009.15 — macOS support via launchd plist generation.
# The sync script itself is portable (bash + git + coreutils).
# Only the timer mechanism differs: systemd on Linux, launchd on macOS.

set -eo pipefail

# ── Parse arguments ────────────────────────────────────────────────
REPO=""
SYNC_PATH=""
COMMIT_PREFIX="vault sync"
LOG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="$2"; shift 2 ;;
    --path)    SYNC_PATH="$2"; shift 2 ;;
    --commit-prefix) COMMIT_PREFIX="$2"; shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Error: --repo is required" >&2
  exit 1
fi

if [[ -z "$SYNC_PATH" ]]; then
  echo "Error: --path is required" >&2
  exit 1
fi

if [[ -z "$LOG_DIR" ]]; then
  LOG_DIR="$(dirname "$SYNC_PATH")/.local/state/repo-sync/logs"
fi

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOG_DIR/$TIMESTAMP.log"
META_FILE="$LOG_DIR/$TIMESTAMP.json"
START_TIME=$(date +%s)

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ── Atomic directory lock with stale cleanup (REQ-009.9) ───────────
LOCKFILE="$LOG_DIR/../sync.lock"
mkdir -p "$(dirname "$LOCKFILE")"

if mkdir "$LOCKFILE" 2>/dev/null; then
  echo $$ > "$LOCKFILE/pid"
  trap 'rm -rf "$LOCKFILE"' EXIT
else
  # Check for stale lock
  if [[ -f "$LOCKFILE/pid" ]]; then
    OLD_PID=$(cat "$LOCKFILE/pid" 2>/dev/null || echo "")
    if [[ -n "$OLD_PID" ]] && ! kill -0 "$OLD_PID" 2>/dev/null; then
      log "Removing stale lock (pid $OLD_PID no longer running)"
      rm -rf "$LOCKFILE"
      mkdir "$LOCKFILE" 2>/dev/null || { echo "Failed to acquire lock after stale cleanup" >&2; exit 0; }
      echo $$ > "$LOCKFILE/pid"
      trap 'rm -rf "$LOCKFILE"' EXIT
    else
      echo "Sync already running (pid $OLD_PID), skipping" >&2
      exit 0
    fi
  else
    echo "Lock exists but no pid file, skipping" >&2
    exit 0
  fi
fi

# ── Clone if path doesn't exist (REQ-009.5) ───────────────────────
if [[ ! -d "$SYNC_PATH" ]]; then
  log "Cloning $REPO to $SYNC_PATH..."
  git clone "$REPO" "$SYNC_PATH" 2>&1 | tee -a "$LOG_FILE"
  log "Clone complete"
fi

cd "$SYNC_PATH"
log "Starting repo sync: $SYNC_PATH"

# ── Fetch from remote (REQ-009.6) ─────────────────────────────────
log "Fetching from origin..."
git fetch origin 2>&1 | tee -a "$LOG_FILE"

# ── Check for local changes ───────────────────────────────────────
LOCAL_CHANGES=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  LOCAL_CHANGES=true
  log "Local changes detected"
fi

UNTRACKED=$(git ls-files --others --exclude-standard)
if [[ -n "$UNTRACKED" ]]; then
  LOCAL_CHANGES=true
  log "Untracked files detected"
fi

# ── Check for upstream changes ────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
UPSTREAM="origin/$CURRENT_BRANCH"

LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse "$UPSTREAM" 2>/dev/null || echo "")

UPSTREAM_CHANGES=false
if [[ -n "$REMOTE_HEAD" ]] && [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  BEHIND=$(git rev-list --count HEAD.."$UPSTREAM" 2>/dev/null || echo "0")
  if [[ "$BEHIND" -gt 0 ]]; then
    UPSTREAM_CHANGES=true
    log "Behind upstream by $BEHIND commits"
  fi
fi

# ── Commit local changes (REQ-009.6, REQ-009.7) ──────────────────
COMMITTED=false
if [[ "$LOCAL_CHANGES" == true ]]; then
  log "Staging all changes..."
  git add -A 2>&1 | tee -a "$LOG_FILE"

  if ! git diff --cached --quiet; then
    COMMIT_MSG="$COMMIT_PREFIX: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Committing: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG" 2>&1 | tee -a "$LOG_FILE"
    COMMITTED=true
  else
    log "Nothing to commit after staging"
  fi
fi

# ── Rebase if upstream has changes (REQ-009.8) ────────────────────
REBASED=false
CONFLICT=false
if [[ "$UPSTREAM_CHANGES" == true ]]; then
  log "Rebasing onto $UPSTREAM..."

  if git rebase "$UPSTREAM" >> "$LOG_FILE" 2>&1; then
    REBASED=true
    log "Rebase successful"
  else
    CONFLICT=true
    log "CONFLICT: Rebase failed - manual intervention required"

    git rebase --abort >> "$LOG_FILE" 2>&1 || true

    STATE_DIR="$LOG_DIR/../state"
    mkdir -p "$STATE_DIR"
    echo "$TIMESTAMP" > "$STATE_DIR/conflict_pending"
    log "Conflict marker written to $STATE_DIR/conflict_pending"
  fi
fi

# ── Push if we have commits to push ───────────────────────────────
PUSHED=false
if [[ "$COMMITTED" == true ]] || [[ "$REBASED" == true ]]; then
  AHEAD=$(git rev-list --count "$UPSTREAM"..HEAD 2>/dev/null || echo "0")
  if [[ "$AHEAD" -gt 0 ]]; then
    log "Pushing $AHEAD commits to origin..."
    if git push origin "$CURRENT_BRANCH" >> "$LOG_FILE" 2>&1; then
      PUSHED=true
      log "Push successful"
    else
      log "Push failed"
    fi
  fi
fi

# ── Summary ───────────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [[ "$CONFLICT" == true ]]; then
  EXIT_CODE=1
  log "Finished with CONFLICT (${DURATION}s)"
else
  EXIT_CODE=0
  log "Finished successfully (${DURATION}s) - committed:$COMMITTED rebased:$REBASED pushed:$PUSHED"
fi

# ── Write metadata (REQ-009.10) ───────────────────────────────────
TIMESTAMP_ISO=$(date -Iseconds)
{
  printf '{\n'
  printf '  "timestamp": "%s",\n' "$TIMESTAMP_ISO"
  printf '  "exit_code": %d,\n' "$EXIT_CODE"
  printf '  "duration_seconds": %d,\n' "$DURATION"
  printf '  "committed": "%s",\n' "$COMMITTED"
  printf '  "rebased": "%s",\n' "$REBASED"
  printf '  "pushed": "%s",\n' "$PUSHED"
  printf '  "conflict": "%s",\n' "$CONFLICT"
  printf '  "branch": "%s"\n' "$CURRENT_BRANCH"
  printf '}\n'
} > "$META_FILE"

# ── Rotate old logs, keep last 10 (REQ-009.11) ───────────────────
for ext in log json; do
  COUNT=0
  find "$LOG_DIR" -maxdepth 1 -name "*.$ext" -type f | sort -r | while IFS= read -r file; do
    COUNT=$((COUNT + 1))
    if [[ $COUNT -gt 10 ]]; then
      rm -f "$file"
    fi
  done
done

exit $EXIT_CODE
