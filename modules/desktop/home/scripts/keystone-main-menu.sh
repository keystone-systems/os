#!/usr/bin/env bash
# keystone-main-menu — Main Mod+Escape Elephant/Walker menu backend.

set -euo pipefail

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

notify() {
  notify-send "$@"
}

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

current_theme_name() {
  local current_theme_dir="${XDG_CONFIG_HOME:-$HOME/.config}/keystone/current/theme"

  if [[ -L "$current_theme_dir" ]]; then
    basename "$(readlink -f "$current_theme_dir")"
    return 0
  fi

  if [[ -d "$current_theme_dir" ]]; then
    basename "$current_theme_dir"
    return 0
  fi

  printf "unknown\n"
}

blocked_entry_json() {
  local title="$1"
  local message="$2"

  jq -n --arg title "$title" --arg message "$message" '
    [
      {
        Text: $title,
        Subtext: $message,
        Value: ("blocked\t" + $title + "\t" + $message),
        Icon: "dialog-warning-symbolic",
        Preview: ("printf " + (($title + "\n\n" + $message + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

main_json() {
  # ISSUE-REQ-1 (#390): Photos/Agents are gated by capability env vars
  # wired from the desktop home-manager module. Default to hidden when unset so
  # the surface never leaks in stale builds or ad-hoc invocations.
  local show_photos="${KEYSTONE_MENU_SHOW_PHOTOS:-false}"
  local show_agents="${KEYSTONE_MENU_SHOW_AGENTS:-false}"

  jq -n \
    --arg show_photos "$show_photos" \
    --arg show_agents "$show_agents" '
    [
      {
        Text: "Apps",
        Subtext: "Application launcher",
        Value: "open-apps",
        Icon: "view-app-grid-symbolic"
      },
      (if $show_photos == "true" then {
        Text: "Photos",
        Subtext: "Search Keystone Photos and preview results",
        Value: "open-photos-search",
        Icon: "image-x-generic-symbolic"
      } else empty end),
      (if $show_agents == "true" then {
        Text: "Agents",
        Subtext: "Agent state, pause, and interactive defaults",
        Value: "agents",
        Icon: "computer-symbolic",
        SubMenu: "keystone-agents"
      } else empty end),
      {
        Text: "Learn",
        Subtext: "Keybindings and desktop references",
        Value: "learn",
        Icon: "help-browser-symbolic",
        SubMenu: "keystone-learn"
      },
      {
        Text: "Capture",
        Subtext: "Screenshots and screen recording",
        Value: "capture",
        Icon: "camera-photo-symbolic",
        SubMenu: "keystone-capture"
      },
      {
        Text: "Toggle",
        Subtext: "Session switches and desktop state",
        Value: "toggle",
        Icon: "system-run-symbolic",
        SubMenu: "keystone-toggle"
      },
      {
        Text: "Style",
        Subtext: "Theme and visual customization",
        Value: "style",
        Icon: "preferences-desktop-theme-symbolic",
        SubMenu: "keystone-style"
      },
      {
        Text: "Setup",
        Subtext: "Devices and desktop defaults",
        Value: "setup",
        Icon: "preferences-system-symbolic",
        SubMenu: "keystone-setup"
      },
      {
        Text: "Install",
        Subtext: "Search and install packages from the current system flake",
        Value: "install",
        Icon: "list-add-symbolic",
        SubMenu: "keystone-install"
      },
      {
        Text: "Remove",
        Subtext: "Use Nix instead",
        Value: "blocked\tRemove\tUse Nix to remove software.",
        Icon: "list-remove-symbolic"
      },
      {
        Text: "Update",
        Subtext: "Update this host (silent, polkit-approved)",
        Value: "run-update",
        Icon: "software-update-available-symbolic"
      },
      {
        Text: "System",
        Subtext: "Lock, suspend, restart, and shutdown",
        Value: "system",
        Icon: "system-shutdown-symbolic",
        SubMenu: "keystone-system"
      }
    ]
  '
}

learn_json() {
  jq -n '
    [
      {
        Text: "Keybindings",
        Subtext: "Search current Hyprland keybindings",
        Value: "open-keybindings",
        Icon: "preferences-desktop-keyboard-shortcuts-symbolic"
      },
      {
        Text: "Hyprland",
        Subtext: "Open the Hyprland wiki",
        Value: "open-url\thttps://wiki.hypr.land/",
        Icon: "web-browser-symbolic"
      },
      {
        Text: "NixOS",
        Subtext: "Open the NixOS wiki",
        Value: "open-url\thttps://wiki.nixos.org/",
        Icon: "web-browser-symbolic"
      }
    ]
  '
}

capture_json() {
  jq -n '
    [
      {
        Text: "Screenshot",
        Subtext: "Capture an area or clipboard screenshot",
        Value: "screenshot",
        Icon: "applets-screenshooter-symbolic",
        SubMenu: "keystone-screenshot"
      },
      {
        Text: "Screenrecord",
        Subtext: "Start or stop screen recording",
        Value: "screenrecord",
        Icon: "media-record-symbolic"
      }
    ]
  '
}

screenshot_json() {
  jq -n '
    [
      {
        Text: "Snap with editing",
        Subtext: "Interactive capture with annotation flow",
        Value: "screenshot-smart",
        Icon: "document-edit-symbolic"
      },
      {
        Text: "Straight to clipboard",
        Subtext: "Interactive capture copied directly",
        Value: "screenshot-clipboard",
        Icon: "edit-copy-symbolic"
      }
    ]
  '
}

toggle_json() {
  jq -n '
    [
      {
        Text: "Idle inhibitor",
        Subtext: "Toggle automatic idle lock behavior",
        Value: "toggle-idle",
        Icon: "changes-allow-symbolic"
      },
      {
        Text: "Nightlight",
        Subtext: "Toggle warm screen temperature",
        Value: "toggle-nightlight",
        Icon: "weather-clear-night-symbolic"
      },
      {
        Text: "Top bar",
        Subtext: "Not implemented yet",
        Value: "blocked\tTop bar\tTop bar toggle is not implemented yet.",
        Icon: "view-more-symbolic"
      }
    ]
  '
}

style_json() {
  local current_theme
  current_theme=$(current_theme_name)

  jq -n --arg current_theme "$current_theme" '
    [
      {
        Text: "Theme",
        Subtext: ("Current theme: " + $current_theme),
        Value: "theme",
        Icon: "preferences-desktop-theme-symbolic",
        SubMenu: "keystone-theme"
      },
      {
        Text: "Background",
        Subtext: "Not implemented yet",
        Value: "blocked\tBackground\tBackground switching is not implemented yet.",
        Icon: "image-x-generic-symbolic"
      }
    ]
  '
}

theme_json() {
  local themes_dir="${XDG_CONFIG_HOME:-$HOME/.config}/keystone/themes"
  local current_theme
  current_theme=$(current_theme_name)

  if [[ ! -d "$themes_dir" ]]; then
    blocked_entry_json "No themes found" "Themes directory not found at ${themes_dir}."
    return 0
  fi

  find "$themes_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | sort \
    | jq -R -s --arg current_theme "$current_theme" '
        split("\n")
        | map(select(length > 0))
        | if length == 0 then
            [
              {
                Text: "No themes found",
                Subtext: "The themes directory is empty",
                Value: "blocked\tTheme\tNo themes were found."
              }
            ]
          else
            map({
              Text: .,
              Subtext: (if . == $current_theme then "current theme" else "switch theme" end),
              Value: ("theme-select\t" + .),
              Icon: "preferences-desktop-theme-symbolic"
            })
          end
      '
}

system_json() {
  jq -n '
    [
      {
        Text: "Lock",
        Subtext: "Lock the current session",
        Value: "system-lock",
        Icon: "system-lock-screen-symbolic"
      },
      {
        Text: "Suspend",
        Subtext: "Suspend the machine",
        Value: "system-suspend",
        Icon: "weather-clear-night-symbolic"
      },
      {
        Text: "Restart",
        Subtext: "Reboot the machine",
        Value: "system-restart",
        Icon: "system-reboot-symbolic"
      },
      {
        Text: "Shutdown",
        Subtext: "Power off the machine",
        Value: "system-shutdown",
        Icon: "system-shutdown-symbolic"
      }
    ]
  '
}

preview_blocked() {
  local title="$1"
  local message="$2"

  printf "%s\n\n%s\n" "$title" "$message"
}

open_menu() {
  local target="${1:-main}"
  local menu_id=""
  local prompt=""

  case "${target,,}" in
    main | go | "")
      menu_id="menus:keystone-main"
      prompt="Go"
      ;;
    learn)
      menu_id="menus:keystone-learn"
      prompt="Learn"
      ;;
    capture)
      menu_id="menus:keystone-capture"
      prompt="Capture"
      ;;
    screenshot)
      menu_id="menus:keystone-screenshot"
      prompt="Screenshot"
      ;;
    agents)
      menu_id="menus:keystone-agents"
      prompt="Agents"
      ;;
    toggle)
      menu_id="menus:keystone-toggle"
      prompt="Toggle"
      ;;
    style)
      menu_id="menus:keystone-style"
      prompt="Style"
      ;;
    theme)
      menu_id="menus:keystone-theme"
      prompt="Theme"
      ;;
    setup)
      menu_id="menus:keystone-setup"
      prompt="Setup"
      ;;
    system)
      menu_id="menus:keystone-system"
      prompt="System"
      ;;
    *)
      menu_id="menus:keystone-main"
      prompt="Go"
      ;;
  esac

  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m "$menu_id" -p "$prompt" >/dev/null 2>&1 &
}

