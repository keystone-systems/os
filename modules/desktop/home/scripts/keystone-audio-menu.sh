#!/usr/bin/env bash
# keystone-audio-menu — Audio default controller for terminal and Elephant.

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

shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

require_audio_cli() {
  command -v pactl >/dev/null 2>&1 || {
    printf "pactl is required but not available in PATH\n" >&2
    exit 1
  }
}

audio_cli_available() {
  command -v pactl >/dev/null 2>&1
}

audio_unavailable_reason() {
  if ! audio_cli_available; then
    printf "pactl is not available in PATH.\n"
    return 0
  fi

  printf "Audio defaults are unavailable.\n"
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
        Preview: ("printf " + (($title + "\n\n" + $reason + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

device_type_label() {
  case "$1" in
    output) printf "Output\n" ;;
    input) printf "Input\n" ;;
    *) printf "%s\n" "$1" ;;
  esac
}

devices_json_raw() {
  local kind="$1"
  require_audio_cli

  case "$kind" in
    output)
      pactl -f json list sinks \
        | jq '
            [
              .[]
              | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))
            ]
          '
      ;;
    input)
      pactl -f json list sources \
        | jq '
            [
              .[]
              | select((.name | endswith(".monitor")) | not)
              | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))
            ]
          '
      ;;
    *)
      printf "Unknown audio kind: %s\n" "$kind" >&2
      exit 1
      ;;
  esac
}

default_device_name() {
  local kind="$1"
  require_audio_cli

  case "$kind" in
    output) pactl get-default-sink ;;
    input) pactl get-default-source ;;
    *)
      printf "Unknown audio kind: %s\n" "$kind" >&2
      exit 1
      ;;
  esac
}

device_json() {
  local kind="$1"
  local name="$2"

  devices_json_raw "$kind" | jq -c --arg name "$name" 'map(select(.name == $name)) | first'
}

require_device_json() {
  local kind="$1"
  local name="$2"
  local device=""

  device=$(device_json "$kind" "$name")
  if [[ -z "$device" || "$device" == "null" ]]; then
    printf "Unknown %s device: %s\n" "$kind" "$name" >&2
    exit 1
  fi

  printf "%s\n" "$device"
}

device_description() {
  local kind="$1"
  local name="$2"

  require_device_json "$kind" "$name" \
    | jq -r '.description // .properties."device.description" // .name'
}

current_default_description() {
  local kind="$1"
  local name=""

  name=$(default_device_name "$kind")
  if [[ -z "$name" ]]; then
    printf "No default %s device\n" "$kind"
    return 0
  fi

  device_description "$kind" "$name"
}

categories_json() {
  local audio_menu
  audio_menu=$(keystone_cmd keystone-audio-menu)

  if ! audio_cli_available; then
    blocked_entry_json "Audio unavailable" "$(audio_unavailable_reason)"
    return 0
  fi

  jq -n \
    --arg audio_menu "$audio_menu" \
    --arg default_output "$(current_default_description output)" \
    --arg default_input "$(current_default_description input)" '
      [
        {
          Text: "Output defaults",
          Subtext: $default_output,
          Value: "output",
          SubMenu: "keystone-audio-devices",
          Preview: ($audio_menu + " preview-kind " + ("output" | @sh)),
          PreviewType: "command",
          Async: ($audio_menu + " volume-display output")
        },
        {
          Text: "Input defaults",
          Subtext: $default_input,
          Value: "input",
          SubMenu: "keystone-audio-devices",
          Preview: ($audio_menu + " preview-kind " + ("input" | @sh)),
          PreviewType: "command",
          Async: ($audio_menu + " volume-display input")
        }
      ]
    '
}

