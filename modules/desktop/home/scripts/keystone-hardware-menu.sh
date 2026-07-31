#!/usr/bin/env bash
# keystone-hardware-menu — Hardware security and disk unlock controller.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-hardware-menu"
mkdir -p "$STATE_DIR"

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

shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

blocked_entry_json() {
  local title="$1"
  local reason="$2"

  jq -n --arg title "$title" --arg reason "$reason" '
    [
      {
        Text: $title,
        Subtext: $reason,
        Value: ("blocked\t" + $title + "\t" + $reason),
        Preview: ("printf " + (($title + "\n\n" + $reason + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

bool_label() {
  if [[ "$1" == "true" ]]; then
    printf "enabled"
  else
    printf "not enrolled"
  fi
}

secure_boot_status() {
  if ! command -v bootctl >/dev/null 2>&1; then
    printf '{"available":false,"summary":"bootctl unavailable","detail":"bootctl is not available in PATH."}\n'
    return 0
  fi

  local output status_line
  output=$(bootctl status 2>/dev/null || true)
  status_line=$(printf "%s\n" "$output" | awk -F: '/Secure Boot:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')

  jq -n --arg available "true" --arg summary "${status_line:-unknown}" --arg detail "$output" '
    {
      available: ($available == "true"),
      summary: $summary,
      detail: $detail
    }
  '
}

sbctl_status_json() {
  if ! command -v sbctl >/dev/null 2>&1; then
    printf '{"available":false,"summary":"sbctl unavailable","detail":"sbctl is not available in PATH."}\n'
    return 0
  fi

  local output setup_mode secure_boot
  output=$(sbctl status 2>/dev/null || true)
  setup_mode=$(printf "%s\n" "$output" | awk -F'\t' '/Setup Mode:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
  secure_boot=$(printf "%s\n" "$output" | awk -F'\t' '/Secure Boot:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')

  jq -n --arg available "true" --arg summary "${secure_boot:-unknown}" --arg setup "${setup_mode:-unknown}" --arg detail "$output" '
    {
      available: ($available == "true"),
      summary: $summary,
      setup: $setup,
      detail: $detail
    }
  '
}

tpm_device_json() {
  if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
    printf '{"available":false,"summary":"systemd-cryptenroll unavailable","detail":"systemd-cryptenroll is not available in PATH."}\n'
    return 0
  fi

  local output first_path
  output=$(systemd-cryptenroll --tpm2-device=list 2>/dev/null || true)
  first_path=$(printf "%s\n" "$output" | awk '/^\/dev\// {print $1; exit}')

  jq -n --arg path "${first_path:-}" --arg detail "$output" '
    {
      available: ($path != ""),
      path: $path,
      detail: $detail
    }
  '
}

fido2_device_json() {
  if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
    printf '{"available":false,"summary":"systemd-cryptenroll unavailable","detail":"systemd-cryptenroll is not available in PATH."}\n'
    return 0
  fi

  local output first_path first_product
  output=$(systemd-cryptenroll --fido2-device=list 2>/dev/null || true)
  first_path=$(printf "%s\n" "$output" | awk '/^\/dev\// {print $1; exit}')
  first_product=$(printf "%s\n" "$output" | awk '/^\/dev\// {print $3; exit}')

  jq -n --arg path "${first_path:-}" --arg product "${first_product:-}" --arg detail "$output" '
    {
      available: ($path != ""),
      path: $path,
      product: $product,
      detail: $detail
    }
  '
}

disk_unlock_status_json() {
  local status_file="/var/lib/keystone/disk-unlock-status.json"

  if [[ -r "$status_file" ]]; then
    cat "$status_file"
    return 0
  fi

  jq -n '
    {
      checked_at: "",
      device: "unknown",
      tpm_enrolled: false,
      fido2_enrolled: false
    }
  '
}

summary() {
  local secure_boot sbctl tpm_device fido2_device disk_status
  secure_boot=$(secure_boot_status)
  sbctl=$(sbctl_status_json)
  tpm_device=$(tpm_device_json)
  fido2_device=$(fido2_device_json)
  disk_status=$(disk_unlock_status_json)

  jq -nr \
    --argjson secure_boot "$secure_boot" \
    --argjson sbctl "$sbctl" \
    --argjson tpm_device "$tpm_device" \
    --argjson fido2_device "$fido2_device" \
    --argjson disk_status "$disk_status" '
    [
      "Hardware",
      "",
      ("Secure Boot: " + ($secure_boot.summary // "unknown")),
      ("sbctl: " + ($sbctl.summary // "unknown")),
      ("TPM device: " + (if $tpm_device.available then ($tpm_device.path // "present") else "not detected" end)),
      ("FIDO2 device: " + (if $fido2_device.available then (($fido2_device.product // "present") + " (" + ($fido2_device.path // "") + ")") else "not detected" end)),
      ("TPM disk unlock: " + (if ($disk_status.tpm_enrolled // false) then "enrolled" else "not enrolled" end)),
      ("FIDO2 disk unlock: " + (if ($disk_status.fido2_enrolled // false) then "enrolled" else "not enrolled" end))
    ]
    | join("\n")
  '
}

entries_json() {
  local hardware_menu secure_boot sbctl tpm_device fido2_device disk_status
  hardware_menu=$(keystone_cmd keystone-hardware-menu)
  secure_boot=$(secure_boot_status)
  sbctl=$(sbctl_status_json)
  tpm_device=$(tpm_device_json)
  fido2_device=$(fido2_device_json)
  disk_status=$(disk_unlock_status_json)

  jq -n \
    --arg hardware_menu "$hardware_menu" \
    --argjson secure_boot "$secure_boot" \
    --argjson sbctl "$sbctl" \
    --argjson tpm_device "$tpm_device" \
    --argjson fido2_device "$fido2_device" \
    --argjson disk_status "$disk_status" '
    [
      {
        Text: "Secure Boot",
        Subtext: ($secure_boot.summary // "unknown"),
        Value: ("blocked\tSecure Boot\t" + ($secure_boot.summary // "unknown")),
        Preview: ($hardware_menu + " preview secure-boot"),
        PreviewType: "command"
      },
      {
        Text: "TPM disk unlock",
        Subtext: (if ($disk_status.tpm_enrolled // false) then "TPM token enrolled" else "TPM token not enrolled" end),
        Value: ("blocked\tTPM disk unlock\t" + (if ($disk_status.tpm_enrolled // false) then "TPM token enrolled" else "TPM token not enrolled" end)),
        Preview: ($hardware_menu + " preview tpm"),
        PreviewType: "command"
      },
      {
        Text: "FIDO2 disk unlock",
        Subtext: (if ($disk_status.fido2_enrolled // false) then "Hardware key enrolled" else "Hardware key not enrolled" end),
        Value: ("blocked\tFIDO2 disk unlock\t" + (if ($disk_status.fido2_enrolled // false) then "Hardware key enrolled" else "Hardware key not enrolled" end)),
        Preview: ($hardware_menu + " preview fido2"),
        PreviewType: "command"
      },
      {
        Text: "Connected hardware key",
        Subtext: (if $fido2_device.available then (($fido2_device.product // "FIDO2 device") + " · " + ($fido2_device.path // "")) else "No FIDO2 hardware key detected" end),
        Value: ("blocked\tHardware key\t" + (if $fido2_device.available then (($fido2_device.product // "FIDO2 device") + " connected") else "No FIDO2 hardware key detected" end)),
        Preview: ($hardware_menu + " preview device"),
        PreviewType: "command"
      },
      {
        Text: "Enroll hardware key for disk unlock",
        Subtext: "Start an interactive FIDO2 enrollment terminal",
        Value: "enroll-fido2",
        Preview: ($hardware_menu + " preview enroll"),
        PreviewType: "command"
      }
    ]
  '
}

preview() {
  local topic="${1:-summary}"

  case "$topic" in
    secure-boot)
      secure_boot_status | jq -r '.detail // .summary // "Unknown Secure Boot state"'
      ;;
    tpm)
      summary
      ;;
    fido2)
      summary
      ;;
    device)
      fido2_device_json | jq -r '.detail // "No FIDO2 device detected"'
      ;;
    enroll)
      cat <<'EOF'
Enroll hardware key for disk unlock

This action opens a detached terminal and runs:
  ks approve --reason "Enroll a hardware key for disk unlock." -- keystone-enroll-fido2 --auto

The flow will show a desktop approval popup when available, then continue in the
terminal for any LUKS password, FIDO2 PIN, or touch confirmation prompts.
EOF
      ;;
    *)
      summary
      ;;
  esac
}

launch_enroll_terminal() {
  local enroll_cmd ghostty_cmd shell_cmd
  enroll_cmd="$(keystone_cmd keystone-enroll-fido2)"
  ghostty_cmd="$(keystone_cmd ghostty)"
  printf -v shell_cmd 'printf "Starting hardware-key disk unlock enrollment...\\n\\n"; exec ks approve --reason %q -- %q --auto' \
    "Enroll a hardware key for disk unlock." \
    "$enroll_cmd"
  detach "$ghostty_cmd" -e bash -lc "$shell_cmd"
}

dispatch() {
  local payload="${1:-}"
  local action="" title="" message=""

  IFS=$'\t' read -r action title message <<<"$payload"

  case "$action" in
    enroll-fido2)
      launch_enroll_terminal
      ;;
    blocked)
      notify "$title" "$message"
      ;;
    *)
      printf "Unknown hardware action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-hardware -p "Hardware" >/dev/null 2>&1 &
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
  summary)
    shift
    summary "$@"
    ;;
  preview)
    shift
    preview "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-hardware-menu {open-menu|entries-json|summary|preview|dispatch} ..." >&2
    exit 1
    ;;
esac
