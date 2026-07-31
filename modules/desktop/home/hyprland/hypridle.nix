{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
  lockCommand = "pidof hyprlock || hyprlock";
in
{
  config = mkIf desktopCfg.enable {
    # UWSM session target fix: greetd starts wayland-session-envelope@ but not
    # wayland-session@ which is what binds to graphical-session.target.
    # hypridle and other services depend on graphical-session.target, so we need
    # to ensure wayland-session@ is started when the envelope starts.
    # See: https://github.com/hyprwm/Hyprland/issues/9342
    systemd.user.targets."wayland-session-envelope@Hyprland" = {
      Unit = {
        Wants = [ "wayland-session@Hyprland.target" ];
      };
    };

    services.hypridle = {
      enable = mkDefault true;
      settings = {
        general = {
          lock_cmd = lockCommand;
          before_sleep_cmd = lockCommand;
          after_sleep_cmd = "hyprctl dispatch dpms on";
          ignore_dbus_inhibit = true;
          inhibit_sleep = 3;
        };

        listener = [
          # Lock screen at 5 minutes
          {
            timeout = 300;
            on-timeout = lockCommand;
          }
          # DPMS off at 5.5 minutes
          {
            timeout = 330;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
          }
        ];
      };
    };
  };
}
