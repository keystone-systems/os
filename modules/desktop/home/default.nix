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
  imports = [
    ../../shared/experimental.nix
    ../../shared/update.nix
    ./components
    ./hyprland
    ./scripts
    ./services.nix
    ./theming
    # Terminal is provided by nixosModules.operating-system via
    # home-manager.sharedModules since 2a9c266. Do not re-import here
    # to avoid duplicate option declarations when both OS and desktop
    # modules are active.
  ];

  options.keystone.desktop = {
    enable = mkEnableOption "Keystone Desktop - Core desktop packages and utilities for Home Manager";

    browser = mkOption {
      type = types.str;
      default = "chromium";
      description = "Default browser binary name. Used by the $mod+B keybinding.";
    };

    uhk = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Install the Ultimate Hacking Keyboard agent";
      };
    };

    audio = {
      defaults = {
        sink = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Default output device name to apply at desktop session start.";
        };

        source = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Default input device name to apply at desktop session start.";
        };
      };
    };

    printer = {
      default = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default CUPS printer name to apply at desktop session start.";
      };
    };

    # Top-level Walker main-menu surfaces. Each gates one hard-coded entry in
    # keystone-main-menu's main_json via KEYSTONE_MENU_SHOW_* env vars. Default
    # to keystone.experimental so only stable surfaces appear by default.
    photos.enable = mkOption {
      type = types.bool;
      default = config.keystone.experimental;
      defaultText = literalExpression "config.keystone.experimental";
      description = "Show the Photos entry in the Mod+Escape Walker main menu.";
    };

    agents.enable = mkOption {
      type = types.bool;
      default = config.keystone.experimental;
      defaultText = literalExpression "config.keystone.experimental";
      description = "Show the Agents entry in the Mod+Escape Walker main menu.";
    };

    startupLockCommand = mkOption {
      type = types.str;
      default = "keystone-startup-lock";
      description = ''
        Command to run as the first user-visible exec-once entry in Hyprland.
        Must present a lock surface or terminate the session (fail-closed).
        See convention os.hyprland-autostart.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Desktop implies terminal
    keystone.terminal.enable = true;

    # UHK Agent copies firmware docs from the Nix store into ~/.config/uhk-agent.
    # Those source files are read-only, and the app preserves that mode, which
    # breaks later updates when it tries to refresh docs for the current firmware.
    home.activation.keystoneUhkAgentCacheFix = mkIf cfg.uhk.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        uhk_cache_dir="$HOME/.config/uhk-agent/smart-macro-docs"
        if [ -d "$uhk_cache_dir" ]; then
          ${pkgs.findutils}/bin/find "$uhk_cache_dir" -type d -exec ${pkgs.coreutils}/bin/chmod u+rwx {} +
          ${pkgs.findutils}/bin/find "$uhk_cache_dir" -type f -exec ${pkgs.coreutils}/bin/chmod u+rw {} +
        fi
      ''
    );

    home.packages = [
      # Presentations
      pkgs.keystone.slidev
    ]
    ++ optionals cfg.uhk.enable [
      pkgs.uhk-agent
    ];
  };
}