devices_json() {
  local kind="$1"
  local current_default=""
  local audio_menu
  audio_menu=$(keystone_cmd keystone-audio-menu)

  if ! audio_cli_available; then
    blocked_entry_json "$(device_type_label "$kind" | tr -d '\n') unavailable" "$(audio_unavailable_reason)"
    return 0
  fi

  current_default=$(default_device_name "$kind")

  jq -n --arg audio_menu "$audio_menu" --arg kind "$kind" --arg current "$current_default" --argjson data "$(devices_json_raw "$kind")" '
    $data
    | if length == 0 then
        [
          {
            Text: (($kind | ascii_upcase) + " devices unavailable"),
            Subtext: "No compatible devices were detected",
            Value: "blocked"
          }
        ]
      else
        sort_by([(.name != $current), (.description // .properties."device.description" // .name)])
    | map({
        Text: (
          (if .name == $current then "  " else "󰓃  " end)
          + (.description // .properties."device.description" // .name)
        ),
        Subtext: (
          [
            .name,
            (if .name == $current then "current default" else "set as default" end)
          ]
          | join(" · ")
        ),
        Value: ("set-default\t" + $kind + "\t" + .name),
        Preview: ($audio_menu + " preview-device " + ($kind | @sh) + " " + (.name | @sh)),
        PreviewType: "command",
        Async: ($audio_menu + " device-volume-display " + ($kind | @sh) + " " + (.name | @sh))
      })
      end
  '
}

list_devices() {
  local kind="$1"
  local current_default=""

  current_default=$(default_device_name "$kind")

  devices_json_raw "$kind" | jq -r --arg current "$current_default" '
    .[]
    | [
        (if .name == $current then "*" else " " end),
        (.description // .properties."device.description" // .name),
        .name
      ]
    | @tsv
  '
}

set_default_device() {
  local kind="$1"
  local name="$2"
  local description=""

  description=$(device_description "$kind" "$name")

  case "$kind" in
    output) pactl set-default-sink "$name" ;;
    input) pactl set-default-source "$name" ;;
    *)
      printf "Unknown audio kind: %s\n" "$kind" >&2
      exit 1
      ;;
  esac

  save_audio_defaults
  notify "Audio default updated" "$(device_type_label "$kind" | tr -d '\n'): ${description}"
}

audio_defaults_snippet() {
  local default_sink default_source
  default_sink=$(default_device_name output)
  default_source=$(default_device_name input)

  printf '  keystone.desktop.audio.defaults = {\n'
  if [[ -n "$default_sink" ]]; then
    printf '    sink = "%s";\n' "$default_sink"
  else
    printf '    sink = null;\n'
  fi
  if [[ -n "$default_source" ]]; then
    printf '    source = "%s";\n' "$default_source"
  else
    printf '    source = null;\n'
  fi
  printf '  };\n'
}

save_audio_defaults() {
  audio_defaults_snippet | keystone-desktop-config write-desktop-state-section "audio defaults"
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-audio -p "Audio" >/dev/null 2>&1 &
}

preview_kind() {
  local kind="$1"

  if ! audio_cli_available; then
    printf "%s\n" "$(audio_unavailable_reason)"
    return 0
  fi

  printf "%s defaults\n\nCurrent default: %s\n\nSelect a device to set it as the new default and save it into the current host config.\n" \
    "$(device_type_label "$kind" | tr -d '\n')" \
    "$(current_default_description "$kind")"
}

preview_device() {
  local kind="$1"
  local name="$2"
  local current_default=""

  if ! audio_cli_available; then
    printf "%s\n" "$(audio_unavailable_reason)"
    return 0
  fi

  current_default=$(default_device_name "$kind")

  printf "%s device\n\nName: %s\nDescription: %s\n\nCurrent default: %s\n\nSelecting this entry updates the live default and saves it into nixos-config.\n" \
    "$(device_type_label "$kind" | tr -d '\n')" \
    "$name" \
    "$(device_description "$kind" "$name")" \
    "$(if [[ "$name" == "$current_default" ]]; then printf "yes"; else printf "no"; fi)"
}

volume_display() {
  local kind="$1"

  if ! audio_cli_available; then
    printf "Unavailable\n"
    return 0
  fi

  local name
  name=$(default_device_name "$kind")
  if [[ -z "$name" ]]; then
    printf "No device\n"
    return 0
  fi

  local list_type
  case "$kind" in
    output) list_type="sinks" ;;
    input) list_type="sources" ;;
    *)
      printf "Unknown kind: %s\n" "$kind" >&2
      exit 1
      ;;
  esac

  pactl -f json list "$list_type" \
    | jq -r --arg name "$name" '
        map(select(.name == $name)) | first
        | if .mute then
            "Muted (" + (.volume | to_entries | first | .value.value_percent) + ")"
          else
            (.volume | to_entries | first | .value.value_percent)
          end
      '
}

device_volume_display() {
  local kind="$1"
  local name="$2"

  if ! audio_cli_available; then
    printf "Unavailable\n"
    return 0
  fi

  local list_type
  case "$kind" in
    output) list_type="sinks" ;;
    input) list_type="sources" ;;
    *)
      printf "Unknown kind: %s\n" "$kind" >&2
      exit 1
      ;;
  esac

  pactl -f json list "$list_type" \
    | jq -r --arg name "$name" '
        map(select(.name == $name)) | first
        | if .mute then
            "Muted (" + (.volume | to_entries | first | .value.value_percent) + ")"
          else
            (.volume | to_entries | first | .value.value_percent)
          end
      '
}

summary() {
  if ! audio_cli_available; then
    printf "Audio unavailable\n%s" "$(audio_unavailable_reason)"
    return 0
  fi

  printf "Output: %s\n" "$(current_default_description output)"
  printf "Input: %s\n" "$(current_default_description input)"
}

apply_config_defaults() {
  if ! audio_cli_available; then
    return 0
  fi

  if [[ -n "${KEYSTONE_AUDIO_DEFAULT_SINK:-}" ]]; then
    pactl set-default-sink "$KEYSTONE_AUDIO_DEFAULT_SINK"
  fi

  if [[ -n "${KEYSTONE_AUDIO_DEFAULT_SOURCE:-}" ]]; then
    pactl set-default-source "$KEYSTONE_AUDIO_DEFAULT_SOURCE"
  fi
}

dispatch() {
  local payload="${1:-}"
  local action="" kind="" name=""

  IFS=$'\t' read -r action kind name <<<"$payload"

  case "$action" in
    set-default)
      set_default_device "$kind" "$name"
      ;;
    blocked)
      notify "Audio unavailable" "$(audio_unavailable_reason)"
      ;;
    *)
      printf "Unknown dispatch action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  categories-json)
    shift
    categories_json "$@"
    ;;
  devices-json)
    shift
    devices_json "$@"
    ;;
  list)
    shift
    list_devices "$@"
    ;;
  set-default)
    shift
    set_default_device "$@"
    ;;
  preview-kind)
    shift
    preview_kind "$@"
    ;;
  preview-device)
    shift
    preview_device "$@"
    ;;
  volume-display)
    shift
    volume_display "$@"
    ;;
  device-volume-display)
    shift
    device_volume_display "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  apply-config-defaults)
    shift
    apply_config_defaults "$@"
    ;;
  save-defaults)
    shift
    save_audio_defaults "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-audio-menu {open-menu|categories-json|devices-json|list|set-default|preview-kind|preview-device|volume-display|device-volume-display|summary|apply-config-defaults|save-defaults|dispatch} ..." >&2
    exit 1
    ;;
esac
