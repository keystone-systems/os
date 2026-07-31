{
  config,
  lib,
  pkgs,
  keystoneInputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  themeCfg = config.keystone.desktop.theme;
  # Single source of truth for polkit.json generation. Both the
  # home.activation script below and keystone-theme-switch invoke this
  # binary; the dev smoke test (bin/dev/test-polkit-theme.sh) runs it
  # too, so what the test exercises is byte-for-byte what production
  # ships.
  writePolkitThemeBin = "${pkgs.keystone.write-polkit-theme}/bin/keystone-write-polkit-theme";

  # List of theme files to copy from omarchy (excluding ghostty.conf - we generate our own)
  themeFilesToCopy = [
    "hyprland.conf"
    "hyprlock.conf"
    "waybar.css"
    "mako.ini"
    "wofi.css"
    "btop.theme"
    "swayosd.css"
    "walker.css"
    "chromium.theme"
    "icons.theme"
    "light.mode"
    "preview.png"
  ];

  # Map keystone theme names to correct ghostty theme names
  ghosttyThemeMap = {
    "tokyo-night" = "TokyoNight Night";
    "kanagawa" = "Kanagawa Wave";
    "catppuccin" = "Catppuccin Mocha";
    "catppuccin-latte" = "Catppuccin Latte";
    "everforest" = "Everforest Dark Hard";
    "gruvbox" = "Gruvbox Dark";
    "nord" = "Nord";
    "rose-pine" = "Rose Pine";
    "flexoki-light" = "Flexoki Light";
    "ristretto" = "Monokai Pro Ristretto";
    "ethereal" = "Builtin Dark";
    "hackerman" = "Builtin Dark";
    "matte-black" = "Matte Black";
    "osaka-jade" = "Builtin Dark";
    # Custom themes use their own ghostty.conf, this is just a fallback
    "royal-green" = "Builtin Dark";
  };

  # Map keystone theme names to helix theme names
  helixThemeMap = {
    "tokyo-night" = "tokyonight";
    "kanagawa" = "kanagawa";
    "catppuccin" = "catppuccin_mocha";
    "catppuccin-latte" = "catppuccin_latte";
    "everforest" = "everforest_dark";
    "gruvbox" = "gruvbox";
    "nord" = "nord";
    "rose-pine" = "rose_pine";
    "flexoki-light" = "fleet_dark";
    "ristretto" = "monokai_pro_ristretto";
    "ethereal" = "base16_default_dark";
    "hackerman" = "base16_default_dark";
    "matte-black" = "base16_default_dark";
    "osaka-jade" = "kinda_nvim";
    "royal-green" = "royal_green";
  };

  # Map keystone theme names to zellij built-in theme names
  zellijThemeMap = {
    "tokyo-night" = "tokyo-night-dark";
    "kanagawa" = "kanagawa";
    "catppuccin" = "catppuccin-mocha";
    "catppuccin-latte" = "catppuccin-latte";
    "everforest" = "everforest-dark";
    "gruvbox" = "gruvbox-dark";
    "nord" = "nord";
    "rose-pine" = "rose-pine";
    "flexoki-light" = "solarized-light";
    "ristretto" = "molokai-dark";
    "ethereal" = "nightfox";
    "hackerman" = "nightfox";
    "matte-black" = "nightfox";
    "osaka-jade" = "nightfox";
    # Custom themes use their own zellij.kdl
    "royal-green" = "royal-green";
  };

  # Path to local custom themes
  customThemesPath = ./themes;

  # Get list of themes from omarchy
  omarchyThemesPath = "${keystoneInputs.omarchy}/themes";

  # Theme directories available in omarchy
  omarchyThemes = [
    "tokyo-night"
    "kanagawa"
    "catppuccin"
    "catppuccin-latte"
    "ethereal"
    "everforest"
    "flexoki-light"
    "gruvbox"
    "hackerman"
    "matte-black"
    "nord"
    "osaka-jade"
    "ristretto"
    "rose-pine"
  ];

  # Custom local themes
  customThemes = [
    "royal-green"
  ];

  # All available themes
  availableThemes = omarchyThemes ++ customThemes;

  # Function to create theme files for an omarchy theme
  mkOmarchyThemeFiles =
    themeName:
    let
      sourceThemePath = "${omarchyThemesPath}/${themeName}";
      destThemePath = "${config.xdg.configHome}/keystone/themes/${themeName}";
      ghosttyTheme = ghosttyThemeMap.${themeName} or "Builtin Dark";
      helixTheme = helixThemeMap.${themeName} or "base16_default_dark";
      zellijTheme = zellijThemeMap.${themeName} or "tokyo-night-dark";
    in
    # Copy individual theme files
    listToAttrs (
      map (
        fileName:
        nameValuePair "${destThemePath}/${fileName}" { source = "${sourceThemePath}/${fileName}"; }
      ) (filter (fileName: pathExists "${sourceThemePath}/${fileName}") themeFilesToCopy)
    )
    # Generate ghostty.conf with correct theme name
    // {
      "${destThemePath}/ghostty.conf".text = "theme = ${ghosttyTheme}\n";
    }
    # Generate helix.conf with correct theme name
    // {
      "${destThemePath}/helix.conf".text = "theme = \"${helixTheme}\"\n";
    }
    # Generate zellij.conf with correct theme name (references built-in zellij themes)
    // {
      "${destThemePath}/zellij.conf".text = "theme \"${zellijTheme}\"\n";
    }
    # Copy backgrounds directory if it exists
    // (
      if pathExists "${sourceThemePath}/backgrounds" then
        {
          "${destThemePath}/backgrounds".source = "${sourceThemePath}/backgrounds";
        }
      else
        { }
    );

  # Files to copy for custom themes (includes ghostty.conf and zellij.kdl since custom themes provide their own)
  customThemeFilesToCopy = themeFilesToCopy ++ [
    "ghostty.conf"
    "helix.toml"
    "zellij.kdl"
    "lazygit.yml"
  ];

  # Function to create theme files for a custom local theme
  mkCustomThemeFiles =
    themeName:
    let
      sourceThemePath = "${customThemesPath}/${themeName}";
      destThemePath = "${config.xdg.configHome}/keystone/themes/${themeName}";
      helixTheme = helixThemeMap.${themeName} or "base16_default_dark";
      zellijTheme = zellijThemeMap.${themeName} or "tokyo-night-dark";
    in
    # Copy individual theme files from local custom themes directory
    listToAttrs (
      map (
        fileName:
        nameValuePair "${destThemePath}/${fileName}" { source = "${sourceThemePath}/${fileName}"; }
      ) (filter (fileName: pathExists "${sourceThemePath}/${fileName}") customThemeFilesToCopy)
    )
    # Generate helix.conf with correct theme name
    // {
      "${destThemePath}/helix.conf".text = "theme = \"${helixTheme}\"\n";
    }
    # Generate zellij.conf with correct theme name
    // {
      "${destThemePath}/zellij.conf".text = "theme \"${zellijTheme}\"\n";
    }
    # Copy helix.toml to helix themes directory for custom themes
    // (
      if pathExists "${sourceThemePath}/helix.toml" then
        {
          "${config.xdg.configHome}/helix/themes/${helixTheme}.toml".source = "${sourceThemePath}/helix.toml";
        }
      else
        { }
    )
    # Copy zellij.kdl to zellij themes directory for custom themes
    // (
      if pathExists "${sourceThemePath}/zellij.kdl" then
        {
          "${config.xdg.configHome}/zellij/themes/${zellijTheme}.kdl".source =
            "${sourceThemePath}/zellij.kdl";
        }
      else
        { }
    )
    # Use osaka-jade backgrounds from omarchy for royal-green
    // (
      if themeName == "royal-green" then
        {
          "${destThemePath}/backgrounds".source = "${omarchyThemesPath}/osaka-jade/backgrounds";
        }
      else
        { }
    );

  # Theme switch script
  keystoneThemeSwitch = pkgs.writeShellScriptBin "keystone-theme-switch" ''
    THEMES_DIR="${config.xdg.configHome}/keystone/themes"
    CURRENT_LINK="${config.xdg.configHome}/keystone/current"

    if [[ $# -eq 0 ]]; then
      echo "Available themes:"
      for theme in "$THEMES_DIR"/*/; do
        theme_name=$(basename "$theme")
        if [[ -L "$CURRENT_LINK/theme" ]] && [[ "$(readlink -f "$CURRENT_LINK/theme")" == "$(readlink -f "$theme")" ]]; then
          echo "  * $theme_name (active)"
        else
          echo "    $theme_name"
        fi
      done
      echo ""
      echo "Usage: keystone-theme-switch <theme-name>"
      exit 0
    fi

    THEME_NAME="$1"
    THEME_PATH="$THEMES_DIR/$THEME_NAME"

    if [[ ! -d "$THEME_PATH" ]]; then
      echo "Error: Theme '$THEME_NAME' not found in $THEMES_DIR"
      exit 1
    fi

    # Create current directory if it doesn't exist
    mkdir -p "$CURRENT_LINK"

    # Update theme symlink
    ln -sfn "$THEME_PATH" "$CURRENT_LINK/theme"

    # Update current polkit theme config
    ${writePolkitThemeBin} "$THEME_PATH" "$CURRENT_LINK/polkit.json"

    # Set background if available
    if [[ -d "$THEME_PATH/backgrounds" ]]; then
      # Use first background if not specifically set
      FIRST_BG=$(ls "$THEME_PATH/backgrounds/" | head -1)
      if [[ -n "$FIRST_BG" ]]; then
        ln -sfn "$THEME_PATH/backgrounds/$FIRST_BG" "$CURRENT_LINK/background"
      fi
    fi

    echo "Switched to theme: $THEME_NAME"

    # Restart hyprpaper to pick up new background
    ${pkgs.systemd}/bin/systemctl --user restart hyprpaper.service 2>/dev/null || true

    # Reload components.
    # waybar.service is the canonical start path (programs.waybar.systemd.enable
    # in components/waybar.nix). The unit's ExecReload sends SIGUSR2 to the
    # MAINPID, reloading config + CSS in place with no process restart and no
    # second-instance spawn risk.
    ${pkgs.systemd}/bin/systemctl --user reload waybar.service 2>/dev/null || true
    ${pkgs.procps}/bin/pkill -SIGUSR2 ghostty 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user restart mako.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user restart walker.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user restart hyprpolkitagent.service 2>/dev/null || true

    # Set Chromium theme color
    if [[ -f "$THEME_PATH/chromium.theme" ]] && command -v chromium &>/dev/null; then
      chromium --no-startup-window --set-theme-color="$(<"$THEME_PATH/chromium.theme")" 2>/dev/null || true
    fi

    # Set GTK/GNOME color scheme based on light.mode file
    if [[ -f "$THEME_PATH/light.mode" ]]; then
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
    else
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
    fi

    # Set icon theme if available
    if [[ -f "$THEME_PATH/icons.theme" ]]; then
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme "$(<"$THEME_PATH/icons.theme")"
    fi

    # Update zellij theme symlink
    if [[ -f "$THEME_PATH/zellij.kdl" ]]; then
      mkdir -p "${config.xdg.configHome}/zellij/themes"
      ln -sfn "$THEME_PATH/zellij.kdl" "${config.xdg.configHome}/zellij/themes/current.kdl"
    fi

    # Update lazygit theme symlink
    if [[ -f "$THEME_PATH/lazygit.yml" ]]; then
      mkdir -p "${config.xdg.configHome}/lazygit"
      ln -sfn "$THEME_PATH/lazygit.yml" "${config.xdg.configHome}/lazygit/config.yml"
    fi

    # Reload hyprland to pick up theme changes
    ${pkgs.hyprland}/bin/hyprctl reload 2>/dev/null || true

    ${pkgs.libnotify}/bin/notify-send "Theme Changed" "Switched to $THEME_NAME theme" -t 3000
  '';
  # Light themes (have light.mode file in omarchy)
  lightThemes = [
    "flexoki-light"
    "catppuccin-latte"
    "rose-pine"
  ];
  isLightTheme = builtins.elem themeCfg.name lightThemes;
in
{
  options.keystone.desktop.theme = {
    name = mkOption {
      type = types.str;
      default = "tokyo-night";
      description = "Active theme name";
    };
  };

  config = mkIf cfg.enable {
    # Deploy all theme files from omarchy and custom themes
    # Also deploy omarchy default mako core.ini since theme mako.ini files include it
    home.file = mkMerge (
      (map mkOmarchyThemeFiles omarchyThemes)
      ++ (map mkCustomThemeFiles customThemes)
      ++ [
        {
          ".local/share/omarchy/default/mako/core.ini".source =
            "${keystoneInputs.omarchy}/default/mako/core.ini";
        }
      ]
    );

    # Theme switching script
    home.packages = [
      keystoneThemeSwitch
    ];

    # GTK theme configuration
    gtk = {
      enable = true;
      theme = {
        name = if isLightTheme then "Adwaita" else "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
      };
    };

    # Set GNOME/GTK color scheme via dconf
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = if isLightTheme then "prefer-light" else "prefer-dark";
        gtk-theme = if isLightTheme then "Adwaita" else "Adwaita-dark";
      };
    };

    # Create activation script to setup symlinks and mutable configs
    # Run after writeBoundary so files are deployed, but handle conflicts gracefully
    home.activation.keystoneThemeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      KEYSTONE_DIR="${config.xdg.configHome}/keystone"
      CURRENT_DIR="$KEYSTONE_DIR/current"
      THEME_DIR="$KEYSTONE_DIR/themes/${themeCfg.name}"

      # Create directories
      mkdir -p "$CURRENT_DIR"

      # Create theme symlink only if not exists (preserve user's runtime selection)
      if [[ ! -L "$CURRENT_DIR/theme" ]]; then
        ln -sfn "$THEME_DIR" "$CURRENT_DIR/theme"
        echo "Keystone: Set initial theme to ${themeCfg.name}"
      fi

      ${writePolkitThemeBin} "$CURRENT_DIR/theme" "$CURRENT_DIR/polkit.json"
      echo "Keystone: Wrote polkit theme"

      # Create default background symlink if not exists and theme has backgrounds
      if [[ ! -L "$CURRENT_DIR/background" ]] && [[ -d "$THEME_DIR/backgrounds" ]]; then
        FIRST_BG=$(ls "$THEME_DIR/backgrounds/" 2>/dev/null | head -1)
        if [[ -n "$FIRST_BG" ]]; then
          ln -sfn "$THEME_DIR/backgrounds/$FIRST_BG" "$CURRENT_DIR/background"
          echo "Keystone: Set default background from ${themeCfg.name} theme"
        fi
      fi

      # Create mako config directory and symlink
      mkdir -p "${config.xdg.configHome}/mako"
      if [[ -f "$THEME_DIR/mako.ini" ]]; then
        ln -sfn "$CURRENT_DIR/theme/mako.ini" "${config.xdg.configHome}/mako/config"
        echo "Keystone: Linked mako config"
      fi

      # Create zellij theme symlink
      mkdir -p "${config.xdg.configHome}/zellij/themes"
      if [[ -f "$THEME_DIR/zellij.kdl" ]]; then
        ln -sfn "$CURRENT_DIR/theme/zellij.kdl" "${config.xdg.configHome}/zellij/themes/current.kdl"
        echo "Keystone: Linked zellij theme"
      fi

      # Create lazygit theme symlink
      mkdir -p "${config.xdg.configHome}/lazygit"
      if [[ -f "$THEME_DIR/lazygit.yml" ]]; then
        ln -sfn "$CURRENT_DIR/theme/lazygit.yml" "${config.xdg.configHome}/lazygit/config.yml"
        echo "Keystone: Linked lazygit theme"
      fi
    '';
  };
}
