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

  };
}
