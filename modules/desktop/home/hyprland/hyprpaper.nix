{
  config,
  lib,
  pkgs,
  keystoneInputs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
in
{
  config = mkIf desktopCfg.enable {
    services.hyprpaper = {
      enable = mkDefault true;
      package = keystoneInputs.hyprpaper.packages.${pkgs.stdenv.hostPlatform.system}.hyprpaper;
      # TODO: remove once home-manager is updated — newer HM defaults importantPrefixes to ["$" "monitor"]
      importantPrefixes = [
        "$"
        "monitor"
      ];
      settings = {
        splash = false;
        preload = [
          "${config.xdg.configHome}/keystone/current/background"
        ];
        # CRITICAL: hyprpaper 0.8.3+ (hyprwm commit 1d8df14, "migrate to
        # hyprtoolkit") removed the bare `wallpaper=<monitor>,<path>`
        # parser. `wallpaper` is now a hyprlang special-category; a list
        # of attrsets renders as repeated `wallpaper { ... }` blocks via
        # home-manager's toHyprconf generator. The empty-monitor form
        # (",<path>") is silently dropped by listKeysForSpecialCategory
        # — see hyprwm/hyprpaper@feafd06 ("support * as wildcard monitor
        # for default wallpapers"). Do not revert to the shorthand.
        wallpaper = [
          {
            monitor = "*";
            path = "${config.xdg.configHome}/keystone/current/background";
          }
        ];
      };
    };
  };
}
