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
  meta.maintainers = [ ];

  imports = [
    ./hyprland-config.nix
    ./waybar.nix
    ./mako.nix
    ./hyprpaper.nix
    ./hyprlock.nix
    ./hypridle.nix
  ];

  options.programs.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland desktop environment with home-manager configuration";

    components = {
      waybar = lib.mkEnableOption "Waybar status bar" // {
        default = true;
      };
      mako = lib.mkEnableOption "Mako notification daemon" // {
        default = true;
      };
      hyprpaper = lib.mkEnableOption "Hyprpaper wallpaper manager" // {
        default = true;
      };
      hyprlock = lib.mkEnableOption "Hyprlock screen locker" // {
        default = true;
      };
      hypridle = lib.mkEnableOption "Hypridle idle daemon" // {
        default = true;
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.wev pkgs.wtype ]";
      description = "Additional packages to include in the desktop environment";
    };
  };

  config = lib.mkIf cfg.enable {
    # Essential Hyprland packages that cannot be excluded
    home.packages =
      with pkgs;
      [
        # Terminal emulator
        ghostty

        # Essential Hyprland utilities
        hyprshot # Screenshot tool
        hyprpicker # Color picker
        hyprsunset # Blue light filter
        brightnessctl # Brightness control
        pamixer # Volume control
        playerctl # Media player control
        gnome-themes-extra # GTK themes
        pavucontrol # PulseAudio/PipeWire volume control
        wl-clipboard # Wayland clipboard utilities
        glib # GLib library

        # User-specified extra packages
      ]
      ++ cfg.extraPackages;

    # Enable uwsm integration for Hyprland session management
    # This is configured through the NixOS module with programs.hyprland.withUWSM = true
  };
}
