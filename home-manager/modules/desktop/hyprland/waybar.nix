{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.desktop.hyprland;
in
{
  config = lib.mkIf (cfg.enable && cfg.components.waybar) {
    programs.waybar = {
      enable = true;

      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 30;
          spacing = 4;

          modules-left = [
            "hyprland/workspaces"
            "hyprland/window"
          ];
          modules-center = [ "clock" ];
          modules-right = [
            "pulseaudio"
            "network"
            "cpu"
            "memory"
            "battery"
            "tray"
          ];

          "hyprland/workspaces" = {
            disable-scroll = false;
            all-outputs = true;
            format = "{icon}";
            format-icons = {
              "1" = "1";
              "2" = "2";
              "3" = "3";
              "4" = "4";
              "5" = "5";
              "6" = "6";
              "7" = "7";
              "8" = "8";
              "9" = "9";
              "10" = "10";
            };
          };

          "hyprland/window" = {
            format = "{}";
            max-length = 50;
            separate-outputs = true;
          };

          "tray" = {
            spacing = 10;
          };

          "clock" = {
            timezone = "UTC";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            format = "{:%Y-%m-%d %H:%M}";
            format-alt = "{:%A, %B %d, %Y}";
          };

          "cpu" = {
            format = "CPU {usage}%";
            tooltip = false;
          };

          "memory" = {
            format = "MEM {}%";
          };

          "battery" = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "BAT {capacity}%";
            format-charging = "CHG {capacity}%";
            format-plugged = "AC {capacity}%";
            format-alt = "{time} {icon}";
          };

          "network" = {
            format-wifi = "WiFi {essid} ({signalStrength}%)";
            format-ethernet = "ETH {ipaddr}";
            tooltip-format = "{ifname} via {gwaddr}";
            format-linked = "{ifname} (No IP)";
            format-disconnected = "Disconnected";
            format-alt = "{ifname}: {ipaddr}/{cidr}";
          };

          "pulseaudio" = {
            format = "VOL {volume}%";
            format-bluetooth = "BT {volume}%";
            format-bluetooth-muted = "BT MUTE";
            format-muted = "MUTE";
            format-icons = {
              default = [
                ""
                ""
                ""
              ];
            };
            on-click = "pavucontrol";
          };
        };
      };

      style = ''
        * {
          border: none;
          border-radius: 0;
          font-family: "CaskaydiaMono Nerd Font", monospace;
          font-size: 13px;
        }

        window#waybar {
          background-color: rgba(43, 48, 59, 0.9);
          color: #ffffff;
          transition-property: background-color;
          transition-duration: 0.5s;
        }

        #workspaces button {
          padding: 0 5px;
          background-color: transparent;
          color: #ffffff;
        }

        #workspaces button:hover {
          background: rgba(0, 0, 0, 0.2);
        }

        #workspaces button.active {
          background-color: #64727d;
        }

        #workspaces button.urgent {
          background-color: #eb4d4b;
        }

        #window,
        #clock,
        #battery,
        #cpu,
        #memory,
        #network,
        #pulseaudio,
        #tray {
          padding: 0 10px;
          color: #ffffff;
        }

        #battery.charging, #battery.plugged {
          color: #26a65b;
        }

        #battery.warning:not(.charging) {
          color: #ffbe76;
        }

        #battery.critical:not(.charging) {
          color: #f53c3c;
        }

        #pulseaudio.muted {
          color: #90b1b1;
        }
      '';
    };
  };
}
