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
  config = lib.mkIf (cfg.enable && cfg.components.hypridle) {
    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock"; # Avoid starting multiple hyprlock instances
          before_sleep_cmd = "loginctl lock-session"; # Lock before suspend
          after_sleep_cmd = "hyprctl dispatch dpms on"; # Turn on display after suspend
        };

        listener = [
          # Lock screen after 5 minutes of inactivity
          {
            timeout = 300; # 5 minutes
            on-timeout = "loginctl lock-session";
          }
          # Turn off display after 6 minutes
          {
            timeout = 360; # 6 minutes
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
          # Suspend system after 10 minutes
          {
            timeout = 600; # 10 minutes
            on-timeout = "systemctl suspend";
          }
        ];
      };
    };
  };
}
