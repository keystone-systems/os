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
  config = lib.mkIf (cfg.enable && cfg.components.mako) {
    services.mako = {
      enable = true;

      settings = {
        # Default notification settings
        default-timeout = 5000; # 5 seconds

        # Visual settings
        background-color = "#2b303b";
        text-color = "#ffffff";
        border-color = "#33ccff";
        border-size = 2;
        border-radius = 10;

        # Position and layout
        anchor = "top-right";
        margin = "10";
        padding = "10";

        # Size constraints
        width = 300;
        height = 100;

        # Font
        font = "CaskaydiaMono Nerd Font 11";

        # Icons
        icons = true;
        max-icon-size = 64;

        # Group notifications
        group-by = "app-name";
      };
    };
  };
}
