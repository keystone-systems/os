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
  config = mkIf desktopCfg.enable {
    programs.hyprlock = {
      enable = mkDefault true;
      settings = {
        source = mkDefault "${config.xdg.configHome}/keystone/current/theme/hyprlock.conf";

        general = {
          disable_loading_bar = true;
          no_fade_in = false;
        };

        auth = {
          fingerprint.enabled = true;
        };

        background = {
          monitor = "";
          # Use the theme background directly so the lockscreen renders on
          # first boot (before hyprpaper sets the wallpaper). The theme
          # symlink is created by home-manager activation, which runs
          # before greetd starts the session.
          path = "${config.xdg.configHome}/keystone/current/background";
          blur_passes = 3;
          brightness = 0.5;
        };

        input-field = {
          monitor = "";
          size = "600, 100";
          position = "0, 0";
          halign = "center";
          valign = "center";

          inner_color = "$inner_color";
          outer_color = "$outer_color";
          outline_thickness = 4;

          font_family = "JetBrainsMono Nerd Font";
          font_size = 32;
          font_color = "$font_color";

          placeholder_color = "$placeholder_color";
          placeholder_text = "  Enter Password";
          check_color = "$check_color";
          fail_text = "Wrong ($ATTEMPTS)";

          rounding = 0;
          shadow_passes = 0;
          fade_on_empty = false;
        };

        label = {
          monitor = "";
          text = "$FPRINTPROMPT";
          text_align = "center";
          color = "$font_color";
          font_size = 24;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, -100";
          halign = "center";
          valign = "center";
        };
      };
    };
  };
}
