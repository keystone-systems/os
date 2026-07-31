# Waybar status bar configuration for the Keystone desktop environment.
# Named workspaces display context slugs (e.g., "catalyst") instead of numbers.
#
# Implements REQ-002 (dt-bar-001, dt-record-001.2, dt-record-001.3)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  config = mkIf cfg.enable {
    programs.waybar = {
      enable = mkDefault true;
      # home-manager's `programs.waybar.systemd.enable` is mkEnableOption and
      # defaults to false. Without it, only the nixpkgs-shipped waybar.service
      # unit lands in the user profile — no wants symlink is created, so the
      # unit never auto-starts at graphical-session.target activation.
      # Enabling here makes systemd the canonical start path under UWSM
      # (which activates graphical-session.target on Hyprland session login).
      systemd.enable = mkDefault true;
      systemd.target = "graphical-session.target";
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          spacing = 0;
          height = 26;
          reload_style_on_change = true;

          modules-left = [
            "custom/keystone"
            "hyprland/workspaces"
          ];
          modules-center = [
            "clock"
            "custom/screenrecording-indicator"
          ];
          modules-right = [
            "group/tray-expander"
            "bluetooth"
            "network"
            "pulseaudio"
            "cpu"
            "battery"
          ];

          "hyprland/workspaces" = {
            on-click = "activate";
            # {name} shows the workspace name for named workspaces (e.g., "catalyst")
            # and the workspace number for numbered workspaces (e.g., "1")
            format = "{name}";
            persistent-workspaces = {
              "1" = [ ];
              "2" = [ ];
              "3" = [ ];
              "4" = [ ];
              "5" = [ ];
            };
          };

          "custom/keystone" = {
            format = "";
            on-click-right = "ghostty";
            tooltip-format = "Keystone Desktop";
          };

          cpu = {
            interval = 5;
            format = "󰍛";
            on-click = "ghostty -e btop";
          };

          clock = {
            format = "{:L%A %H:%M}";
            format-alt = "{:L%d %B W%V %Y}";
            tooltip = false;
          };

          # Screen recording indicator - updates via signal instead of polling
          # signal = 8 means waybar listens for RTMIN+8 (sent by keystone-screenrecord)
          # See: modules/keystone/desktop/home/scripts/default.nix
          "custom/screenrecording-indicator" = {
            exec = "pgrep -f '[g]pu-screen-recorder' >/dev/null && echo '{\"text\": \"󰻂\", \"tooltip\": \"Stop recording\", \"class\": \"active\"}' || echo '{\"text\": \"\"}'";
            return-type = "json";
            signal = 8;
            on-click = "keystone-screenrecord";
          };

          network = {
            format-icons = [
              "󰤯"
              "󰤟"
              "󰤢"
              "󰤥"
              "󰤨"
            ];
            format = "{icon}";
            format-wifi = "{icon}";
            format-ethernet = "󰀂";
            format-disconnected = "󰤮";
            tooltip-format-wifi = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
            tooltip-format-ethernet = "⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
            tooltip-format-disconnected = "Disconnected";
            interval = 3;
            spacing = 1;
            on-click = "keystone-wifi-menu open-menu";
          };

          battery = {
            format = "{capacity}% {icon}";
            format-discharging = "{icon}";
            format-charging = "{icon}";
            format-plugged = "";
            format-icons = {
              charging = [
                "󰢜"
                "󰂆"
                "󰂇"
                "󰂈"
                "󰢝"
                "󰂉"
                "󰢞"
                "󰂊"
                "󰂋"
                "󰂅"
              ];
              default = [
                "󰁺"
                "󰁻"
                "󰁼"
                "󰁽"
                "󰁾"
                "󰁿"
                "󰂀"
                "󰂁"
                "󰂂"
                "󰁹"
              ];
            };
            format-full = "󰂅";
            tooltip-format-discharging = "{power:>1.0f}W↓ {capacity}%";
            tooltip-format-charging = "{power:>1.0f}W↑ {capacity}%";
            interval = 5;
            on-click = "keystone-menu system";
            states = {
              warning = 20;
              critical = 10;
            };
          };

          bluetooth = {
            format = "";
            format-disabled = "󰂲";
            format-connected = "󰂱";
            format-no-controller = "";
            tooltip-format = "Devices connected: {num_connections}";
            on-click = "blueman-manager";
          };

          pulseaudio = {
            format = "{icon}";
            on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            tooltip-format = "Playing at {volume}%";
            scroll-step = 5;
            format-muted = "";
            format-icons = {
              default = [
                ""
                ""
                ""
              ];
            };
          };

          "group/tray-expander" = {
            orientation = "inherit";
            drawer = {
              transition-duration = 600;
              children-class = "tray-group-item";
            };
            modules = [
              "custom/expand-icon"
              "tray"
            ];
          };

          "custom/expand-icon" = {
            format = "";
            tooltip = false;
          };

          tray = {
            icon-size = 12;
            spacing = 17;
          };
        };
      };

      style = ''
        @import "${config.xdg.configHome}/keystone/current/theme/waybar.css";

        * {
          background-color: @background;
          color: @foreground;
          border: none;
          border-radius: 0;
          min-height: 0;
          font-family: 'JetBrainsMono Nerd Font';
          font-size: 12px;
        }

        .modules-left {
          margin-left: 8px;
        }

        .modules-right {
          margin-right: 8px;
        }

        /* Base workspace button styling - DO NOT use "all: initial" as it breaks CSS cascade */
        #workspaces button {
          font-family: 'JetBrainsMono Nerd Font';
          font-size: 12px;
          font-weight: normal;
          background-color: transparent;
          color: @foreground;
          padding: 0 6px;
          margin: 0 1.5px;
          min-width: 9px;
          border: none;
          border-radius: 0;
        }

        /* Empty workspaces - less visible */
        #workspaces button.empty {
          opacity: 0.5;
        }

        /* Active workspace - MUST come last for CSS cascade priority */
        #workspaces button.active, #workspaces button.active label {
          color: #B8A26C;
          font-weight: bold;
        }

        #cpu,
        #battery,
        #pulseaudio,
        #custom-keystone {
          min-width: 12px;
          margin: 0 7.5px;
        }

        #tray {
          margin-right: 16px;
        }

        #bluetooth {
          margin-right: 17px;
        }

        #network {
          margin-right: 13px;
        }

        #custom-expand-icon {
          margin-right: 18px;
        }

        tooltip {
          padding: 2px;
        }

        #clock {
          margin-left: 8.75px;
        }

        #custom-screenrecording-indicator {
          min-width: 20px;
          padding: 0 8px;
        }

        #custom-screenrecording-indicator.active {
          color: #ef5350;
          font-weight: bold;
        }
      '';
    };
  };
}
