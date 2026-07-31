{
  config,
  lib,
  pkgs,
  keystoneInputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  devScripts = import ../../../shared/dev-script-link.nix { inherit lib; };
  inherit (devScripts) mkHomeScriptCommand;
  hyprlandPkg = keystoneInputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

  # Screen recording script using gpu-screen-recorder
  #
  # Waybar Integration:
  # The waybar module "custom/screenrecording-indicator" uses signal-based updates
  # instead of polling for efficiency. When recording starts or stops, we send
  # RTMIN+8 signal to waybar (pkill -RTMIN+8 waybar) which triggers it to re-run
  # the indicator's exec command and update the display immediately.
  #
  # The waybar config uses "signal": 8 which maps to RTMIN+8.
  # See: modules/keystone/desktop/home/components/waybar.nix
  #
  keystoneScreenrecord = pkgs.writeShellScriptBin "keystone-screenrecord" ''
    [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
    OUTPUT_DIR="''${KEYSTONE_SCREENRECORD_DIR:-''${XDG_VIDEOS_DIR:-$HOME/Videos}}"

    if [[ ! -d "$OUTPUT_DIR" ]]; then
      ${pkgs.libnotify}/bin/notify-send "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
      exit 1
    fi

    DESKTOP_AUDIO="false"
    MICROPHONE_AUDIO="false"
    STOP_RECORDING="false"

    for arg in "$@"; do
      case "$arg" in
        --with-desktop-audio) DESKTOP_AUDIO="true" ;;
        --with-microphone-audio) MICROPHONE_AUDIO="true" ;;
        --stop) STOP_RECORDING="true" ;;
      esac
    done

    start_screenrecording() {
      local filename="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
      local audio_args=""

      if [[ "$DESKTOP_AUDIO" == "true" && "$MICROPHONE_AUDIO" == "true" ]]; then
        audio_args="-a default_output|default_input"
      elif [[ "$DESKTOP_AUDIO" == "true" ]]; then
        audio_args="-a default_output"
      elif [[ "$MICROPHONE_AUDIO" == "true" ]]; then
        audio_args="-a default_input"
      fi

      ${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder -w portal -f 60 -encoder gpu -o "$filename" $audio_args -ac aac &
      ${pkgs.libnotify}/bin/notify-send "Screen recording started" -t 2000
      ${pkgs.procps}/bin/pkill -RTMIN+8 waybar
    }

    stop_screenrecording() {
      ${pkgs.procps}/bin/pkill -SIGINT -f "[g]pu-screen-recorder"

      # Wait up to 5 seconds for clean shutdown
      local count=0
      while ${pkgs.procps}/bin/pgrep -f "[g]pu-screen-recorder" >/dev/null && [ $count -lt 50 ]; do
        sleep 0.1
        count=$((count + 1))
      done

      if ${pkgs.procps}/bin/pgrep -f "[g]pu-screen-recorder" >/dev/null; then
        ${pkgs.procps}/bin/pkill -9 -f "[g]pu-screen-recorder"
        ${pkgs.libnotify}/bin/notify-send "Screen recording error" "Recording had to be force-killed. Video may be corrupted." -u critical -t 5000
      else
        ${pkgs.libnotify}/bin/notify-send "Screen recording saved to $OUTPUT_DIR" -t 2000
      fi
      ${pkgs.procps}/bin/pkill -RTMIN+8 waybar
    }

    screenrecording_active() {
      ${pkgs.procps}/bin/pgrep -f "[g]pu-screen-recorder" >/dev/null
    }

    if screenrecording_active; then
      stop_screenrecording
    elif [[ "$STOP_RECORDING" == "false" ]]; then
      start_screenrecording
    else
      exit 1
    fi
  '';

  # Audio switch script
  keystoneAudioSwitch = pkgs.writeShellScriptBin "keystone-audio-switch" ''
    focused_monitor="$(${hyprlandPkg}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true).name')"

    sinks=$(${pkgs.pulseaudio}/bin/pactl -f json list sinks | ${pkgs.jq}/bin/jq '[.[] | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))]')
    sinks_count=$(echo "$sinks" | ${pkgs.jq}/bin/jq '. | length')

    if [ "$sinks_count" -eq 0 ]; then
      ${pkgs.swayosd}/bin/swayosd-client \
        --monitor "$focused_monitor" \
        --custom-message "No audio devices found"
      exit 1
    fi

    current_sink_name=$(${pkgs.pulseaudio}/bin/pactl get-default-sink)
    current_sink_index=$(echo "$sinks" | ${pkgs.jq}/bin/jq -r --arg name "$current_sink_name" 'map(.name) | index($name)')

    if [ "$current_sink_index" != "null" ]; then
      next_sink_index=$(((current_sink_index + 1) % sinks_count))
    else
      next_sink_index=0
    fi

    next_sink=$(echo "$sinks" | ${pkgs.jq}/bin/jq -r ".[$next_sink_index]")
    next_sink_name=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.name')

    next_sink_description=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.description')
    if [ "$next_sink_description" = "(null)" ] || [ "$next_sink_description" = "null" ] || [ -z "$next_sink_description" ]; then
      sink_id=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.properties."object.id"')
      next_sink_description=$(${pkgs.wireplumber}/bin/wpctl status | grep -E "\s+\*?\s+''${sink_id}\." | sed -E 's/^.*[0-9]+\.\s+//' | sed -E 's/\s+\[.*$//')
    fi

    next_sink_volume=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r \
      '.volume | to_entries[0].value.value_percent | sub("%"; "")')
    next_sink_is_muted=$(echo "$next_sink" | ${pkgs.jq}/bin/jq -r '.mute')

    if [ "$next_sink_is_muted" = "true" ] || [ "$next_sink_volume" -eq 0 ]; then
      icon_state="muted"
    elif [ "$next_sink_volume" -le 33 ]; then
      icon_state="low"
    elif [ "$next_sink_volume" -le 66 ]; then
      icon_state="medium"
    else
      icon_state="high"
    fi

    next_sink_volume_icon="sink-volume-''${icon_state}-symbolic"

    if [ "$next_sink_name" != "$current_sink_name" ]; then
      ${pkgs.pulseaudio}/bin/pactl set-default-sink "$next_sink_name"
    fi

    ${pkgs.swayosd}/bin/swayosd-client \
      --monitor "$focused_monitor" \
      --custom-message "$next_sink_description" \
      --custom-icon "$next_sink_volume_icon"
  '';

  # Idle toggle script
  keystoneIdleToggle = pkgs.writeShellScriptBin "keystone-idle-toggle" ''
    if ${pkgs.procps}/bin/pgrep -x hypridle > /dev/null; then
      ${pkgs.procps}/bin/pkill -x hypridle
      ${pkgs.libnotify}/bin/notify-send "󰅶  Idle inhibitor enabled" "Screen will not lock automatically"
    else
      setsid ${pkgs.uwsm}/bin/uwsm app -- ${pkgs.hypridle}/bin/hypridle &
      ${pkgs.libnotify}/bin/notify-send "󰾪  Idle inhibitor disabled" "Screen will lock after timeout"
    fi
  '';

  # Nightlight toggle script
  keystoneNightlightToggle = pkgs.writeShellScriptBin "keystone-nightlight-toggle" ''
    ON_TEMP=4000
    OFF_TEMP=6000

    if ! ${pkgs.procps}/bin/pgrep -x hyprsunset; then
      setsid ${pkgs.uwsm}/bin/uwsm app -- ${pkgs.hyprsunset}/bin/hyprsunset &
      sleep 1
    fi

    CURRENT_TEMP=$(${hyprlandPkg}/bin/hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+')

    if [[ "$CURRENT_TEMP" == "$OFF_TEMP" ]]; then
      ${hyprlandPkg}/bin/hyprctl hyprsunset temperature $ON_TEMP
      ${pkgs.libnotify}/bin/notify-send "  Nightlight screen temperature"
    else
      ${hyprlandPkg}/bin/hyprctl hyprsunset temperature $OFF_TEMP
      ${pkgs.libnotify}/bin/notify-send "   Daylight screen temperature"
    fi
  '';

  # Walker launcher wrapper for menus
  keystoneLaunchWalker = pkgs.writeShellScriptBin "keystone-launch-walker" (
    builtins.readFile ./keystone-launch-walker.sh
  );

  # Shared desktop-config helper, packaged as a subcommand CLI so other menu
  # scripts (each in its own writeShellScriptBin $out/bin) can invoke helpers
  # without relying on an unpackaged sibling path.
  keystoneDesktopConfig = pkgs.writeShellScriptBin "keystone-desktop-config" (
    builtins.readFile ./keystone-desktop-config.sh
  );

  # Detached process launcher for menu-triggered long-lived commands.
  keystoneDetach = pkgs.writeShellScriptBin "keystone-detach" ''
    set -euo pipefail

    print_pid="false"

    case "''${1:-}" in
      --print-pid)
        print_pid="true"
        shift
        ;;
    esac

    if [[ $# -eq 0 ]]; then
      echo "Usage: keystone-detach [--print-pid] <command> [args...]" >&2
      exit 1
    fi

    ${pkgs.util-linux}/bin/setsid "$@" </dev/null >/dev/null 2>&1 &
    child_pid=$!

    if [[ "$print_pid" == "true" ]]; then
      printf "%s\n" "$child_pid"
    fi
  '';

  # Main menu script
  keystoneMenu = pkgs.writeShellScriptBin "keystone-menu" (builtins.readFile ./keystone-menu.sh);

  # Main Mod+Escape backend for Elephant/Walker
  keystoneMainMenu = pkgs.writeShellScriptBin "keystone-main-menu" (
    builtins.readFile ./keystone-main-menu.sh
  );

  # Package install flow for the main menu
  keystonePackageMenu = pkgs.writeShellScriptBin "keystone-package-menu" (
    builtins.readFile ./keystone-package-menu.sh
  );

  # Desktop setup launcher for Walker/Elephant
  keystoneSetupMenu = pkgs.writeShellScriptBin "keystone-setup-menu" (
    builtins.readFile ./keystone-setup-menu.sh
  );

  # Audio defaults controller for Elephant/Walker and terminal use
  keystoneAudioMenu = pkgs.writeShellScriptBin "keystone-audio-menu" (
    builtins.readFile ./keystone-audio-menu.sh
  );

  # CUPS printer default controller for Elephant/Walker and terminal use
  keystonePrinterMenu = pkgs.writeShellScriptBin "keystone-printer-menu" (
    builtins.readFile ./keystone-printer-menu.sh
  );

  # Hyprland monitor controller for Elephant/Walker
  keystoneMonitorMenu = pkgs.writeShellScriptBin "keystone-monitor-menu" (
    builtins.readFile ./keystone-monitor-menu.sh
  );

  # Hardware security and disk unlock controller
  keystoneHardwareMenu = pkgs.writeShellScriptBin "keystone-hardware-menu" (
    builtins.readFile ./keystone-hardware-menu.sh
  );

  # Fingerprint enrollment and management controller
  keystoneFingerprintMenu = pkgs.writeShellScriptBin "keystone-fingerprint-menu" (
    builtins.readFile ./keystone-fingerprint-menu.sh
  );

  # Multi-account mail and calendar controller
  keystoneAccountsMenu = pkgs.writeShellScriptBin "keystone-accounts-menu" (
    builtins.readFile ./keystone-accounts-menu.sh
  );

  # Agenix secret categories, inspection, and rekey controller
  keystoneSecretsMenu = pkgs.writeShellScriptBin "keystone-secrets-menu" (
    builtins.readFile ./keystone-secrets-menu.sh
  );

  # Wi-Fi scan/join controller for Elephant/Walker
  keystoneWifiMenu = pkgs.writeShellScriptBin "keystone-wifi-menu" (
    builtins.readFile ./keystone-wifi-menu.sh
  );

  # Keybindings viewer script
  keystoneMenuKeybindings = pkgs.writeShellScriptBin "keystone-menu-keybindings" (
    builtins.readFile ./keystone-menu-keybindings.sh
  );

  # Context launcher — creates zellij session + ghostty window on named workspace
  keystoneContext = pkgs.writeShellScriptBin "keystone-context" (
    builtins.readFile ./keystone-context.sh
  );

  # Photo search and preview adapter for Walker/Elephant
  keystonePhotosMenu = pkgs.writeShellScriptBin "keystone-photos-menu" (
    builtins.readFile ./keystone-photos-menu.sh
  );

  # Agent control surface for the main menu
  keystoneAgentMenu = pkgs.writeShellScriptBin "keystone-agent-menu" (
    builtins.readFile ./keystone-agent-menu.sh
  );

  # Inbox capture launcher — opens zk edit -i in a dedicated floating Ghostty window
  keystoneNotesInbox = pkgs.writeShellScriptBin "keystone-notes-inbox" (
    builtins.readFile ./keystone-notes-inbox.sh
  );

  # Battery monitor script
  keystoneBatteryMonitor = pkgs.writeShellScriptBin "keystone-battery-monitor" ''
    BATTERY_THRESHOLD=10
    NOTIFICATION_FLAG="/run/user/$UID/keystone_battery_notified"

    # Get battery level
    BATTERY_LEVEL=$(${pkgs.upower}/bin/upower -i $(${pkgs.upower}/bin/upower -e | grep 'BAT') | grep -E "percentage" | awk '{print $2}' | tr -d '%')
    BATTERY_STATE=$(${pkgs.upower}/bin/upower -i $(${pkgs.upower}/bin/upower -e | grep 'BAT') | grep -E "state" | awk '{print $2}')

    send_notification() {
      ${pkgs.libnotify}/bin/notify-send -u critical " Time to recharge!" "Battery is down to ''${1}%" -i battery-caution -t 30000
    }

    if [[ -n "$BATTERY_LEVEL" && "$BATTERY_LEVEL" =~ ^[0-9]+$ ]]; then
      if [[ $BATTERY_STATE == "discharging" && $BATTERY_LEVEL -le $BATTERY_THRESHOLD ]]; then
        if [[ ! -f $NOTIFICATION_FLAG ]]; then
          send_notification $BATTERY_LEVEL
          touch $NOTIFICATION_FLAG
        fi
      else
        rm -f $NOTIFICATION_FLAG
      fi
    fi
  '';

  # Startup lock wrapper. Launches hyprlock at session start and terminates the
  # session if the lock surface never appears.
  keystoneStartupLock = pkgs.writeShellScriptBin "keystone-startup-lock" (
    builtins.readFile ./keystone-startup-lock.sh
  );

  linkedCommands = [
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-launch-walker";
      relativePath = "modules/desktop/home/scripts/keystone-launch-walker.sh";
      package = keystoneLaunchWalker;
      runtimeInputs = [ pkgs.walker ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-desktop-config";
      relativePath = "modules/desktop/home/scripts/keystone-desktop-config.sh";
      package = keystoneDesktopConfig;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.hostname
        pkgs.python3
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-menu";
      relativePath = "modules/desktop/home/scripts/keystone-menu.sh";
      package = keystoneMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gnugrep
        hyprlandPkg
        pkgs.jq
        pkgs.libnotify
        pkgs.walker
        pkgs.xdg-utils
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-main-menu";
      relativePath = "modules/desktop/home/scripts/keystone-main-menu.sh";
      package = keystoneMainMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.ghostty
        pkgs.gnugrep
        pkgs.jq
        pkgs.keystone.ks
        pkgs.libnotify
        pkgs.systemd
        pkgs.walker
        pkgs.xdg-utils
      ];
      # Capability gating for ISSUE-REQ-1 (issue #390): the script's main_json
      # emits Photos/Agents/Contexts entries only when the corresponding env var
      # is "true". Values are evaluated at build time from the desktop config.
      extraEnvSetup = ''
        export KEYSTONE_MENU_SHOW_PHOTOS="${if cfg.photos.enable then "true" else "false"}"
        export KEYSTONE_MENU_SHOW_AGENTS="${if cfg.agents.enable then "true" else "false"}"
      '';
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-package-menu";
      relativePath = "modules/desktop/home/scripts/keystone-package-menu.sh";
      package = keystonePackageMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.ghostty
        pkgs.jq
        pkgs.keystone.ks
        pkgs.libnotify
        pkgs.nix
        pkgs.python3
        pkgs.ripgrep
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-setup-menu";
      relativePath = "modules/desktop/home/scripts/keystone-setup-menu.sh";
      package = keystoneSetupMenu;
      runtimeInputs = [
        pkgs.libnotify
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-audio-menu";
      relativePath = "modules/desktop/home/scripts/keystone-audio-menu.sh";
      package = keystoneAudioMenu;
      runtimeInputs = [
        pkgs.jq
        pkgs.libnotify
        pkgs.pulseaudio
        pkgs.python3
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-printer-menu";
      relativePath = "modules/desktop/home/scripts/keystone-printer-menu.sh";
      package = keystonePrinterMenu;
      runtimeInputs = [
        pkgs.cups
        pkgs.jq
        pkgs.libnotify
        pkgs.python3
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-monitor-menu";
      relativePath = "modules/desktop/home/scripts/keystone-monitor-menu.sh";
      package = keystoneMonitorMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        hyprlandPkg
        pkgs.jq
        pkgs.libnotify
        pkgs.python3
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-hardware-menu";
      relativePath = "modules/desktop/home/scripts/keystone-hardware-menu.sh";
      package = keystoneHardwareMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.keystone.ks
        pkgs.libnotify
        pkgs.systemd
        pkgs.util-linux
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-fingerprint-menu";
      relativePath = "modules/desktop/home/scripts/keystone-fingerprint-menu.sh";
      package = keystoneFingerprintMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.fprintd
        pkgs.gnugrep
        pkgs.jq
        pkgs.libnotify
        pkgs.util-linux
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-accounts-menu";
      relativePath = "modules/desktop/home/scripts/keystone-accounts-menu.sh";
      package = keystoneAccountsMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.less
        pkgs.libnotify
        pkgs.util-linux
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-secrets-menu";
      relativePath = "modules/desktop/home/scripts/keystone-secrets-menu.sh";
      package = keystoneSecretsMenu;
      runtimeInputs = [
        pkgs.keystone.agenix
        pkgs.coreutils
        pkgs.findutils
        pkgs.ghostty
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.less
        pkgs.libnotify
        pkgs.ripgrep
        pkgs.util-linux
        pkgs.walker
        pkgs.yubikey-manager
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-wifi-menu";
      relativePath = "modules/desktop/home/scripts/keystone-wifi-menu.sh";
      package = keystoneWifiMenu;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.libnotify
        pkgs.networkmanager
        pkgs.util-linux
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-menu-keybindings";
      relativePath = "modules/desktop/home/scripts/keystone-menu-keybindings.sh";
      package = keystoneMenuKeybindings;
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-startup-lock";
      relativePath = "modules/desktop/home/scripts/keystone-startup-lock.sh";
      package = keystoneStartupLock;
      runtimeInputs = [
        pkgs.coreutils
        hyprlandPkg
        pkgs.jq
        pkgs.procps
        pkgs.systemd
        pkgs.uwsm
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-context";
      relativePath = "modules/desktop/home/scripts/keystone-context.sh";
      package = keystoneContext;
      runtimeInputs = [
        hyprlandPkg
        pkgs.jq
        pkgs.util-linux
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-photos-menu";
      relativePath = "modules/desktop/home/scripts/keystone-photos-menu.sh";
      package = keystonePhotosMenu;
      runtimeInputs = [
        pkgs.jq
        pkgs.keystone.ks
        pkgs.libnotify
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-agent-menu";
      relativePath = "modules/desktop/home/scripts/keystone-agent-menu.sh";
      package = keystoneAgentMenu;
      runtimeInputs = [
        pkgs.keystone.ks
        pkgs.jq
        pkgs.walker
      ];
    })
    (mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-notes-inbox";
      relativePath = "modules/desktop/home/scripts/keystone-notes-inbox.sh";
      package = keystoneNotesInbox;
    })
  ];
in
{
  config = mkIf cfg.enable (
    mkMerge (
      [
        {
          home.packages = [
            keystoneScreenrecord
            keystoneAudioSwitch
            keystoneIdleToggle
            keystoneNightlightToggle
            keystoneBatteryMonitor
            keystoneDetach
            keystonePhotosMenu
            pkgs.jq
            pkgs.pulseaudio
            # Dependencies that should be available
            pkgs.gpu-screen-recorder
            pkgs.libxkbcommon # for xkbcli in keybindings menu
            pkgs.hypridle
          ];

          wayland.windowManager.hyprland.settings.exec-once =
            mkIf (cfg.audio.defaults.sink != null || cfg.audio.defaults.source != null)
              (mkAfter [
                "env KEYSTONE_AUDIO_DEFAULT_SINK='${
                  if cfg.audio.defaults.sink != null then cfg.audio.defaults.sink else ""
                }' KEYSTONE_AUDIO_DEFAULT_SOURCE='${
                  if cfg.audio.defaults.source != null then cfg.audio.defaults.source else ""
                }' keystone-audio-menu apply-config-defaults"
              ]);

          # Periodically check battery level and send a notification when low
          systemd.user.services.keystone-battery-monitor = {
            Unit = {
              Description = "Keystone low battery notification";
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${keystoneBatteryMonitor}/bin/keystone-battery-monitor";
            };
          };

          systemd.user.timers.keystone-battery-monitor = {
            Unit = {
              Description = "Timer for low battery notification";
            };
            Timer = {
              OnBootSec = "1min";
              OnUnitActiveSec = "1min";
            };
            Install = {
              WantedBy = [ "timers.target" ];
            };
          };
        }
        (mkIf (cfg.printer.default != null) {
          wayland.windowManager.hyprland.settings.exec-once = mkAfter [
            "env KEYSTONE_PRINTER_DEFAULT='${cfg.printer.default}' keystone-printer-menu apply-config-defaults"
          ];
        })
      ]
      ++ linkedCommands
    )
  );
}
