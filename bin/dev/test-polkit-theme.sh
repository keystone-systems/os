#!/usr/bin/env bash
# Smoke-test the keystone hyprpolkitagent dialog against one or more
# keystone themes. The whole point is to test the THEME FILES AND
# the keystone-write-polkit-theme binary FROM THE CURRENT BRANCH'S
# WORKING TREE — not whatever the activated keystone happens to ship
# — so a developer can iterate on a theming change without
# `ks update --approve`. The binary built and invoked here is the
# same one production uses, so no logic drift.
#
# Validates that:
#   1. keystone-write-polkit-theme emits valid JSON
#   2. hyprpolkitagent restarts cleanly (no QML parse errors,
#      no QQuickStyle fallback chain, no XHR file-read denial)
#   3. The dialog renders and pkexec round-trips a no-op activation
#   4. (Interactive only) the user confirms the dialog looks right
#
# Theme source resolution:
#   - Custom themes (royal-green, etc.) — read from
#     $REPO_ROOT/modules/desktop/home/theming/themes/<name>/.
#   - Omarchy themes (tokyo-night, kanagawa, etc.) — read from the
#     branch's flake-locked omarchy input, resolved via `nix eval`.
#   - Override either with KEYSTONE_THEMES_DIRS or --themes-dir.
#
# Caveats:
#   - The hyprpolkitagent restart uses the ACTIVATED agent (we can't
#     swap the QML without a rebuild). This is fine for theme-only
#     changes; for QML changes, `ks update --approve --keystone path:…`
#     against the branch first, then run this.
#
# Usage:
#   bin/dev/test-polkit-theme.sh                 # current theme, interactive
#   bin/dev/test-polkit-theme.sh --theme NAME    # specific theme
#   bin/dev/test-polkit-theme.sh --all           # iterate every theme
#   bin/dev/test-polkit-theme.sh --headless      # no visual confirmation
#   bin/dev/test-polkit-theme.sh --reset         # restore live polkit.json
#   bin/dev/test-polkit-theme.sh --repo PATH     # use a different keystone checkout
#
# Notes:
#   - Edits ~/.config/keystone/current/polkit.json in place. The original
#     is snapshotted to ${LIVE_THEME}.test-snapshot and restored on EXIT,
#     INT, TERM. Run --reset if a previous run was killed mid-test.
#   - Uses pkexec directly (not `ks approve`) so a missing graphical
#     session doesn't fall back to a tty password prompt.
#   - The pkexec target is `ks activate /run/current-system`, which the
#     allowlist accepts and which is a no-op against the running system.

set -u
set -o pipefail

LIVE_THEME=${KEYSTONE_POLKIT_THEME:-$HOME/.config/keystone/current/polkit.json}
SNAPSHOT="${LIVE_THEME}.test-snapshot"
LOG_DIR=${KEYSTONE_POLKIT_TEST_LOG_DIR:-$HOME/.cache/keystone-polkit-tests}
LOG_FILE="$LOG_DIR/log"
HELPER=${KEYSTONE_APPROVE_EXEC:-/run/current-system/sw/bin/keystone-approve-exec}
PKEXEC=${PKEXEC_BIN:-/run/wrappers/bin/pkexec}
AGENT_UNIT=hyprpolkitagent.service

THEME_ARG=""
RUN_ALL=0
HEADLESS=0
RESET=0
REPO_ARG="${KEYSTONE_REPO:-}"
THEMES_DIRS_OVERRIDE="${KEYSTONE_THEMES_DIRS:-}"

usage() {
  sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)        THEME_ARG="${2:-}"; shift 2 ;;
    --theme=*)      THEME_ARG="${1#--theme=}"; shift ;;
    --all)          RUN_ALL=1; shift ;;
    --headless)     HEADLESS=1; shift ;;
    --reset)        RESET=1; shift ;;
    --repo)         REPO_ARG="${2:-}"; shift 2 ;;
    --repo=*)       REPO_ARG="${1#--repo=}"; shift ;;
    --themes-dir)   THEMES_DIRS_OVERRIDE="${2:-}"; shift 2 ;;
    --themes-dir=*) THEMES_DIRS_OVERRIDE="${1#--themes-dir=}"; shift ;;
    -h|--help)      usage 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage 1
      ;;
  esac
