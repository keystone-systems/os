# Hyprland keybindings for the Keystone desktop environment.
# Defines all keyboard shortcuts including window management, workspace
# navigation and application launchers.
#
# Implements REQ-002 (dt-bind-002, dt-bind-010, dt-bind-011, dt-bind-012, dt-menu-001, dt-help-001)
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
in
{
  config = mkIf desktopCfg.enable {
    wayland.windowManager.hyprland.settings = {
      "$mod" = mkDefault cfg.modifierKey;

      bind = mkDefault [
        # Application launchers
        "$mod, Return, exec, ghostty"
        "$mod, Space, exec, walker"
        "$mod, B, exec, $browser"
        "$mod, E, exec, $fileManager"

        # Menu system
        "$mod, Escape, exec, keystone-menu system"
        "$mod, K, exec, keystone-menu-keybindings"

        # Window management
        "$mod, W, killactive,"
        "CTRL ALT, DELETE, exec, hyprctl dispatch closewindow address:*"
        "$mod SHIFT, V, togglefloating,"
        "$mod, P, pseudo,"

        # Move focus with vim keys
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, T, layoutmsg, togglesplit"

        # Move focus with arrow keys
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        # Swap windows with arrow keys
        "$mod SHIFT, left, swapwindow, l"
        "$mod SHIFT, right, swapwindow, r"
        "$mod SHIFT, up, swapwindow, u"
        "$mod SHIFT, down, swapwindow, d"

        # Workspace navigation
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Move to workspace
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        # TAB between workspaces
        "$mod, TAB, workspace, e+1"
        "$mod SHIFT, TAB, workspace, e-1"
        "$mod CTRL, TAB, workspace, previous"

        # Scroll through workspaces with comma/period
        "$mod, comma, workspace, -1"
        "$mod, period, workspace, +1"

        # Move window to adjacent workspace
        "$mod SHIFT, comma, movetoworkspace, -1"
        "$mod SHIFT, period, movetoworkspace, +1"
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"

        # Cycle through windows (ALT+TAB)
        "ALT, TAB, cyclenext,"
        "ALT SHIFT, TAB, cyclenext, prev"
        "ALT, TAB, bringactivetotop,"
        "ALT SHIFT, TAB, bringactivetotop,"

        # Special workspace (scratchpad)
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        # Fullscreen
        "$mod, F, fullscreen,"
        "SHIFT, F11, fullscreen, 0"
        "ALT, F11, fullscreen, 1"

        # Toggle split direction
        "$mod SHIFT, T, layoutmsg, togglesplit"

        # Resize windows
        "$mod, minus, resizeactive, -100 0"
        "$mod, equal, resizeactive, 100 0"
        "$mod SHIFT, minus, resizeactive, 0 -100"
        "$mod SHIFT, equal, resizeactive, 0 100"

        # Universal copy/paste/cut
        "$mod, C, sendshortcut, CTRL, Insert,"
        "$mod, V, sendshortcut, SHIFT, Insert,"
        "$mod, X, sendshortcut, CTRL, X,"

        # Clipboard manager
        "$mod CTRL, V, exec, ghostty --class clipse -e clipse"

        # Emoji picker
        "$mod CTRL, E, exec, walker -m symbols"

        # Utilities
        "$mod SHIFT, Space, exec, killall -SIGUSR1 waybar"
        "$mod, Backspace, exec, hyprctl dispatch setprop \"address:$(hyprctl activewindow -j | jq -r '.address')\" opaque toggle"

        # Notifications (mako)
        "$mod SHIFT, N, exec, makoctl dismiss"
        "$mod ALT, N, exec, makoctl dismiss --all"
        "$mod CTRL SHIFT, N, exec, makoctl mode -t do-not-disturb"

        # Screenshots
        ", Print, exec, keystone-screenshot"
        "SHIFT, Print, exec, keystone-screenshot smart clipboard"
        "$mod, Print, exec, hyprpicker -a"

        # Toggle idle/nightlight
        "$mod CTRL, I, exec, keystone-idle-toggle"
        "$mod CTRL, N, exec, keystone-nightlight-toggle"
      ];

      # Mouse bindings
      bindm = mkDefault [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # Volume and brightness (release bindings)
      bindel = mkDefault [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
      ];

      # Media keys (locked bindings)
      bindl = mkDefault [
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
        ", XF86PowerOff, exec, keystone-menu system"
        # Lid switch bindings - lock AND suspend on close
        ", switch:on:Lid Switch, exec, pidof hyprlock || hyprlock; systemctl suspend"
        ", switch:off:Lid Switch, exec, hyprctl dispatch dpms on"
      ];
    };
  };
}
