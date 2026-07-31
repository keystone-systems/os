{
  pkgs,
  lib,
  self,
  home-manager,
}:
let
  evalDesktop =
    extraModules:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.terminal
        self.homeModules.desktop
        {
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";

          programs.ssh.enableDefaultConfig = false;

          keystone.terminal = {
            enable = true;
            git = {
              userName = "Test User";
              userEmail = "test@test";
            };
          };

          keystone.desktop.enable = true;
          wayland.windowManager.hyprland.enable = true;
        }
      ]
      ++ extraModules;
    }).config;

  desktopConfig = evalDesktop [ ];
  hyprlandConf = desktopConfig.xdg.configFile."hypr/hyprland.conf".source;
  hypridleConf = desktopConfig.xdg.configFile."hypr/hypridle.conf".source;
  hyprlockConf = desktopConfig.xdg.configFile."hypr/hyprlock.conf".source;
  hyprpaperConf = desktopConfig.xdg.configFile."hypr/hyprpaper.conf".source;
  hyprlandPkg = desktopConfig.wayland.windowManager.hyprland.package;
  startupLockScript = ../../modules/desktop/home/scripts/keystone-startup-lock.sh;
in
pkgs.runCommand "hyprland-config-smoke"
  {
    nativeBuildInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    set -euo pipefail

    input_field_block="$(sed -n '/^input-field {/,/^}/p' "${hyprlockConf}")"

    assert_contains() {
      local file="$1"
      local needle="$2"
      local description="$3"

      if grep -F "$needle" "$file" >/dev/null; then
        echo "PASS: $description"
      else
        echo "FAIL: $description" >&2
        echo "missing: $needle" >&2
        exit 1
      fi
    }

    assert_not_contains() {
      local file="$1"
      local needle="$2"
      local description="$3"

      if grep -F "$needle" "$file" >/dev/null; then
        echo "FAIL: $description" >&2
        echo "unexpected: $needle" >&2
        exit 1
      else
        echo "PASS: $description"
      fi
    }

    assert_contains "${hyprpaperConf}" "preload=/home/testuser/.config/keystone/current/background" \
      "hyprpaper preloads the theme background before assigning wallpaper"
    assert_contains "${hyprpaperConf}" "monitor=*" \
      "hyprpaper wallpaper block targets all monitors with wildcard"
    assert_contains "${hyprpaperConf}" "path=/home/testuser/.config/keystone/current/background" \
      "hyprpaper wallpaper block points at the theme background"

    assert_contains "${hypridleConf}" "lock_cmd=pidof hyprlock || hyprlock" \
      "hypridle lock command invokes hyprlock"
    assert_contains "${hypridleConf}" "before_sleep_cmd=pidof hyprlock || hyprlock" \
      "hypridle locks before suspend"
    assert_contains "${hypridleConf}" "on-timeout=pidof hyprlock || hyprlock" \
      "hypridle timeout triggers lock"
    assert_not_contains "${hypridleConf}" "immediate-render" \
      "hypridle does not use --immediate-render (causes blank lock screen)"

    assert_contains "${hyprlandConf}" "switch:on:Lid Switch, exec, pidof hyprlock || hyprlock; systemctl suspend" \
      "lid-close binding locks and suspends"
    assert_contains "${startupLockScript}" "hyprlock_cmd=(hyprlock)" \
      "startup lock wrapper launches hyprlock without --immediate-render"

    assert_contains "${hyprlockConf}" "source=" \
      "hyprlock sources theme colors from theme hyprlock.conf"
    assert_contains "${hyprlockConf}" "disable_loading_bar" \
      "hyprlock general section is present"
    assert_contains "${hyprlockConf}" "inner_color=\$inner_color" \
      "hyprlock uses theme variable for inner_color"
    assert_contains "${hyprlockConf}" "font_color=\$font_color" \
      "hyprlock uses theme variable for font_color"
    assert_contains "${hyprlockConf}" "placeholder_color=\$placeholder_color" \
      "hyprlock uses theme variable for placeholder_color"
    if printf '%s\n' "$input_field_block" | grep -F "font_size" >/dev/null; then
      echo "PASS: hyprlock input-field includes font_size"
    else
      echo "FAIL: hyprlock input-field missing font_size" >&2
      exit 1
    fi

    export HOME="$PWD/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    mkdir -p "$XDG_CONFIG_HOME/keystone/current/theme" "$XDG_RUNTIME_DIR"
    : > "$XDG_CONFIG_HOME/keystone/current/theme/hyprland.conf"

    "${hyprlandPkg}/bin/Hyprland" --verify-config -c "${hyprlandConf}" >"$PWD/hyprland-verify.log" 2>&1
    assert_contains "$PWD/hyprland-verify.log" "config ok" \
      "Hyprland verifies the rendered desktop config successfully"

    touch "$out"
  ''