done

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$LOG_FILE"
}

# Locate the keystone repo root. We need it for both the custom-theme
# files and to nix-eval the branch's pinned omarchy input. Resolution
# chain: --repo PATH > $KEYSTONE_REPO > git rev-parse from $PWD > fail.
# Errors abort the script directly (not via a function and command
# substitution, which would only kill the subshell).
REPO_ROOT="$REPO_ARG"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
fi
if [[ -z "$REPO_ROOT" ]]; then
  echo "error: pass --repo PATH or run from inside the keystone repo" >&2
  exit 2
fi
if [[ ! -f "$REPO_ROOT/flake.nix" ]] \
   || [[ ! -d "$REPO_ROOT/modules/desktop/home/theming" ]]; then
  echo "error: $REPO_ROOT does not look like a keystone checkout" >&2
  echo "       (cd into the keystone checkout, or pass --repo PATH)" >&2
  exit 2
fi

CUSTOM_THEMES_DIR="$REPO_ROOT/modules/desktop/home/theming/themes"

# Resolve the omarchy themes directory by nix-eval-ing the flake's
# locked input. Cached for the duration of this run because the eval
# is the slow part (~1-2 s on a warm store).
OMARCHY_THEMES_DIR=""
resolve_omarchy_themes_dir() {
  if [[ -n "$OMARCHY_THEMES_DIR" ]]; then
    printf '%s\n' "$OMARCHY_THEMES_DIR"
    return 0
  fi
  local out
  out=$(nix --extra-experimental-features 'nix-command flakes' \
        eval --raw --impure \
        --expr "(builtins.getFlake \"git+file://$REPO_ROOT\").inputs.omarchy.outPath" \
        2>/dev/null) || return 1
  if [[ -z "$out" || ! -d "$out/themes" ]]; then
    return 1
  fi
  OMARCHY_THEMES_DIR="$out/themes"
  printf '%s\n' "$OMARCHY_THEMES_DIR"
}

restore_snapshot() {
  if [[ -f "$SNAPSHOT" ]]; then
    mv "$SNAPSHOT" "$LIVE_THEME"
    systemctl --user restart "$AGENT_UNIT" 2>/dev/null || true
    log "snapshot restored to $LIVE_THEME"
  fi
}

# Reset mode: just restore and exit. Useful if a previous run died
# without unwinding (ctrl-c during the visual prompt, killed terminal,
# etc).
if [[ "$RESET" -eq 1 ]]; then
  if [[ -f "$SNAPSHOT" ]]; then
    restore_snapshot
    echo "polkit.json restored from snapshot"
  else
    echo "no snapshot at $SNAPSHOT; nothing to restore"
  fi
  exit 0
fi

trap restore_snapshot EXIT INT TERM

# Build the branch's keystone-write-polkit-theme binary once and call it
# per theme. This is the same binary that production
# (keystone-theme-switch + the home-manager activation hook) invokes,
# so what the test exercises is byte-for-byte what ships. No more
# in-script port to drift from the Nix definition.
WPT_BIN=""

ensure_wpt_bin() {
  [[ -n "$WPT_BIN" ]] && return 0

  log "  building keystone-write-polkit-theme from branch..."
  local store_path
  if ! store_path=$(nix build "path:$REPO_ROOT#write-polkit-theme" --no-link --print-out-paths 2>&1); then
    log "  ERROR: failed to build write-polkit-theme from $REPO_ROOT"
    log "  This branch must include packages/write-polkit-theme/ — if the"
    log "  branch was cut before that package landed, rebase onto main."
    log "$store_path"
    return 1
  fi
  WPT_BIN="$store_path/bin/keystone-write-polkit-theme"
}

write_polkit_theme() {
  ensure_wpt_bin || return 1
  "$WPT_BIN" "$1" "$2"
}

