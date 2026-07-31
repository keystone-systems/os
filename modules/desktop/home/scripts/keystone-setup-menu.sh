#!/usr/bin/env bash
# keystone-setup-menu — Desktop setup entrypoint for Walker/Elephant.

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

entries_json() {
  local audio_menu monitor_menu hardware_menu fingerprint_menu accounts_menu printer_menu setup_menu secrets_menu wifi_menu
  local current_flake="" show_secrets=false
  audio_menu=$(keystone_cmd keystone-audio-menu)
  monitor_menu=$(keystone_cmd keystone-monitor-menu)
  hardware_menu=$(keystone_cmd keystone-hardware-menu)
  fingerprint_menu=$(keystone_cmd keystone-fingerprint-menu)
  accounts_menu=$(keystone_cmd keystone-accounts-menu)
  printer_menu=$(keystone_cmd keystone-printer-menu)
  setup_menu=$(keystone_cmd keystone-setup-menu)
  secrets_menu=$(keystone_cmd keystone-secrets-menu)
  wifi_menu=$(keystone_cmd keystone-wifi-menu)

  current_flake=""
  local _pointer_file="${KEYSTONE_SYSTEM_FLAKE_POINTER_FILE:-/run/current-system/keystone-system-flake}"
  if [[ -r "$_pointer_file" ]]; then
    current_flake="$(tr -d '\n' < "$_pointer_file" 2>/dev/null || true)"
  fi
  if [[ -d "$HOME/.keystone/repos/ncrmro/agenix-secrets" ]]; then
    show_secrets=true
  elif [[ -n "$current_flake" && -d "$current_flake/agenix-secrets" ]]; then
    show_secrets=true
  fi

  jq -n '
    [
      {
        Text: "Audio",
        Subtext: "Default output and input devices",
        Value: "audio",
        SubMenu: "keystone-audio",
        Preview: ($audio_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Monitors",
        Subtext: "Scaling, resolution, orientation, and layout",
        Value: "monitors",
        SubMenu: "keystone-monitors",
        Preview: ($monitor_menu + " preview-setup"),
        PreviewType: "command"
      },
      {
        Text: "Printer",
        Subtext: "Default CUPS printer",
        Value: "printer",
        SubMenu: "keystone-printer",
        Preview: ($printer_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Hardware",
        Subtext: "Secure Boot, TPM, and hardware-key disk unlock",
        Value: "hardware",
        SubMenu: "keystone-hardware",
        Preview: ($hardware_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Fingerprint",
        Subtext: "Enroll, verify, and delete fingerprints",
        Value: "fingerprint",
        SubMenu: "keystone-fingerprint",
        Preview: ($fingerprint_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Accounts",
        Subtext: "Configured mail and calendar accounts",
        Value: "accounts",
        SubMenu: "keystone-accounts",
        Preview: ($accounts_menu + " summary"),
        PreviewType: "command"
      },
      (if $show_secrets then
        {
          Text: "Secrets",
          Subtext: "Agenix secret categories, recipients, and rekey flows",
          Value: "secrets",
          SubMenu: "keystone-secrets",
          Preview: ($secrets_menu + " summary"),
          PreviewType: "command"
        }
      else empty end),
      {
        Text: "Wifi",
        Subtext: "Scan, join, and manage Wi-Fi networks",
        Value: "wifi",
        SubMenu: "keystone-wifi",
        Preview: ($wifi_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Bluetooth",
        Subtext: "Controller not implemented yet",
        Value: "blocked\tBluetooth\tBluetooth setup is not implemented yet.",
        Preview: ($setup_menu + " preview-blocked " + ("Bluetooth" | @sh) + " " + ("Bluetooth setup is not implemented yet." | @sh)),
        PreviewType: "command"
      }
    ]
  ' \
    --arg audio_menu "$audio_menu" \
    --arg monitor_menu "$monitor_menu" \
    --arg hardware_menu "$hardware_menu" \
    --arg fingerprint_menu "$fingerprint_menu" \
    --arg accounts_menu "$accounts_menu" \
    --arg printer_menu "$printer_menu" \
    --arg setup_menu "$setup_menu" \
    --arg secrets_menu "$secrets_menu" \
    --arg wifi_menu "$wifi_menu" \
    --argjson show_secrets "$show_secrets"
}

preview_blocked() {
  local title="$1"
  local message="$2"

  printf "%s\n\n%s\n" "$title" "$message"
}

dispatch() {
  local payload="${1:-}"
  local action="" title="" message=""

  IFS=$'\t' read -r action title message <<<"$payload"

  case "$action" in
    audio | monitors | printer | hardware | fingerprint | accounts | secrets | wifi)
      ;;
    blocked)
      notify "$title" "$message"
      ;;
    *)
      printf "Unknown setup action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-setup -p "Setup" >/dev/null 2>&1 &
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  entries-json)
    shift
    entries_json "$@"
    ;;
  preview-blocked)
    shift
    preview_blocked "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-setup-menu {open-menu|entries-json|preview-blocked|dispatch} ..." >&2
    exit 1
    ;;
esac
