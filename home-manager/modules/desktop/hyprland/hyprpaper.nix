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
  config = lib.mkIf (cfg.enable && cfg.components.hyprpaper) {
    services.hyprpaper = {
      enable = true;

      settings = {
        # Preload wallpapers (using a simple color for now)
        # Users can override this with their own wallpaper
        preload = [
          # Default: use a solid color wallpaper
          # Users can add their own: "/path/to/wallpaper.png"
        ];

        # Set wallpaper for all monitors
        wallpaper = [
          # Format: "monitor,/path/to/wallpaper"
          # Default: no wallpaper set, Hyprland will use default background
          # Users can configure: ",/path/to/wallpaper.png" for all monitors
        ];

        # Disable IPC for performance
        ipc = "off";

        # Splash screen
        splash = false;
      };
    };

    # Note: Users can configure wallpapers by overriding:
    # services.hyprpaper.settings.preload = [ "/path/to/wallpaper.png" ];
    # services.hyprpaper.settings.wallpaper = [ ",/path/to/wallpaper.png" ];
  };
}
