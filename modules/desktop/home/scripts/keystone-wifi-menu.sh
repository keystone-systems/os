#!/usr/bin/env bash
# keystone-wifi-menu — Wi-Fi Walker/Elephant surface driven by nmcli.
#
# Verbs:
#   open-menu        — launch Walker with menus:keystone-wifi
#   list-json        — emit Elephant entries for visible SSIDs
#   dispatch <val>   — handle a selected entry payload
#   summary          — short status blurb for the Setup menu preview
#   preview-blocked  — parity with other menus for blocked entries

set -euo pipefail

notify() {
  notify-send "$@"
}

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

nmcli_available() {
  command -v nmcli >/dev/null 2>&1
}

# Decode nmcli's ':'-escaped terse output field. nmcli escapes ':' and '\'
# in terse (-t) output with a leading backslash.
nmcli_unescape() {
  local s="$1"
  # Replace escaped colons and backslashes.
  printf '%s' "${s//\\:/:}" | sed 's/\\\\/\\/g'
}

# Map a signal strength (0-100) to a Freedesktop network-wireless icon name.
signal_icon() {
  local signal="${1:-0}"
  if ! [[ "$signal" =~ ^[0-9]+$ ]]; then
    signal=0
  fi
  if (( signal >= 80 )); then
    printf "network-wireless-signal-excellent\n"
  elif (( signal >= 55 )); then
    printf "network-wireless-signal-good\n"
  elif (( signal >= 30 )); then
    printf "network-wireless-signal-ok\n"
  elif (( signal > 0 )); then
    printf "network-wireless-signal-weak\n"
  else
    printf "network-wireless-signal-none\n"
  fi
}

current_ssid() {
  nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null \
    | awk -F: '$1=="yes" {$1=""; sub(/^:/, ""); print; exit}'
}

# Return 0 if the SSID has a saved NetworkManager connection profile.
has_saved_connection() {
  local ssid="$1"
  nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$ssid"
}

