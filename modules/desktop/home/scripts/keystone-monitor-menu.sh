#!/usr/bin/env bash
# keystone-monitor-menu — Hyprland monitor controller for Walker/Elephant

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-monitor-menu"
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

hyprctl_available() {
  command -v hyprctl >/dev/null 2>&1
}

monitor_unavailable_reason() {
  if ! hyprctl_available; then
    printf "hyprctl is not available in PATH.\n"
    return 0
  fi

  printf "Monitor controls are unavailable.\n"
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

monitors_json_raw() {
  hyprctl -j monitors all 2>/dev/null || printf '[]\n'
}

monitors_json() {
  if ! hyprctl_available; then
    printf '[]\n'
    return 0
  fi

  monitors_json_raw
}

monitor_json() {
  local monitor_name="$1"

  monitors_json | jq -c --arg name "$monitor_name" 'map(select(.name == $name)) | first'
}

require_monitor_json() {
  local monitor_name="$1"
  local monitor

  monitor=$(monitor_json "$monitor_name")
  if [[ -z "$monitor" || "$monitor" == "null" ]]; then
    printf "Unknown monitor: %s\n" "$monitor_name" >&2
    exit 1
  fi

  printf "%s\n" "$monitor"
}

normalize_mode() {
  local mode="${1:-$(cat)}"
  printf "%s\n" "${mode%Hz}"
}

refresh_string() {
  local refresh="$1"
  LC_ALL=C printf "%.2f" "$refresh"
}

current_mode() {
  local monitor_name="$1"
  local monitor width height refresh

  monitor=$(require_monitor_json "$monitor_name")
  width=$(jq -r '.width // 0' <<<"$monitor")
  height=$(jq -r '.height // 0' <<<"$monitor")
  refresh=$(jq -r '.refreshRate // 60' <<<"$monitor")

  if [[ "$width" == "0" || "$height" == "0" ]]; then
    jq -r '(.availableModes // [])[0] // "preferred"' <<<"$monitor" | normalize_mode
  else
    printf "%sx%s@%s\n" "$width" "$height" "$(refresh_string "$refresh")"
  fi
}

preferred_mode() {
  local monitor_name="$1"
  require_monitor_json "$monitor_name" | jq -r '(.availableModes // [])[0] // "preferred"' | normalize_mode
}

current_scale() {
  local monitor_name="$1"
  require_monitor_json "$monitor_name" | jq -r '.scale // 1'
}

current_transform() {
  local monitor_name="$1"
  require_monitor_json "$monitor_name" | jq -r '.transform // 0'
}

current_position() {
  local monitor_name="$1"
  require_monitor_json "$monitor_name" | jq -r '"\(.x // 0)x\(.y // 0)"'
}

current_mirror_target() {
  local monitor_name="$1"
  require_monitor_json "$monitor_name" | jq -r '.mirrorOf // "none"'
}

stable_monitor_id() {
  local monitor_name="$1"
  local description=""

  description=$(require_monitor_json "$monitor_name" | jq -r '.description // ""')

  if [[ -n "$description" ]]; then
    printf "desc:%s\n" "$description"
  else
    printf "%s\n" "$monitor_name"
  fi
}

is_disabled() {
  local monitor_name="$1"
  [[ "$(require_monitor_json "$monitor_name" | jq -r '.disabled // false')" == "true" ]]
}

transform_label() {
  case "$1" in
    0) printf "Landscape\n" ;;
    1) printf "Portrait right\n" ;;
    2) printf "Upside down\n" ;;
    3) printf "Portrait left\n" ;;
    *) printf "Transform %s\n" "$1" ;;
  esac
}

transform_needs_swap() {
  case "$1" in
    1 | 3 | 5 | 7) return 0 ;;
    *) return 1 ;;
  esac
}

