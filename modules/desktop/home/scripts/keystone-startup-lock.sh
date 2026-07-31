#!/usr/bin/env bash
set -u -o pipefail

# SECURITY: This script is the fail-closed gate for the desktop session.
# If the session never reaches a real startup lock state, the entire
# session is terminated rather than exposing an unlocked desktop.
#
# Do NOT treat an early non-zero hyprlock exit as the source of truth.
# During greetd -> uwsm -> Hyprland startup, the compositor may briefly
# reject the lock while outputs are still coming online. The correct
# truth source is a visible lock signal or a stable-running hyprlock
# process after session-lock readiness is established.
poll_interval_seconds="${KEYSTONE_STARTUP_LOCK_POLL_INTERVAL_SECONDS:-0.1}"
timeout_steps="${KEYSTONE_STARTUP_LOCK_TIMEOUT_STEPS:-50}"
readiness_timeout_steps="${KEYSTONE_STARTUP_LOCK_READINESS_TIMEOUT_STEPS:-100}"
stable_lock_steps="${KEYSTONE_STARTUP_LOCK_STABLE_LOCK_STEPS:-20}"

# SECURITY: During session startup (greetd -> uwsm -> Hyprland), the
# compositor may deny the session lock while outputs are being
# reconfigured. We relaunch a limited number of times inside the
# overall startup deadline, but still fail closed unless a lock signal
# appears or hyprlock stays stable after readiness.
max_lock_attempts="${KEYSTONE_STARTUP_LOCK_MAX_ATTEMPTS:-3}"
retry_delay_seconds="${KEYSTONE_STARTUP_LOCK_RETRY_DELAY:-1}"
hyprlock_cmd=(hyprlock)

log() {
  local priority="$1"
  shift
  local message="$*"

  printf 'keystone-startup-lock: %s\n' "$message" >&2

  if command -v systemd-cat >/dev/null 2>&1; then
    printf '%s\n' "$message" | systemd-cat -t keystone-startup-lock -p "$priority"
  fi
}

hyprctl_json() {
  local subcommand="$1"
  local output

  output="$(hyprctl -j "$subcommand" 2>/dev/null)" || return 1
  printf '%s\n' "$output" | jq -e . >/dev/null 2>&1 || return 1
  printf '%s\n' "$output"
}

lock_surface_present() {
  hyprctl_json layers | jq -e '
    .. | objects | select(
      (.namespace? // "") == "hyprlock"
      or (.class? // "") == "hyprlock"
      or (.name? // "") == "hyprlock"
    )
  ' >/dev/null
}

session_lock_ready() {
  hyprctl_json monitors | jq -e 'type == "array" and length > 0' >/dev/null
}

session_locked() {
  if [[ -z "${XDG_SESSION_ID:-}" ]] || ! command -v loginctl >/dev/null 2>&1; then
    return 1
  fi

  [[ "$(loginctl show-session "$XDG_SESSION_ID" -p LockedHint --value 2>/dev/null)" == "yes" ]]
}

lock_ready() {
  session_locked || lock_surface_present
}

lock_process_alive() {
  local pid="$1"
  local state_file="/proc/$pid/stat"
  local state

  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1
  [[ -r "$state_file" ]] || return 1

  state="$(awk '{ print $3 }' "$state_file" 2>/dev/null)" || return 1
  [[ "$state" != "Z" ]]
}

fail_closed() {
  local reason="$1"

  log err "$reason"
  log err "Terminating the desktop session instead of exposing an unlocked desktop."

  pkill -TERM -x hyprlock >/dev/null 2>&1 || true

  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl dispatch exit >/dev/null 2>&1 || true
  fi

  if command -v uwsm >/dev/null 2>&1; then
    uwsm stop >/dev/null 2>&1 || true
  fi

  if [[ -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
    loginctl terminate-session "$XDG_SESSION_ID" >/dev/null 2>&1 || true
  fi

  exit 1
}

wait_for_session_lock_ready() {
  for _ in $(seq 1 "$readiness_timeout_steps"); do
    if session_lock_ready; then
      return 0
    fi

    sleep "$poll_interval_seconds"
  done

  return 1
}

launch_lock() {
  "${hyprlock_cmd[@]}" >/dev/null 2>&1 &
  current_lock_pid=$!
  launch_count=$((launch_count + 1))
  log info "launched hyprlock attempt ${launch_count}/${max_lock_attempts}"
}

current_lock_pid=""
launch_count=0
stable_lock_count=0

if lock_ready; then
  log info "session already reports locked"
  exit 0
fi

if pgrep -x hyprlock >/dev/null 2>&1; then
  log info "hyprlock is already running"
  exit 0
fi

if ! wait_for_session_lock_ready; then
  fail_closed "Hyprland did not become ready for session locking before the startup lock deadline."
fi

log info "session lock prerequisites are ready"

launch_lock

for _ in $(seq 1 "$timeout_steps"); do
  if lock_ready; then
    log info "startup lock is ready"
    exit 0
  fi

  if [[ -n "$current_lock_pid" ]] && lock_process_alive "$current_lock_pid"; then
    stable_lock_count=$((stable_lock_count + 1))

    if [[ "$stable_lock_count" -ge "$stable_lock_steps" ]]; then
      log info "hyprlock remained alive for the startup grace window"
      exit 0
    fi
  else
    stable_lock_count=0
  fi

  if [[ -n "$current_lock_pid" ]] && ! lock_process_alive "$current_lock_pid"; then
    wait "$current_lock_pid"
    lock_status=$?
    current_lock_pid=""

    if [[ "$lock_status" -eq 0 ]]; then
      log info "hyprlock exited cleanly (user authenticated)"
      exit 0
    fi

    if lock_ready; then
      log info "session locked after hyprlock exit"
      exit 0
    fi

    if [[ "$launch_count" -lt "$max_lock_attempts" ]]; then
      log warning "hyprlock exited before lock state was visible, relaunching in ${retry_delay_seconds}s"
      sleep "$retry_delay_seconds"
      wait_for_session_lock_ready || true
      launch_lock
      stable_lock_count=0
      continue
    fi
  fi

  sleep "$poll_interval_seconds"
done

fail_closed "hyprlock failed to make the session report locked after ${launch_count} launch attempts."
