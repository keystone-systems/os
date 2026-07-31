{
  writeShellApplication,
  jq,
}:
# Single source of truth for the keystone polkit-theme JSON generator.
# Both production (modules/desktop/home/theming/default.nix — the home.activation
# script and the keystone-theme-switch wrapper) and the dev smoke test
# (bin/dev/test-polkit-theme.sh) call this binary, so the smoke test exercises
# the same logic that ships.
writeShellApplication {
  name = "keystone-write-polkit-theme";
  runtimeInputs = [ jq ];
  text = ''
    if [[ $# -ne 2 ]]; then
      echo "Usage: keystone-write-polkit-theme <theme-path> <output-path>" >&2
      exit 2
    fi

    theme_path="$1"
    output_path="$2"
    hyprlock_file="$theme_path/hyprlock.conf"
    waybar_file="$theme_path/waybar.css"
    is_light=false

    read_hyprlock_color() {
      local name="$1"
      if [[ -f "$hyprlock_file" ]]; then
        # Match rgb(...) or rgba(...) — keystone-internal themes
        # (royal-green) use rgb; omarchy themes use rgba.
        sed -n 's/^\$'"$name"' = \(rgba\{0,1\}([^)]*)\).*/\1/p' "$hyprlock_file" | head -1
      fi
    }

    read_waybar_color() {
      local name="$1"
      if [[ -f "$waybar_file" ]]; then
        # Stop at the first space OR `;` — catppuccin-latte writes
        # `@define-color background #eff1f5 /* base */;` (comment
        # before the semicolon), and naive `[^;]*` would capture the
        # comment as part of the colour value, polluting polkit.json.
        sed -n 's/^@define-color '"$name"' \([^ ;]*\).*/\1/p' "$waybar_file" | head -1
      fi
    }

    # Normalise to #RRGGBB. The QML in packages/hyprpolkitagent/main.qml
    # binds the values from polkit.json straight into Qt color properties
    # (`color: theme.text`, etc.). Qt's QColor parser accepts `#RRGGBB`
    # and named colours but does NOT accept CSS-style `rgb(r, g, b)` /
    # `rgba(r, g, b, a)` strings — when parsing fails, the bound colour
    # is invalid and Qt renders it as black. Hyprlock files use
    # `rgb(...)` (royal-green) or `rgba(...)` (omarchy themes), so
    # passing those through verbatim made every hyprlock-sourced colour
    # paint as black: gold border invisible against dark green, gold
    # text rendered black, etc. Convert to hex once on the way out.
    to_hex() {
      local val="$1"
      [[ -z "$val" ]] && return 0
      if [[ "$val" =~ ^rgba?\(([[:space:]]*[0-9]+)[[:space:]]*,([[:space:]]*[0-9]+)[[:space:]]*,([[:space:]]*[0-9]+)([[:space:]]*,.*)?\)$ ]]; then
        printf '#%02X%02X%02X' \
          "$(( BASH_REMATCH[1] ))" \
          "$(( BASH_REMATCH[2] ))" \
          "$(( BASH_REMATCH[3] ))"
        return 0
      fi
      printf '%s' "$val"
    }

    if [[ -f "$theme_path/light.mode" ]]; then
      is_light=true
    fi

    # Prefer waybar's @define-color background over hyprlock's $color.
    # Hyprlock is tuned for a full-screen lock and is the darkest variant of
    # a theme (royal-green hyprlock = rgb(0,18,12) ≈ near-black; waybar =
    # #001F14, visibly green). The polkit dialog is a panel-ish surface, so
    # waybar's brightness is a closer fit.
    background="$(read_waybar_color background)"
    [[ -n "$background" ]] || background="$(read_hyprlock_color color)"
    [[ -n "$background" ]] || background="#111827"

    surface="$background"

    border="$(read_hyprlock_color outer_color)"
    [[ -n "$border" ]] || border="$(read_waybar_color gold)"
    [[ -n "$border" ]] || border="#334155"

    accent="$border"

    # Hyprlock's $font_color is the password-prompt text colour — the polkit
    # dialog is semantically the same kind of surface (small auth modal), so
    # its text colour should match. Waybar's @foreground is tuned for panel
    # text, which on themes like royal-green is silvery while the lock prompt
    # is gold — preferring waybar there makes the polkit dialog read off-theme.
    text="$(read_hyprlock_color font_color)"
    [[ -n "$text" ]] || text="$(read_waybar_color foreground)"
    [[ -n "$text" ]] || text="#e5e7eb"

    placeholder="$(read_hyprlock_color placeholder_color)"
    [[ -n "$placeholder" ]] || placeholder="$text"

    muted_text="$placeholder"

    if [[ "$is_light" == true ]]; then
      error="#b42318"
    else
      error="#fb7185"
    fi

    background="$(to_hex "$background")"
    surface="$(to_hex "$surface")"
    border="$(to_hex "$border")"
    accent="$(to_hex "$accent")"
    text="$(to_hex "$text")"
    placeholder="$(to_hex "$placeholder")"
    muted_text="$(to_hex "$muted_text")"
    error="$(to_hex "$error")"

    mkdir -p "$(dirname "$output_path")"
    jq -n \
      --arg background "$background" \
      --arg surface "$surface" \
      --arg border "$border" \
      --arg accent "$accent" \
      --arg text "$text" \
      --arg mutedText "$muted_text" \
      --arg placeholder "$placeholder" \
      --arg error "$error" \
      --argjson light "$is_light" \
      '{
        background: $background,
        surface: $surface,
        border: $border,
        accent: $accent,
        text: $text,
        mutedText: $mutedText,
        placeholder: $placeholder,
        error: $error,
        light: $light
      }' > "$output_path"
  '';
}
