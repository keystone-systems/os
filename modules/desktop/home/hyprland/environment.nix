{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
  cfg = config.keystone.desktop.hyprland;
  terminalCfg = config.keystone.terminal;
  hasNvidiaDrivers =
    if osConfig ? services.xserver.videoDrivers then
      builtins.elem "nvidia" osConfig.services.xserver.videoDrivers
    else
      false;
  nvidiaEnv = [
    "NVD_BACKEND,direct"
    "LIBVA_DRIVER_NAME,nvidia"
    "__GLX_VENDOR_LIBRARY_NAME,nvidia"
  ];
in
{
  config = mkIf desktopCfg.enable {
    wayland.windowManager.hyprland.settings = {
      env = mkDefault (
        (optionals hasNvidiaDrivers nvidiaEnv)
        ++ [
          # Display scaling
          "GDK_SCALE,${toString cfg.scale}"

          # Cursor size
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"

          # Cursor theme
          "XCURSOR_THEME,Adwaita"
          "HYPRCURSOR_THEME,Adwaita"

          # Force all apps to use Wayland
          "GDK_BACKEND,wayland"
          "QT_QPA_PLATFORM,wayland"
          "QT_STYLE_OVERRIDE,kvantum"
          "SDL_VIDEODRIVER,wayland"
          "MOZ_ENABLE_WAYLAND,1"
          "ELECTRON_OZONE_PLATFORM_HINT,wayland"
          "OZONE_PLATFORM,wayland"

          # Make Chromium use XCompose and all Wayland
          "CHROMIUM_FLAGS,\"--enable-features=UseOzonePlatform --ozone-platform=wayland --gtk-version=4\""

          # Make .desktop files available for wofi
          "XDG_DATA_DIRS,$XDG_DATA_DIRS:$HOME/.nix-profile/share:/nix/var/nix/profiles/default/share"
          "PATH,$HOME/.local/bin:$PATH"

          # Use XCompose file
          "XCOMPOSEFILE,~/.XCompose"
          "EDITOR,${terminalCfg.editor}"

          # SSH agent socket for child processes
          "SSH_AUTH_SOCK,$XDG_RUNTIME_DIR/ssh-agent"

          # GTK theme
          "GTK_THEME,Adwaita:dark"

          # Allow software rendering fallback in VMs (no-op on bare metal with GPU)
          "WLR_RENDERER_ALLOW_SOFTWARE,1"
        ]
      );

      xwayland = mkDefault {
        force_zero_scaling = true;
      };

      ecosystem = mkDefault {
        no_update_news = true;
      };
    };
  };
}