# Theme directory search path, in priority order. Custom themes (the
# branch's checked-in `royal-green` etc.) win over omarchy because if
# both ever defined the same name, custom is the override.
theme_search_dirs() {
  if [[ -n "$THEMES_DIRS_OVERRIDE" ]]; then
    printf '%s\n' "$THEMES_DIRS_OVERRIDE" | tr ':' '\n'
    return 0
  fi
  printf '%s\n' "$CUSTOM_THEMES_DIR"
  local omarchy
  if omarchy=$(resolve_omarchy_themes_dir); then
    printf '%s\n' "$omarchy"
  fi
}

resolve_theme_dir() {
  local name="$1"
  local dir
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    if [[ -d "$dir/$name" ]]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done < <(theme_search_dirs)
  return 1
}

# Best-effort detection of the currently-active theme name from the
# user's home-manager symlink. Used only as a default for "no args"
# invocations; it doesn't constrain which themes can be tested.
current_theme_name() {
  local link="${KEYSTONE_CURRENT_LINK:-$HOME/.config/keystone/current/theme}"
  if [[ -L "$link" ]]; then
    basename "$(readlink -f "$link")"
  else
    echo ""
  fi
}

run_one() {
  local theme_name="$1"
  local theme_dir
  theme_dir="$(resolve_theme_dir "$theme_name")" || {
    local search
    search=$(theme_search_dirs | paste -sd ':' -)
    log "FAIL [$theme_name]: theme directory not found (searched: $search)"
    return 1
  }

  log "==> testing theme: $theme_name (path: $theme_dir)"

  # Step 1: regenerate polkit.json from theme.
  if ! write_polkit_theme "$theme_dir" "$LIVE_THEME"; then
    log "FAIL [$theme_name]: write_polkit_theme failed"
    return 1
  fi
  log "  generated $LIVE_THEME"

  # Step 2: validate JSON shape.
  local missing
  missing=$(jq -r '
    ["background","surface","border","accent","text","mutedText","placeholder","error","light"]
    - (keys)
    | .[]
  ' "$LIVE_THEME" 2>/dev/null) || {
    log "FAIL [$theme_name]: polkit.json is not valid JSON"
    return 1
  }
  if [[ -n "$missing" ]]; then
    log "FAIL [$theme_name]: polkit.json missing keys: $(tr '\n' ' ' <<<"$missing")"
    return 1
  fi
  log "  json validated (all keys present)"

  # Echo the colors so a reviewer can sanity-check them against the
  # theme files without opening jq separately.
  jq -r '"  bg=\(.background) surface=\(.surface) border=\(.border) text=\(.text)"' "$LIVE_THEME" \
    | tee -a "$LOG_FILE"

  # Step 3: restart agent and capture stderr from the journal.
  # reset-failed first so that rapid iteration in --all doesn't trip
  # systemd's StartLimitBurst (default 5 restarts / 10s).
  local start_ts
  start_ts=$(date '+%Y-%m-%d %H:%M:%S')
  systemctl --user reset-failed "$AGENT_UNIT" 2>/dev/null || true
  if ! systemctl --user restart "$AGENT_UNIT"; then
    log "FAIL [$theme_name]: failed to restart $AGENT_UNIT"
    return 1
  fi
  # Brief settle before pkexec talks to the agent on the user bus.
  sleep 1

  # Step 4: scan the agent journal for known-bad signals. We tolerate
  # the kvantum platformtheme line because it's a noisy-but-harmless
  # init message in the upstream Qt build.
  local agent_errors
  agent_errors=$(journalctl --user -u "$AGENT_UNIT" --since "$start_ts" --no-pager 2>&1 \
    | grep -E 'QQuickStyle|file:.*XMLHttpRequest|qrc:/main\.qml.*Error|Cannot read property|QML.*ReferenceError' \
    || true)
  if [[ -n "$agent_errors" ]]; then
    log "FAIL [$theme_name]: agent reported QML/style errors:"
    printf '%s\n' "$agent_errors" | sed 's/^/    /' | tee -a "$LOG_FILE"
    return 1
  fi
  log "  agent restart clean (no QML/style errors in journal)"

  # Step 5: trigger an actual auth dialog. If --headless, skip — the
  # checks above already prove the agent reads the theme without
  # blowing up. Visual confirmation is opt-in because it requires the
  # user's password.
  if [[ "$HEADLESS" -eq 1 ]]; then
    log "PASS [$theme_name] (headless)"
    return 0
  fi

  if [[ ! -x "$HELPER" || ! -x "$PKEXEC" ]]; then
    log "FAIL [$theme_name]: pkexec or keystone-approve-exec missing"
    log "  HELPER=$HELPER PKEXEC=$PKEXEC"
    return 1
  fi

  echo
  echo "  >>> A polkit dialog should appear for theme '$theme_name'."
  echo "      Check: background, border, text colors, gold accent on Authenticate."
  echo "      Cancel the dialog if you don't want to type your password —"
  echo "      a pkexec exit of 126/127 still proves render."
  echo

  local pkexec_start
  pkexec_start=$(date '+%Y-%m-%d %H:%M:%S')
  set +e
  "$PKEXEC" "$HELPER" --reason "polkit-theme-test ($theme_name)" -- ks activate /run/current-system
  local pkexec_exit=$?
  set -e
  log "  pkexec exited $pkexec_exit"

  # Re-check the journal for errors that surfaced *during* the dialog,
  # which is when the QML actually paints.
  agent_errors=$(journalctl --user -u "$AGENT_UNIT" --since "$pkexec_start" --no-pager 2>&1 \
    | grep -E 'qrc:/main\.qml.*Error|Cannot read property|QML.*ReferenceError|XMLHttpRequest.*forbidden' \
    || true)
  if [[ -n "$agent_errors" ]]; then
    log "FAIL [$theme_name]: agent reported QML errors during dialog:"
    printf '%s\n' "$agent_errors" | sed 's/^/    /' | tee -a "$LOG_FILE"
    return 1
  fi

  echo
  read -r -p "  Did the dialog render correctly for '$theme_name'? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) log "PASS [$theme_name] (user-confirmed)"; return 0 ;;
    *)           log "FAIL [$theme_name]: user reported visual problem"; return 1 ;;
  esac
}