logical_dimensions() {
  local monitor_name="$1"
  local monitor width height scale transform logical_width logical_height

  monitor=$(require_monitor_json "$monitor_name")
  width=$(jq -r '.width // 0' <<<"$monitor")
  height=$(jq -r '.height // 0' <<<"$monitor")
  scale=$(jq -r '.scale // 1' <<<"$monitor")
  transform=$(jq -r '.transform // 0' <<<"$monitor")

  if transform_needs_swap "$transform"; then
    logical_width=$(LC_ALL=C printf "%.0f" "$(awk "BEGIN { print $height / $scale }")")
    logical_height=$(LC_ALL=C printf "%.0f" "$(awk "BEGIN { print $width / $scale }")")
  else
    logical_width=$(LC_ALL=C printf "%.0f" "$(awk "BEGIN { print $width / $scale }")")
    logical_height=$(LC_ALL=C printf "%.0f" "$(awk "BEGIN { print $height / $scale }")")
  fi

  printf "%s\t%s\n" "$logical_width" "$logical_height"
}

build_monitor_rule() {
  local monitor_name="$1"
  local mode="$2"
  local position="$3"
  local scale="$4"
  local transform="$5"
  local mirror_target="${6:-none}"

  if [[ "$mode" == "disable" ]]; then
    printf "%s, disable\n" "$monitor_name"
    return 0
  fi

  if [[ -n "$mirror_target" && "$mirror_target" != "none" ]]; then
    printf "%s, %s, %s, %s, transform, %s, mirror, %s\n" \
      "$monitor_name" "$mode" "$position" "$scale" "$transform" "$mirror_target"
    return 0
  fi

  printf "%s, %s, %s, %s, transform, %s\n" \
    "$monitor_name" "$mode" "$position" "$scale" "$transform"
}

apply_rule() {
  local rule="$1"
  hyprctl keyword monitor "$rule" >/dev/null
}

apply_scale() {
  local monitor_name="$1"
  local scale="$2"
  local rule

  rule=$(build_monitor_rule \
    "$monitor_name" \
    "$(current_mode "$monitor_name")" \
    "$(current_position "$monitor_name")" \
    "$scale" \
    "$(current_transform "$monitor_name")" \
    "$(current_mirror_target "$monitor_name")")

  apply_rule "$rule"
  notify "Monitor updated" "$monitor_name scale set to ${scale}x"
}

apply_resolution() {
  local monitor_name="$1"
  local mode="$2"
  local rule

  rule=$(build_monitor_rule \
    "$monitor_name" \
    "$mode" \
    "$(current_position "$monitor_name")" \
    "$(current_scale "$monitor_name")" \
    "$(current_transform "$monitor_name")" \
    "$(current_mirror_target "$monitor_name")")

  apply_rule "$rule"
  notify "Monitor updated" "$monitor_name resolution set to $mode"
}

apply_orientation() {
  local monitor_name="$1"
  local transform="$2"
  local rule

  rule=$(build_monitor_rule \
    "$monitor_name" \
    "$(current_mode "$monitor_name")" \
    "$(current_position "$monitor_name")" \
    "$(current_scale "$monitor_name")" \
    "$transform" \
    "$(current_mirror_target "$monitor_name")")

  apply_rule "$rule"
  notify "Monitor updated" "$monitor_name rotated to $(transform_label "$transform" | tr -d '\n')"
}

layout_position() {
  local source_name="$1"
  local relation="$2"
  local target_name="$3"
  local source_dims target_monitor source_width source_height target_width target_height target_x target_y new_x new_y

  source_dims=$(logical_dimensions "$source_name")
  source_width=${source_dims%%$'\t'*}
  source_height=${source_dims#*$'\t'}

  target_monitor=$(require_monitor_json "$target_name")
  target_x=$(jq -r '.x // 0' <<<"$target_monitor")
  target_y=$(jq -r '.y // 0' <<<"$target_monitor")

  read -r target_width target_height < <(logical_dimensions "$target_name" | tr '\t' ' ')

  case "$relation" in
    left-of)
      new_x=$((target_x - source_width))
      new_y=$((target_y + (target_height - source_height) / 2))
      ;;
    right-of)
      new_x=$((target_x + target_width))
      new_y=$((target_y + (target_height - source_height) / 2))
      ;;
    above)
      new_x=$((target_x + (target_width - source_width) / 2))
      new_y=$((target_y - source_height))
      ;;
    below)
      new_x=$((target_x + (target_width - source_width) / 2))
      new_y=$((target_y + target_height))
      ;;
    *)
      printf "Unknown layout relation: %s\n" "$relation" >&2
      exit 1
      ;;
  esac

  printf "%sx%s\n" "$new_x" "$new_y"
}