blocked_entry_json() {
  local title="$1"
  local reason="$2"

  jq -n --arg title "$title" --arg reason "$reason" '
    [
      {
        Text: $title,
        Subtext: $reason,
        Value: "blocked",
        Icon: "network-wireless-offline",
        Preview: ("printf " + (($title + "\n\n" + $reason + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

list_json() {
  if ! nmcli_available; then
    blocked_entry_json "Wi-Fi unavailable" "nmcli is not available in PATH."
    return 0
  fi

  # IN-USE:SSID:SIGNAL:SECURITY — terse output, rescan to refresh.
  local raw
  if ! raw=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan yes 2>/dev/null); then
    blocked_entry_json "Wi-Fi scan failed" "nmcli dev wifi list returned a non-zero status."
    return 0
  fi

  if [[ -z "$raw" ]]; then
    blocked_entry_json "No networks found" "nmcli did not return any visible Wi-Fi networks."
    return 0
  fi

  local entries_json="[]"
  local seen_ssids=""
  local line in_use ssid signal security icon subtext text entry

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # nmcli -t uses ':' as a field separator and escapes literal ':' as '\:'.
    # Split on unescaped ':' by substituting placeholders.
    local placeheld="${line//\\:/$'\x01'}"
    IFS=':' read -r in_use ssid signal security <<<"$placeheld"
    in_use="${in_use//$'\x01'/:}"
    ssid="${ssid//$'\x01'/:}"
    signal="${signal//$'\x01'/:}"
    security="${security//$'\x01'/:}"
    ssid=$(nmcli_unescape "$ssid")
    security=$(nmcli_unescape "$security")

    # Skip hidden networks and duplicates (keep strongest, which appears first).
    [[ -z "$ssid" ]] && continue
    if printf '%s\n' "$seen_ssids" | grep -Fxq "$ssid"; then
      continue
    fi
    seen_ssids+="${ssid}"$'\n'

    icon=$(signal_icon "$signal")

    local marker=""
    [[ "$in_use" == "*" ]] && marker="✓ "

    local sec_label="$security"
    [[ -z "$sec_label" ]] && sec_label="open"

    text="${marker}${ssid}"
    subtext="${signal}%  ·  ${sec_label}"

    entry=$(jq -n \
      --arg text "$text" \
      --arg subtext "$subtext" \
      --arg ssid "$ssid" \
      --arg security "$security" \
      --arg icon "$icon" \
      '{
        Text: $text,
        Subtext: $subtext,
        Value: ("join\t" + $ssid + "\t" + $security),
        Icon: $icon
      }')
    entries_json=$(jq -n --argjson arr "$entries_json" --argjson entry "$entry" '$arr + [$entry]')
  done <<<"$raw"

  # If loop filtered everything out, fall back to a blocked entry.
  if [[ "$entries_json" == "[]" ]]; then
    blocked_entry_json "No networks found" "No visible Wi-Fi SSIDs after filtering."
    return 0
  fi

  printf "%s\n" "$entries_json"
}

# Prompt for a passphrase via walker --dmenu --inputonly --password.
prompt_passphrase() {
  local ssid="$1"
  local walker
  walker=$(keystone_cmd keystone-launch-walker)

  # --password masks input if supported; --inputonly suppresses list items.
  printf '\n' \
    | "$walker" --dmenu --inputonly --password \
        --placeholder "Password for ${ssid}" 2>/dev/null \
    | tr -d '\r\n'
}

join_network() {
  local ssid="$1"
  local security="$2"

  if ! nmcli_available; then
    notify "Wi-Fi unavailable" "nmcli is not available."
    exit 1
  fi

  if has_saved_connection "$ssid"; then
    if nmcli connection up "$ssid" >/dev/null 2>&1; then
      notify "Wi-Fi connected" "$ssid"
      return 0
    else
      notify "Wi-Fi failed" "Could not activate saved connection: $ssid"
      exit 1
    fi
  fi

  # Open network → no passphrase needed.
  if [[ -z "$security" || "$security" == "--" ]]; then
    if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
      notify "Wi-Fi connected" "$ssid"
      return 0
    else
      notify "Wi-Fi failed" "Could not join open network: $ssid"
      exit 1
    fi
  fi

  # Secured network without a saved profile — prompt for passphrase.
  local passphrase
  passphrase=$(prompt_passphrase "$ssid" || true)
  if [[ -z "$passphrase" ]]; then
    notify "Wi-Fi cancelled" "No passphrase entered for $ssid"
    return 0
  fi

  # SECURITY: feed the passphrase on stdin via `nmcli --ask` rather than
  # passing it as a `password <pw>` argv token, which would expose the
  # secret in /proc/<pid>/cmdline for the duration of the connect call.
  if printf '%s\n' "$passphrase" \
       | nmcli --ask device wifi connect "$ssid" >/dev/null 2>&1; then
    notify "Wi-Fi connected" "$ssid"
  else
    notify "Wi-Fi failed" "Could not join $ssid — check the passphrase"
    exit 1
  fi
}

dispatch() {
  local payload="${1:-}"
  local action="" ssid="" security=""

  IFS=$'\t' read -r action ssid security <<<"$payload"

  case "$action" in
    join)
      join_network "$ssid" "$security"
      ;;
    blocked)
      notify "Wi-Fi unavailable" "nmcli is not available on this host."
      ;;
    *)
      printf "Unknown dispatch action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

summary() {
  if ! nmcli_available; then
    printf "Wi-Fi unavailable\nnmcli is not available in PATH.\n"
    return 0
  fi

  local ssid
  ssid=$(current_ssid)

  if [[ -z "$ssid" ]]; then
    printf "Wi-Fi: disconnected\n"
    return 0
  fi

  local signal
  signal=$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null \
    | awk -F: '$1=="yes" {print $2; exit}')
  signal="${signal:-?}"

  printf "Wi-Fi: %s\nSignal: %s%%\n" "$ssid" "$signal"
}

preview_blocked() {
  local title="$1"
  local message="$2"

  printf "%s\n\n%s\n" "$title" "$message"
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-wifi -p "Wi-Fi" >/dev/null 2>&1 &
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  list-json)
    shift
    list_json "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  preview-blocked)
    shift
    preview_blocked "$@"
    ;;
  *)
    echo "Usage: keystone-wifi-menu {open-menu|list-json|dispatch|summary|preview-blocked} ..." >&2
    exit 1
    ;;
esac
