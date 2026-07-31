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
    programs.ghostty = {
      enable = true;
      settings = {
        # Window settings
        window-padding-x = 14;
        window-padding-y = 14;
        background-opacity = 0.95;
        window-decoration = "none";
        confirm-close-surface = false;
        resize-overlay = "never";

        # Font settings
        font-family = "JetBrainsMono Nerd Font";
        font-style = "Regular";
        font-size = 12;

        # Cursor settings
        cursor-style = "block";
        cursor-style-blink = false;

        # Mouse settings
        mouse-scroll-multiplier = 0.95;

        # Keybindings
        keybind = [
          # Clipboard
          "shift+insert=paste_from_clipboard"
          "control+insert=copy_to_clipboard"
          # Tab navigation
          "ctrl+shift+w=previous_tab"
          "ctrl+shift+e=new_tab"
          "ctrl+shift+r=next_tab"
          "ctrl+shift+c=close_surface"
          # Unbind Zellij tab shortcuts
          "ctrl+page_up=unbind"
          "ctrl+page_down=unbind"
          "ctrl+tab=unbind"
          # Unbind Ghostty splits - Zellij handles all pane management
          "ctrl+shift+o=unbind"
          "ctrl+alt+up=unbind"
          "ctrl+alt+down=unbind"
          "ctrl+alt+left=unbind"
          "ctrl+alt+right=unbind"
        ];
      }
      # Always load theme from the dynamic symlink so theme switching works at runtime
      // {
        config-file = "${config.xdg.configHome}/keystone/current/theme/ghostty.conf";
      };
    };
  };
}
