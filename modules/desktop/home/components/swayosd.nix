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
    # SwayOSD for volume/brightness on-screen display
    services.swayosd = {
      enable = mkDefault true;
      topMargin = 0.95; # Near bottom of screen
    };

    # Ensure the package is available
    home.packages = with pkgs; [
      swayosd
    ];
  };
}
