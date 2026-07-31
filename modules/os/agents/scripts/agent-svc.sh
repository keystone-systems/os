#!/usr/bin/env bash
# Per-agent service helper — sole sudoers target for agent-admins.
# SECURITY: Hardcodes XDG_RUNTIME_DIR internally and allowlists safe
# systemctl verbs only to prevent LD_PRELOAD injection.
set -euo pipefail

# Configuration (substituted by NixOS module via pkgs.replaceVars)
AGENT_NAME="@agentName@"
UID_NUM="@uid@"
PATH_PREFIX="@pathPrefix@"

export XDG_RUNTIME_DIR="/run/user/${UID_NUM}"
# CRITICAL: systemctl --user via sudo cannot auto-discover the dbus
# socket. Without this, every agentctl command fails with "Failed to
# connect to user scope bus via local transport: No such file or directory".
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus"
export SSH_AUTH_SOCK="/run/agent-${AGENT_NAME}-ssh-agent/agent.sock"
# SECURITY: Use the agent's own home-manager profile, not the caller's.
# Without this, `agentctl <name> exec` inherits the invoking user's PATH
# (e.g. ncrmro's), breaking all home-manager tools (himalaya, direnv, fj,
# rbw) and devshell tools (deepwork, gh, node) for the agent.
export PATH="$PATH_PREFIX"
# Source home-manager session variables (EDITOR, VISUAL, etc.) so agentctl
# exec inherits whatever keystone.terminal sets — no hardcoded values here.
HM_VARS="/etc/profiles/per-user/agent-${AGENT_NAME}/etc/profile.d/hm-session-vars.sh"
if [ -f "$HM_VARS" ]; then
  # Home Manager's guard is not nounset-safe, so relax -u only for sourcing.
  set +u
  . "$HM_VARS"
  set -u
fi

if [ $# -lt 1 ]; then
  echo "Usage: agent-svc-${AGENT_NAME} <verb> [args...]" >&2
  exit 1
fi

VERB="$1"; shift

case "$VERB" in
  # Safe systemctl verbs
  status|start|stop|restart|enable|disable|list-units|list-timers|show|cat|is-active|is-enabled|is-failed|daemon-reload|reset-failed)
    exec systemctl --user "$VERB" "$@"
    ;;
  # journalctl passthrough
  journalctl)
    exec journalctl --user "$@"
    ;;
  # Run arbitrary command as this agent (for diagnostics)
  exec)
    exec "$@"
    ;;
  *)
    echo "Error: verb '$VERB' is not allowed." >&2
    echo "Allowed: status start stop restart enable disable list-units list-timers show cat is-active is-enabled is-failed daemon-reload reset-failed journalctl exec" >&2
    exit 1
    ;;
esac