apply_layout() {
  local monitor_name="$1"
  local relation="$2"
  local target_name="$3"
  local rule position mirror_target

  if [[ "$relation" == "mirror" ]]; then
    mirror_target="$target_name"
    position="auto"
  else
    mirror_target="none"
    position=$(layout_position "$monitor_name" "$relation" "$target_name")
  fi

  rule=$(build_monitor_rule \
    "$monitor_name" \
    "$(current_mode "$monitor_name")" \
    "$position" \
    "$(current_scale "$monitor_name")" \
    "$(current_transform "$monitor_name")" \
    "$mirror_target")

  apply_rule "$rule"

  if [[ "$relation" == "mirror" ]]; then
    notify "Monitor updated" "$monitor_name now mirrors $target_name"
  else
    notify "Monitor updated" "$monitor_name placed $relation $target_name"
  fi
}

apply_enable() {
  local monitor_name="$1"
  local rule

  rule=$(build_monitor_rule "$monitor_name" "$(preferred_mode "$monitor_name")" "auto" "1" "0" "none")
  apply_rule "$rule"
  notify "Monitor updated" "$monitor_name enabled"
}

apply_disable() {
  local monitor_name="$1"
  apply_rule "$(build_monitor_rule "$monitor_name" "disable" "" "" "" "")"
  notify "Monitor updated" "$monitor_name disabled"
}

monitor_settings_json() {
  while IFS= read -r monitor_name; do
    [[ -z "$monitor_name" ]] && continue

    local monitor stable_name mirror_target width height refresh scale transform pos_x pos_y
    monitor=$(require_monitor_json "$monitor_name")
    stable_name=$(stable_monitor_id "$monitor_name")
    mirror_target=$(jq -r '.mirrorOf // "none"' <<<"$monitor")
    width=$(jq -r '.width // 0' <<<"$monitor")
    height=$(jq -r '.height // 0' <<<"$monitor")
    refresh=$(jq -r '.refreshRate // 60' <<<"$monitor")
    scale=$(jq -r '.scale // 1' <<<"$monitor")
    transform=$(jq -r '.transform // 0' <<<"$monitor")
    pos_x=$(jq -r '.x // 0' <<<"$monitor")
    pos_y=$(jq -r '.y // 0' <<<"$monitor")

    if [[ "$mirror_target" != "none" ]]; then
      printf "%s, %sx%s@%s, auto, %s, transform, %s, mirror, %s\n" \
        "$stable_name" \
        "$width" \
        "$height" \
        "$(refresh_string "$refresh")" \
        "$scale" \
        "$transform" \
        "$(stable_monitor_id "$mirror_target")"
    else
      printf "%s, %sx%s@%s, %sx%s, %s, transform, %s\n" \
        "$stable_name" \
        "$width" \
        "$height" \
        "$(refresh_string "$refresh")" \
        "$pos_x" \
        "$pos_y" \
        "$scale" \
        "$transform"
    fi
  done < <(monitors_json | jq -r '.[] | select((.disabled // false) | not) | .name')
}