# Snapshot current polkit.json once so multiple theme iterations don't
# clobber each other and a final restore reaches the user's real theme.
if [[ -f "$LIVE_THEME" && ! -f "$SNAPSHOT" ]]; then
  cp "$LIVE_THEME" "$SNAPSHOT"
  log "snapshot created at $SNAPSHOT"
fi

# Build the theme list. For --all, deduplicate names across the search
# path so a custom-overridden theme is tested once (against its custom
# definition).
declare -a THEMES
if [[ "$RUN_ALL" -eq 1 ]]; then
  declare -A seen=()
  while IFS= read -r dir; do
    [[ -z "$dir" || ! -d "$dir" ]] && continue
    while IFS= read -r name; do
      if [[ -z "${seen[$name]:-}" ]]; then
        THEMES+=("$name")
        seen["$name"]=1
      fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  done < <(theme_search_dirs)
  if [[ "${#THEMES[@]}" -eq 0 ]]; then
    echo "error: no themes found; check --repo and --themes-dir" >&2
    exit 2
  fi
elif [[ -n "$THEME_ARG" ]]; then
  THEMES=("$THEME_ARG")
else
  current="$(current_theme_name)"
  if [[ -z "$current" ]]; then
    echo "error: no active theme detected; pass --theme NAME or --all" >&2
    exit 2
  fi
  THEMES=("$current")
fi

log "==> run started (repo=$REPO_ROOT, themes: ${THEMES[*]}, headless=$HEADLESS)"

failures=0
for theme in "${THEMES[@]}"; do
  if ! run_one "$theme"; then
    failures=$((failures + 1))
  fi
done

log "==> run finished: ${#THEMES[@]} tested, $failures failed"

# Trap restores the snapshot on exit — no manual restore needed.
exit "$failures"
