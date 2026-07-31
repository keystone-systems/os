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
  cfg = desktopCfg.hyprland;

  browserCommand =
    {
      "chromium" = "uwsm app -- chromium --new-window --ozone-platform=wayland";
      "google-chrome-stable" = "uwsm app -- google-chrome-stable --new-window --ozone-platform=wayland";
      "firefox" = "uwsm app -- firefox --new-window";
    }
    .${desktopCfg.browser} or "uwsm app -- ${desktopCfg.browser} --new-window";
  hyprlandPkg = keystoneInputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
in
{
  imports = [
    ./appearance.nix
    ./autostart.nix
    ./bindings.nix
    ./environment.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./hyprsunset.nix
    ./input.nix
    ./layout.nix
    ./monitors.nix
  ];

  options.keystone.desktop.hyprland = {
    terminal = mkOption {
      type = types.str;
      default = "uwsm app -- ghostty";
      description = "Default terminal application";
    };

    fileManager = mkOption {
      type = types.str;
      default = "uwsm app -- nautilus --new-window";
      description = "Default file manager application";
    };

    scale = mkOption {
      type = types.int;
      default = 2;
      description = "Display scale factor (1 for 1x displays, 2 for 2x/HiDPI displays)";
    };

    modifierKey = mkOption {
      type = types.str;
      default = "SUPER";
      description = ''
        Primary modifier key for Hyprland keybindings (e.g., 'SUPER', 'ALT').
        SUPER is recommended because with altwin:swap_alt_win enabled (default),
        physical Alt sends Super keycodes - placing frequent window management
        on the ergonomic thumb position. Physical Super + arrows then sends
        Alt + arrows for browser back/forward navigation.
      '';
    };

    capslockAsControl = mkOption {
      type = types.bool;
      default = true;
      description = "Remap Caps Lock to Control key";
    };

    touchpad = {
      dragLock = mkOption {
        type = types.bool;
        default = false;
        description = "Enable drag lock (double-tap-hold to drag, lift finger, continue dragging until tap)";
      };
    };
  };

  config = mkIf desktopCfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprlandPkg;
      # Disabled since programs.hyprland.withUWSM is enabled on NixOS
      systemd.enable = false;

      # Source theme file for runtime theme switching
      extraConfig = ''
        source = ~/.config/keystone/current/theme/hyprland.conf
      '';

      settings = {
        # Default applications
        "$terminal" = mkDefault cfg.terminal;
        "$fileManager" = mkDefault cfg.fileManager;
        "$browser" = mkDefault browserCommand;

        # Disable start-hyprland warning - UWSM handles session management
        # See: docs/specs/REQ-001-keystone-os.md#about-the-start-hyprland-warning
        misc.disable_watchdog_warning = true;

        # Hardware cursors don't handle rotated monitors correctly,
        # causing the cursor to be invisible or stuck on transformed displays.
        # See: https://github.com/hyprwm/Hyprland/issues/8993
        cursor.no_hardware_cursors = true;
      };
    };

    # Supporting packages
    home.packages = with pkgs; [
      wofi
      waybar
      libnotify
      wl-clipboard
      wl-clip-persist
      clipse
      grim
      slurp
      brightnessctl
      playerctl
    ];
  };
}
