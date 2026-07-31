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
    # Clipboard manager packages (clipse configuration is in hyprland/autostart.nix and layout.nix)
    home.packages = with pkgs; [
      clipse
      wl-clipboard
      wl-clip-persist
    ];

    # Clipse configuration
    xdg.configFile."clipse/config.json".text = builtins.toJSON {
      historySize = 100;
      maxCharacters = 1000;
      themeFile = "${config.xdg.configHome}/keystone/current/theme/clipse.json";
    };
  };
}
