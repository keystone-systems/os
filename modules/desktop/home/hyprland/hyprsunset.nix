{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
in
{
  # hyprsunset is started via autostart.nix exec-once
  # This module provides the configuration file

  config = mkIf desktopCfg.enable {
    xdg.configFile."hypr/hyprsunset.conf".text = mkDefault ''
      # Makes hyprsunset do nothing to the screen by default
      # Without this, the default applies some tint to the monitor
      profile {
          time = 07:00
          identity = true
      }

      # Nightlight at 8pm with warm temperature
      profile {
          time = 20:00
          temperature = 4000
      }
    '';

    home.packages = with pkgs; [
      hyprsunset
    ];
  };
}