primary_display() {
  monitors_json | jq -r '
    (
      map(select(((.disabled // false) | not) and (.mirrorOf // "none") == "none" and (.focused // false)))
      | first
    )
    // (
      map(select(((.disabled // false) | not) and (.mirrorOf // "none") == "none"))
      | first
    )
    // (first // {})
    | .name // "eDP-1"
  '
}

config_snippet() {
  local primary
  primary=$(primary_display)

  printf '  keystone.desktop.monitors = {\n'
  printf '    primaryDisplay = "%s";\n' "$(stable_monitor_id "$primary")"
  printf '    autoMirror = false;\n'
  printf '    settings = [\n'

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '      "%s"\n' "$line"
  done < <(monitor_settings_json)

  printf '    ];\n'
  printf '  };\n'
}

save_monitor_defaults() {
  local target_file=""
  target_file=$(keystone-desktop-config home-manager-host-file)
  config_snippet | keystone-desktop-config write-desktop-state-section "monitors"
  notify "Saved monitor defaults" "Updated ${target_file}"
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-monitors -p "Monitors" >/dev/null 2>&1 &
}

cmd_monitors_json() {
  local monitor_menu
  monitor_menu=$(keystone_cmd keystone-monitor-menu)

  if ! hyprctl_available; then
    blocked_entry_json "Monitors unavailable" "$(monitor_unavailable_reason)"
    return 0
  fi

  jq -n --arg monitor_menu "$monitor_menu" --argjson data "$(monitors_json_raw)" '
    if ($data | length) == 0 then
      [
        {
          Text: "No monitors detected",
          Subtext: "Hyprland reported no displays",
          Value: "blocked"
        }
      ]
    else
      $data
      | sort_by([((.focused // false) | not), (.disabled // false), .name])
      | map({
          Text: (
            (if .focused then "󰍹  " else "󰍺  " end)
            + .name
          ),
          Subtext: (
            [
              (.description // (.make + " " + .model)),
              (
                if (.disabled // false) then
                  "disabled"
                else
                  "\(.width)x\(.height) @ \(.refreshRate | tonumber | . * 100 | round / 100)Hz"
                end
              ),
              ("scale " + ((.scale // 1) | tostring)),
              ("orientation " + (.transform | tostring)),
              (
                if (.mirrorOf // "none") != "none" then
                  "mirrors " + .mirrorOf
                else
                  "at " + ((.x // 0) | tostring) + "x" + ((.y // 0) | tostring)
                end
              )
            ]
            | join(" · ")
          ),
          Value: .name,
          Icon: (if (.disabled // false) then "video-display-off-symbolic" else "video-display-symbolic" end),
          SubMenu: "keystone-monitor-actions",
          Preview: ($monitor_menu + " preview-monitor " + (.name | @sh)),
          PreviewType: "command"
        })
    end
  '
}

cmd_monitor_actions_json() {
  local monitor_name="$1"
  local monitor_menu
  monitor_menu=$(keystone_cmd keystone-monitor-menu)

  if is_disabled "$monitor_name"; then
    jq -n --arg monitor_menu "$monitor_menu" --arg monitor "$monitor_name" '
      [
        {
          Text: "Temporary: Enable monitor",
          Subtext: "Restore the display with its preferred mode",
          Value: ("enable\t" + $monitor),
          Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("enable" | @sh)),
          PreviewType: "command"
        },
        {
          Text: "Save current layout",
          Subtext: "Write the current monitor state into nixos-config",
          Value: ("save-layout\t" + $monitor),
          Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("save-layout" | @sh)),
          PreviewType: "command"
        }
      ]
    '
    return 0
  fi

  jq -n --arg monitor_menu "$monitor_menu" --arg monitor "$monitor_name" '
    [
      {
        Text: "Temporary: Scale",
        Subtext: "Apply a live scale change for this display",
        Value: "scale",
        SubMenu: "keystone-monitor-values",
        Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("scale" | @sh)),
        PreviewType: "command"
      },
      {
        Text: "Temporary: Resolution",
        Subtext: "Choose from the monitor advertised modes",
        Value: "resolution",
        SubMenu: "keystone-monitor-values",
        Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("resolution" | @sh)),
        PreviewType: "command"
      },
      {
        Text: "Temporary: Orientation",
        Subtext: "Rotate this display live",
        Value: "orientation",
        SubMenu: "keystone-monitor-values",
        Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("orientation" | @sh)),
        PreviewType: "command"
      },
      {
        Text: "Temporary: Layout",
        Subtext: "Mirror or place the display relative to another monitor",
        Value: "layout",
        SubMenu: "keystone-monitor-values",
        Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("layout" | @sh)),
        PreviewType: "command"
      },
      {
        Text: "Temporary: Disable monitor",
        Subtext: "Turn off the display for the current session",
        Value: ("disable\t" + $monitor),
        Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("disable" | @sh)),
        PreviewType: "command"
      },
      {
        Text: "Save current layout",
        Subtext: "Write the current monitor state into nixos-config",
        Value: ("save-layout\t" + $monitor),
        Preview: ($monitor_menu + " preview-action " + ($monitor | @sh) + " " + ("save-layout" | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

cmd_monitor_values_json() {
  local monitor_name="$1"
  local action="$2"
  local current

  case "$action" in
    scale)
      current=$(current_scale "$monitor_name")
      jq -n --arg monitor "$monitor_name" --arg current "$current" '
        [
          "0.75",
          "1",
          "1.25",
          "1.5",
          "1.75",
          "2",
          "2.5",
          "3"
        ]
        | map({
            Text: . + "x",
            Subtext: (if . == $current then "current scale" else "live session change" end),
            Value: ("apply-scale\t" + $monitor + "\t" + .)
          })
      '
      ;;
    resolution)
      current=$(current_mode "$monitor_name")
      jq -n --arg monitor "$monitor_name" --arg current "$current" --argjson data "$(require_monitor_json "$monitor_name")" '
        [
          ($data.availableModes // [])
          | map(sub("Hz$"; ""))
          | unique[]
          | {
              Text: .,
              Subtext: (if . == $current then "current mode" else "advertised by monitor" end),
              Value: ("apply-resolution\t" + $monitor + "\t" + .)
            }
        ]
      '
      ;;
    orientation)
      current=$(current_transform "$monitor_name")
      jq -n --arg monitor "$monitor_name" --arg current "$current" '
        [
          { id: "0", text: "Landscape" },
          { id: "1", text: "Portrait right" },
          { id: "2", text: "Upside down" },
          { id: "3", text: "Portrait left" }
        ]
        | map({
            Text: .text,
            Subtext: (if .id == $current then "current orientation" else "live session change" end),
            Value: ("apply-orientation\t" + $monitor + "\t" + .id)
          })
      '
      ;;
    layout)
      jq -n --arg monitor "$monitor_name" --argjson data "$(monitors_json)" '
        [
          $data[]
          | select(.name != $monitor)
          | select((.disabled // false) | not)
          | [
              {
                Text: "Mirror " + .name,
                Subtext: "Clone this display onto " + .name,
                Value: ("apply-layout\t" + $monitor + "\tmirror\t" + .name)
              },
              {
                Text: "Place left of " + .name,
                Subtext: "Center vertically relative to " + .name,
                Value: ("apply-layout\t" + $monitor + "\tleft-of\t" + .name)
              },
              {
                Text: "Place right of " + .name,
                Subtext: "Center vertically relative to " + .name,
                Value: ("apply-layout\t" + $monitor + "\tright-of\t" + .name)
              },
              {
                Text: "Place above " + .name,
                Subtext: "Center horizontally relative to " + .name,
                Value: ("apply-layout\t" + $monitor + "\tabove\t" + .name)
              },
              {
                Text: "Place below " + .name,
                Subtext: "Center horizontally relative to " + .name,
                Value: ("apply-layout\t" + $monitor + "\tbelow\t" + .name)
              }
            ][]
        ]
      '
      ;;
    *)
      printf '[]\n'
      ;;
  esac
}

cmd_preview_monitor() {
  local monitor_name="$1"
  local monitor mirror

  monitor=$(require_monitor_json "$monitor_name")
  mirror=$(jq -r '.mirrorOf // "none"' <<<"$monitor")

  jq -r \
    --arg mirror "$mirror" \
    --arg snippet "$(config_snippet)" '
      [
        "Monitor: \(.name)",
        "",
        ("Description: " + (.description // ((.make // "") + " " + (.model // "")))),
        ("Mode: " + (if (.disabled // false) then "disabled" else "\(.width)x\(.height) @ \(.refreshRate | tonumber | . * 100 | round / 100)Hz" end)),
        ("Scale: " + ((.scale // 1) | tostring)),
        ("Orientation: " + (.transform | tostring)),
        (
          if ($mirror != "none") then
            "Layout: mirroring " + $mirror
          else
            "Layout: positioned at \(.x)x\(.y)"
          end
        ),
        "",
        "Save for this host",
        "Selecting save writes this monitor state into the current host home-manager file in nixos-config.",
        "",
        "Current declarative snippet:",
        $snippet
      ]
      | join("\n")
    ' <<<"$monitor"
}

cmd_preview_setup() {
  if ! hyprctl_available; then
    printf "Monitors unavailable\n\n%s" "$(monitor_unavailable_reason)"
    return 0
  fi

  printf "Connected monitors: %s\n\nSelect a monitor to change scale, resolution, orientation, or layout.\nSaving writes the current layout into nixos-config.\n" \
    "$(monitors_json_raw | jq 'length')"
}

cmd_preview_action() {
  local monitor_name="$1"
  local action="$2"

  case "$action" in
    scale)
      printf "Temporary scale change for %s.\n\nThis updates the live Hyprland session only.\n\nCurrent scale: %s\n" \
        "$monitor_name" "$(current_scale "$monitor_name")"
      ;;
    resolution)
      printf "Temporary resolution change for %s.\n\nOffered modes come from hyprctl live monitor data.\n\nCurrent mode: %s\n" \
        "$monitor_name" "$(current_mode "$monitor_name")"
      ;;
    orientation)
      printf "Temporary orientation change for %s.\n\nCurrent orientation: %s\n" \
        "$monitor_name" "$(transform_label "$(current_transform "$monitor_name")" | tr -d '\n')"
      ;;
    layout)
      printf "Temporary layout change for %s.\n\nChoose mirroring or a relative placement against another connected display.\n" \
        "$monitor_name"
      ;;
    disable)
      printf "Disable %s for the current session.\n\nUse the monitor list again to re-enable it.\n" "$monitor_name"
      ;;
    enable)
      printf "Re-enable %s with its preferred mode.\n" "$monitor_name"
      ;;
    save-layout)
      printf "Save the current monitor layout for this host.\n\nThis writes the current monitor state into the managed desktop block in:\n%s\n\nCurrent snippet:\n%s\n" \
        "$(keystone-desktop-config home-manager-host-file)" \
        "$(config_snippet)"
      ;;
    *)
      printf "Monitor action preview unavailable.\n"
      ;;
  esac
}

cmd_dispatch() {
  local payload="${1:-}"
  local action="" monitor_name="" arg1="" arg2=""

  IFS=$'\t' read -r action monitor_name arg1 arg2 <<<"$payload"

  case "$action" in
    apply-scale)
      apply_scale "$monitor_name" "$arg1"
      ;;
    apply-resolution)
      apply_resolution "$monitor_name" "$arg1"
      ;;
    apply-orientation)
      apply_orientation "$monitor_name" "$arg1"
      ;;
    apply-layout)
      apply_layout "$monitor_name" "$arg1" "$arg2"
      ;;
    enable)
      apply_enable "$monitor_name"
      ;;
    disable)
      apply_disable "$monitor_name"
      ;;
    save-layout)
      save_monitor_defaults
      ;;
    blocked)
      notify "Monitors unavailable" "$(monitor_unavailable_reason)"
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
  monitors-json)
    shift
    cmd_monitors_json "$@"
    ;;
  monitor-actions-json)
    shift
    cmd_monitor_actions_json "$@"
    ;;
  monitor-values-json)
    shift
    cmd_monitor_values_json "$@"
    ;;
  preview-monitor)
    shift
    cmd_preview_monitor "$@"
    ;;
  preview-setup)
    shift
    cmd_preview_setup "$@"
    ;;
  preview-action)
    shift
    cmd_preview_action "$@"
    ;;
  dispatch)
    shift
    cmd_dispatch "$@"
    ;;
  config-snippet)
    shift
    config_snippet "$@"
    ;;
  save-current)
    shift
    save_monitor_defaults "$@"
    ;;
  *)
    echo "Usage: keystone-monitor-menu {open-menu|monitors-json|monitor-actions-json|monitor-values-json|preview-monitor|preview-setup|preview-action|dispatch|config-snippet|save-current} ..." >&2
    exit 1
    ;;
esac
