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
  config = lib.mkIf cfg.enable {
    # Basic Hyprland configuration via home-manager
    # Most configuration is handled by the NixOS module
    # This provides user-level settings and keybindings

    wayland.windowManager.hyprland = {
      enable = true;

      settings = {
        # Monitor configuration - use auto-detect by default
        monitor = ",preferred,auto,1";

        # Execute apps at launch
        exec-once = [
          # Waybar, mako, and hyprpaper are launched via their respective modules
          # hypridle is launched via its module for idle management
        ];

        # Environment variables
        env = [
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"
        ];

        # Input configuration
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          sensitivity = 0;
          touchpad = {
            natural_scroll = true;
          };
        };

        # General window configuration
        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
          "col.inactive_border" = "rgba(595959aa)";
          resize_on_border = false;
          allow_tearing = false;
          layout = "dwindle";
        };

        # Decoration settings
        decoration = {
          rounding = 10;
          active_opacity = 1.0;
          inactive_opacity = 1.0;

          drop_shadow = true;
          shadow_range = 4;
          shadow_render_power = 3;
          "col.shadow" = "rgba(1a1a1aee)";

          blur = {
            enabled = true;
            size = 3;
            passes = 1;
            vibrancy = 0.1696;
          };
        };

        # Animation settings
        animations = {
          enabled = true;
          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
          ];
        };

        # Layout configuration
        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        master = {
          new_status = "master";
        };

        # Misc settings
        misc = {
          force_default_wallpaper = 0;
          disable_hyprland_logo = true;
        };

        # Key bindings
        "$mod" = "SUPER";

        bind = [
          # Application launchers
          "$mod, Return, exec, ghostty"
          "$mod, Q, killactive,"
          "$mod, E, exec, nautilus"
          "$mod, V, togglefloating,"
          "$mod, P, pseudo,"
          "$mod, J, layoutmsg, togglesplit"
          "$mod, L, exec, hyprlock"
          "$mod, B, exec, chromium"

          # Move focus
          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"

          # Switch workspaces
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

          # Move window to workspace
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

          # Scroll through workspaces
          "$mod, mouse_down, workspace, e+1"
          "$mod, mouse_up, workspace, e-1"

          # Screenshot
          ", Print, exec, hyprshot -m region"
          "$mod, Print, exec, hyprshot -m window"
          "$mod SHIFT, Print, exec, hyprshot -m output"
        ];

        # Mouse bindings
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        # Media keys
        bindl = [
          ", XF86AudioMute, exec, pamixer --toggle-mute"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPrev, exec, playerctl previous"
        ];

        bindle = [
          ", XF86AudioRaiseVolume, exec, pamixer -i 5"
          ", XF86AudioLowerVolume, exec, pamixer -d 5"
          ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
          ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ];

        # Window rules
        windowrulev2 = [
          "suppressevent maximize, class:.*"
        ];
      };
    };
  };
}
