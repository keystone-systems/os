{
  config,
  lib,
  pkgs,
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

  # Theme switch script
  keystoneThemeSwitch = pkgs.writeShellScriptBin "keystone-theme-switch" ''
    THEMES_DIR="${config.xdg.configHome}/themes"
    CURRENT_THEME="$THEMES_DIR/current"
    RUNTIME_DIR="${config.xdg.configHome}/keystone/current"

    if [[ $# -eq 0 ]]; then
      echo "Available themes:"
      for theme in "$THEMES_DIR"/*/; do
        theme_name=$(basename "$theme")
        if [[ -L "$CURRENT_THEME" ]] && [[ "$(readlink -f "$CURRENT_THEME")" == "$(readlink -f "$theme")" ]]; then
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

    mkdir -p "$RUNTIME_DIR"

    # Update theme symlink
    ln -sfn "$THEME_PATH" "$CURRENT_THEME"

    # Update current polkit theme config
    ${writePolkitThemeBin} "$THEME_PATH" "$RUNTIME_DIR/polkit.json"

    # Set background if available
    if [[ -d "$THEME_PATH/backgrounds" ]]; then
      # Use first background if not specifically set
      FIRST_BG=$(ls "$THEME_PATH/backgrounds/" | head -1)
      if [[ -n "$FIRST_BG" ]]; then
        ln -sfn "$THEME_PATH/backgrounds/$FIRST_BG" "$RUNTIME_DIR/background"
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
      THEMES_DIR="${config.xdg.configHome}/themes"
      CURRENT_THEME="$THEMES_DIR/current"
      RUNTIME_DIR="${config.xdg.configHome}/keystone/current"
      THEME_DIR="$THEMES_DIR/${themeCfg.name}"

      # Create directories
      mkdir -p "$RUNTIME_DIR"

      # Create theme symlink only if not exists (preserve user's runtime selection)
      if [[ ! -L "$CURRENT_THEME" ]]; then
        ln -sfn "$THEME_DIR" "$CURRENT_THEME"
        echo "Keystone: Set initial theme to ${themeCfg.name}"
      fi

      ${writePolkitThemeBin} "$CURRENT_THEME" "$RUNTIME_DIR/polkit.json"
      echo "Keystone: Wrote polkit theme"

      # Create default background symlink if not exists and theme has backgrounds
      if [[ ! -L "$RUNTIME_DIR/background" ]] && [[ -d "$THEME_DIR/backgrounds" ]]; then
        FIRST_BG=$(ls "$THEME_DIR/backgrounds/" 2>/dev/null | head -1)
        if [[ -n "$FIRST_BG" ]]; then
          ln -sfn "$THEME_DIR/backgrounds/$FIRST_BG" "$RUNTIME_DIR/background"
          echo "Keystone: Set default background from ${themeCfg.name} theme"
        fi
      fi

      # Create mako config directory and symlink
      mkdir -p "${config.xdg.configHome}/mako"
      if [[ -f "$THEME_DIR/mako.ini" ]]; then
        ln -sfn "$CURRENT_THEME/mako.ini" "${config.xdg.configHome}/mako/config"
        echo "Keystone: Linked mako config"
      fi

      # Create zellij theme symlink
      mkdir -p "${config.xdg.configHome}/zellij/themes"
      if [[ -f "$THEME_DIR/zellij.kdl" ]]; then
        ln -sfn "$CURRENT_THEME/zellij.kdl" "${config.xdg.configHome}/zellij/themes/current.kdl"
        echo "Keystone: Linked zellij theme"
      fi

      # Create lazygit theme symlink
      mkdir -p "${config.xdg.configHome}/lazygit"
      if [[ -f "$THEME_DIR/lazygit.yml" ]]; then
        ln -sfn "$CURRENT_THEME/lazygit.yml" "${config.xdg.configHome}/lazygit/config.yml"
        echo "Keystone: Linked lazygit theme"
      fi
    '';
  };
}
