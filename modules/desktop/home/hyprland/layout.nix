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
    wayland.windowManager.hyprland.settings = {
      general = {
        layout = mkDefault "dwindle";
      };

      dwindle = mkDefault {
        preserve_split = true;
        force_split = 2;
      };

      master = mkDefault {
        new_status = "master";
      };

      # Hyprland 0.54+ windowrule syntax: "action value, match:field pattern"
      # tile/float need an explicit "on" — bare "tile" or "float" is a parse error.
      # match:class matches WM_CLASS; multiple match: clauses AND together.
      windowrule = mkDefault [
        # Chromium --app mode misidentifies windows as popups, so they float
        # and overlap your tiled layout. Force them back into tiles.
        "tile on, match:class ^(chromium)$"

        # Volume and bluetooth panels are small fixed dialogs — floating
        # keeps them out of the tiling grid where they'd get awkwardly stretched.
        "float on, match:class ^(org.pulseaudio.pavucontrol|.blueman-manager-wrapped|blueman-manager)$"

        # Subtle transparency gives depth cues between focused and background
        # windows. 0.97 focused / 0.9 unfocused is barely perceptible but
        # makes the active window pop without feeling like frosted glass.
        # Video, streaming, and gaming apps get full opacity so content
        # isn't washed out.
        "opacity 0.97 0.9, match:class .*"
        "opacity 1 1, match:class ^(chromium|google-chrome|google-chrome-unstable)$, match:title .*Youtube.*"
        "opacity 1 0.97, match:class ^(chromium|google-chrome|google-chrome-unstable)$"
        "opacity 0.97 0.9, match:class ^(chrome-.*-Default)$"
        "opacity 1 1, match:class ^(chrome-youtube.*-Default)$"
        "opacity 1 1, match:class ^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
        "opacity 1 1, match:class ^(com.libretro.RetroArch|steam)$"

        # Clipse clipboard picker should appear as a centered overlay you can
        # quickly select from and dismiss — not a tiled pane.
        "float on, match:class (clipse)"
        "size 622 652, match:class (clipse)"

        # Quick-capture notes inbox opens as a floating dialog so you can
        # jot something down without disrupting your workspace layout.
        "float on, match:class ^(com.mitchellh.ghostty)$, match:title ^(keystone-notes-inbox)$"
        "center on, match:class ^(com.mitchellh.ghostty)$, match:title ^(keystone-notes-inbox)$"
        "size 1000 700, match:class ^(com.mitchellh.ghostty)$, match:title ^(keystone-notes-inbox)$"

        # hyprpolkitagent's password dialog is a 486×246 modal but Hyprland
        # tiles it by default — `xdg_toplevel.configure` arrives with
        # WindowMaximized state, the input field gets stretched into
        # whichever tile slot it lands in, and the QML theming looks
        # broken because the layout assumes the natural size. The Qt app
        # doesn't set a Wayland app_id (class is empty in `hyprctl
        # clients`), so match on the empty class AND the title together.
        # AND-matching on class ^$ scopes the rule to classless windows
        # so localized prompt titles in other apps (matching English
        # `Authentication required`) don't get accidentally floated;
        # hyprpolkitagent itself is the only window we've seen ship with
        # no class. `pin` keeps it above tiled windows so an active
        # terminal can't focus-steal it.
        "float on, match:class ^$, match:title ^(Authentication required)$"
        "center on, match:class ^$, match:title ^(Authentication required)$"
        "size 486 246, match:class ^$, match:title ^(Authentication required)$"
        "pin on, match:class ^$, match:title ^(Authentication required)$"
        # Global decoration.blur shows backdrop proportional to (1 - alpha),
        # and Hyprland 0.54 dropped per-window `blur on`, so opacity is the
        # only lever for a translucent-blurred dialog. 0.85/0.78 is the
        # readability/blur sweet spot. Rounding matches the desktop.
        "opacity 0.85 0.78, match:class ^$, match:title ^(Authentication required)$"
        "rounding 12, match:class ^$, match:title ^(Authentication required)$"
      ];

      # layerrule disabled until Hyprland 0.52+ syntax is confirmed
      # layerrule = mkDefault [
      #   "blur on, namespace:wofi"
      #   "blur on, namespace:waybar"
      # ];
    };
  };
}
