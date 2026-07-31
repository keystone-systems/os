#!/usr/bin/env bash
# keystone-context — Launch or attach to a desktop context
#
# Creates a zellij session directly,
# opens a ghostty window attached to it, and moves it to a named workspace.
#
# Usage: keystone-context <slug> [--layout <name>] [--workspace <num>]

set -euo pipefail

SESSION_PREFIX="obs"
VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"

keystone_cmd() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return 0
  fi

  if [[ -x "$HOME/.local/bin/$command_name" ]]; then
    printf "%s\n" "$HOME/.local/bin/$command_name"
    return 0
  fi

  printf "Unable to locate %s\n" "$command_name" >&2
  exit 1
}

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

detach_with_pid() {
  "$(keystone_cmd keystone-detach)" --print-pid "$@"
}

usage() {
  cat <<'EOF'
keystone-context — Launch or attach to a desktop context

Usage:
  keystone-context <slug> [--layout <name>] [--workspace <num>]

Options:
  --layout <name>      Zellij layout preset: dev, ops, write (default: dev)
  --workspace <num>    Target workspace number (default: next available)
  -h, --help           Show this help message

Examples:
  keystone-context catalyst              # Launch with dev layout
  keystone-context catalyst --layout ops # Launch with ops layout
  keystone-context task-email            # Ad-hoc context (no project dir)
EOF
}

# --- Argument parsing ---
SLUG=""
LAYOUT="dev"
WORKSPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --layout)
      if [[ $# -lt 2 ]]; then
        echo "error: --layout requires a name argument" >&2
        exit 1
      fi
      LAYOUT="$2"
      shift 2
      ;;
    --workspace)
      if [[ $# -lt 2 ]]; then
        echo "error: --workspace requires a number argument" >&2
        exit 1
      fi
      WORKSPACE="$2"
      shift 2
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$SLUG" ]]; then
        SLUG="$1"
      else
        echo "error: unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$SLUG" ]]; then
  echo "error: <slug> is required" >&2
  usage >&2
  exit 1
fi

# Validate slug format
if [[ ! "$SLUG" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "error: invalid slug '${SLUG}'" >&2
  echo "slugs must contain only letters, digits, hyphens, and underscores" >&2
  exit 1
fi

SESSION_NAME="${SESSION_PREFIX}-${SLUG}"

# Check if session already exists
session_exists() {
  zellij list-sessions --no-formatting 2>/dev/null | awk '{print $1}' | grep -qx "${SESSION_NAME}"
}

# Create the zellij session if it doesn't exist
if ! session_exists; then
  local_project_path="${VAULT_ROOT}/projects/${SLUG}"
  if [[ ! -d "$local_project_path" ]]; then
    local_project_path="$VAULT_ROOT"
  fi
  (
    export PROJECT_NAME="${SLUG}"
    export PROJECT_PATH="${local_project_path}"
    export VAULT_ROOT="${VAULT_ROOT}"
    detach zellij --session "${SESSION_NAME}" --layout "$LAYOUT" options --default-cwd "${local_project_path}"
  )

  # Wait briefly for the session to register
  for _ in $(seq 1 20); do
    if session_exists; then
      break
    fi
    sleep 0.1
  done
fi

# Determine target workspace
if [[ -n "$WORKSPACE" ]]; then
  TARGET_WS="$WORKSPACE"
else
  # Use the slug as a named workspace
  TARGET_WS="name:${SLUG}"
fi

# Launch ghostty attached to the session, or focus existing window
# Check if a window with this title already exists on Hyprland
EXISTING_CLIENT=$(hyprctl clients -j | jq -r ".[] | select(.title == \"${SLUG}\") | .address" | head -1)

if [[ -n "$EXISTING_CLIENT" ]]; then
  # Window exists — focus it by switching to its workspace
  EXISTING_WS=$(hyprctl clients -j | jq -r ".[] | select(.address == \"${EXISTING_CLIENT}\") | .workspace.name")
  if [[ -n "$EXISTING_WS" ]]; then
    hyprctl dispatch workspace "name:${SLUG}" >/dev/null 2>&1
  else
    hyprctl dispatch focuswindow "address:${EXISTING_CLIENT}" >/dev/null 2>&1
  fi
else
  # Launch new ghostty window attached to the zellij session
  GHOSTTY_PID=$(detach_with_pid ghostty --title="${SLUG}" -e zellij attach "${SESSION_NAME}")

  # Wait for the window to appear in Hyprland
  for _ in $(seq 1 30); do
    NEW_CLIENT=$(hyprctl clients -j | jq -r ".[] | select(.pid == ${GHOSTTY_PID}) | .address" | head -1)
    if [[ -n "$NEW_CLIENT" ]]; then
      break
    fi
    sleep 0.1
  done

  if [[ -n "${NEW_CLIENT:-}" ]]; then
    # Move window to the target workspace and rename it
    hyprctl dispatch movetoworkspacesilent "${TARGET_WS},address:${NEW_CLIENT}" >/dev/null 2>&1
    hyprctl dispatch workspace "${TARGET_WS}" >/dev/null 2>&1
  fi
fi