dispatch() {
  local payload="${1:-}"
  local action="" arg1="" arg2=""

  IFS=$'\t' read -r action arg1 arg2 <<<"$payload"

  case "$action" in
    learn | capture | screenshot | toggle | style | theme | setup | system | agents)
      ;;
    open-apps)
      detach walker
      ;;
    open-photos-search)
      detach "$(keystone_cmd keystone-photos-menu)" prompt-query
      ;;
    open-keybindings)
      detach "$(keystone_cmd keystone-menu-keybindings)"
      ;;
    open-url)
      detach xdg-open "$arg1"
      ;;
    screenrecord)
      detach "$(keystone_cmd keystone-screenrecord)"
      ;;
    run-update)
      # CRITICAL: delegate to the dedicated update submenu's dispatch path
      # so the top-level Walker entry stays aligned with the authoritative
      # update launcher. The submenu spawns `ks update --approve` via
      # `uwsm app -- systemd-inhibit … systemd-cat -t ks-update …` (no
      # terminal); polkit prompt + notify-send make the run silent on
      # success and journaled under tag `ks-update` on failure. Any
      # change to the launch contract belongs in
      # update_menu.rs::dispatch, not duplicated here.
      ks menu update dispatch run-update
      ;;
    screenshot-smart)
      detach "$(keystone_cmd keystone-screenshot)" smart
      ;;
    screenshot-clipboard)
      detach "$(keystone_cmd keystone-screenshot)" smart clipboard
      ;;
    toggle-idle)
      detach "$(keystone_cmd keystone-idle-toggle)"
      ;;
    toggle-nightlight)
      detach "$(keystone_cmd keystone-nightlight-toggle)"
      ;;
    theme-select)
      detach "$(keystone_cmd keystone-theme-switch)" "$arg1"
      ;;
    system-lock)
      "$(keystone_cmd hyprlock)"
      ;;
    system-suspend)
      systemctl suspend
      ;;
    system-restart)
      systemctl reboot
      ;;
    system-shutdown)
      systemctl poweroff
      ;;
    blocked)
      notify "$arg1" "$arg2"
      ;;
    *)
      printf "Unknown main menu action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  main-json)
    shift
    main_json "$@"
    ;;
  learn-json)
    shift
    learn_json "$@"
    ;;
  capture-json)
    shift
    capture_json "$@"
    ;;
  screenshot-json)
    shift
    screenshot_json "$@"
    ;;
  toggle-json)
    shift
    toggle_json "$@"
    ;;
  style-json)
    shift
    style_json "$@"
    ;;
  theme-json)
    shift
    theme_json "$@"
    ;;
  system-json)
    shift
    system_json "$@"
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
    echo "Usage: keystone-main-menu {open-menu|main-json|learn-json|capture-json|screenshot-json|toggle-json|style-json|theme-json|system-json|preview-blocked|dispatch} ..." >&2
    exit 1
    ;;
esac
