{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
  cfg = config.keystone.desktop.hyprland;
  # Build kb_options based on configuration
  # - altwin:swap_alt_win: Swap Alt and Super keys for ergonomic window management
  #   Physical Alt (thumb position) → Super keycodes → Hyprland $mod
  #   Physical Super → Alt keycodes → Browser back/forward (Alt+Left/Right)
  # - ctrl:nocaps or compose:caps: Caps Lock behavior
  capsOption = if cfg.capslockAsControl then "ctrl:nocaps" else "compose:caps";
  kbOptions = "${capsOption},altwin:swap_alt_win";
in
{
  config = mkIf desktopCfg.enable {
    wayland.windowManager.hyprland.settings = {
      input = mkDefault {
        kb_layout = "us";
        kb_options = kbOptions;
        follow_mouse = 1;
        sensitivity = 0;
        scroll_factor = 0.4; # Reduce scroll speed (omarchy default)

        touchpad = {
          natural_scroll = true;
          drag_lock = cfg.touchpad.dragLock;
        };
      };

      # Note: workspace_swipe was removed in Hyprland 0.51+
      # Use new gesture syntax if needed: gesture = fingers, direction, action
    };
  };
}
