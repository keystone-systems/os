#!/usr/bin/env bash

set -euo pipefail

# Keystone Menu Keybindings - Displays Hyprland keybindings in a searchable Walker menu

declare -A KEYCODE_SYM_MAP

build_keymap_cache() {
  local keymap
  keymap="$(xkbcli compile-keymap 2>/dev/null)" || {
    return 1
  }

  while IFS=, read -r code sym; do
    [[ -z "$code" || -z "$sym" ]] && continue
    KEYCODE_SYM_MAP["$code"]="$sym"
  done < <(
    awk '
      BEGIN { sec = "" }
      /xkb_keycodes/ { sec = "codes"; next }
      /xkb_symbols/  { sec = "syms";  next }
      sec == "codes" {
        if (match($0, /<([A-Za-z0-9_]+)>\s*=\s*([0-9]+)\s*;/, m)) code_by_name[m[1]] = m[2]
      }
      sec == "syms" {
        if (match($0, /key\s*<([A-Za-z0-9_]+)>\s*\{\s*\[\s*([^, \]]+)/, m)) sym_by_name[m[1]] = m[2]
      }
      END {
        for (k in code_by_name) {
          c = code_by_name[k]
          s = sym_by_name[k]
          if (c != "" && s != "" && s != "NoSymbol") print c "," s
        }
      }
    ' <<<"$keymap"
  )
}

lookup_keycode_cached() {
  printf '%s\n' "${KEYCODE_SYM_MAP[$1]}"
}

parse_keycodes() {
  while IFS= read -r line; do
    if [[ "$line" =~ code:([0-9]+) ]]; then
      code="${BASH_REMATCH[1]}"
      symbol=$(lookup_keycode_cached "$code")
      echo "${line/code:${code}/$symbol}"
    elif [[ "$line" =~ mouse:([0-9]+) ]]; then
      code="${BASH_REMATCH[1]}"

      case "$code" in
        272) symbol="LEFT MOUSE BUTTON" ;;
        273) symbol="RIGHT MOUSE BUTTON" ;;
        274) symbol="MIDDLE MOUSE BUTTON" ;;
        *)   symbol="mouse:${code}" ;;
      esac

      echo "${line/mouse:${code}/$symbol}"
    else
      echo "$line"
    fi
  done
}

# Fetch dynamic keybindings from Hyprland
# Map numeric modifier key mask to a textual rendition
dynamic_bindings() {
  hyprctl -j binds |
    jq -r '.[] | {modmask, key, keycode, description, dispatcher, arg} | "\(.modmask),\(.key)@\(.keycode),\(.description),\(.dispatcher),\(.arg)"' |
    sed -r \
      -e 's/null//' \
      -e 's/@0//' \
      -e 's/,@/,code:/' \
      -e 's/^0,/,/' \
      -e 's/^1,/SHIFT,/' \
      -e 's/^4,/CTRL,/' \
      -e 's/^5,/SHIFT CTRL,/' \
      -e 's/^8,/ALT,/' \
      -e 's/^9,/SHIFT ALT,/' \
      -e 's/^12,/CTRL ALT,/' \
      -e 's/^13,/SHIFT CTRL ALT,/' \
      -e 's/^64,/SUPER,/' \
      -e 's/^65,/SUPER SHIFT,/' \
      -e 's/^68,/SUPER CTRL,/' \
      -e 's/^69,/SUPER SHIFT CTRL,/' \
      -e 's/^72,/SUPER ALT,/' \
      -e 's/^73,/SUPER SHIFT ALT,/' \
      -e 's/^76,/SUPER CTRL ALT,/' \
      -e 's/^77,/SUPER SHIFT CTRL ALT,/'
}

# Parse and format keybindings
parse_bindings() {
  awk -F, '
{
    # Combine the modifier and key (first two fields)
    key_combo = $1 " + " $2;

    # Clean up: strip leading "+" if present, trim spaces
    gsub(/^[ \t]*\+?[ \t]*/, "", key_combo);
    gsub(/[ \t]+$/, "", key_combo);

    # Use description, if set
    action = $3;

    if (action == "") {
        # Reconstruct the command from the remaining fields
        for (i = 4; i <= NF; i++) {
            action = action $i (i < NF ? "," : "");
        }

        # Clean up trailing commas, remove leading "exec, ", and trim
        sub(/,$/, "", action);
        gsub(/(^|,)[[:space:]]*exec[[:space:]]*,?/, "", action);
        gsub(/^[ \t]+|[ \t]+$/, "", action);
        gsub(/[ \t]+/, " ", key_combo);  # Collapse multiple spaces to one

        # Escape XML entities
        gsub(/&/, "\\&amp;", action);
        gsub(/</, "\\&lt;", action);
        gsub(/>/, "\\&gt;", action);
        gsub(/"/, "\\&quot;", action);
        gsub(/'"'"'/, "\\&apos;", action);
    }

    if (action != "") {
        printf "%-35s → %s\n", key_combo, action;
    }
}'
}

static_bindings() {
  cat <<'EOF'
Ctrl + , / Ctrl + PageUp          → Terminal: Previous zellij tab
Ctrl + . / Ctrl + PageDown        → Terminal: Next zellij tab
Ctrl + <                           → Terminal: Move zellij tab left
Ctrl + >                           → Terminal: Move zellij tab right
Ctrl + T                           → Terminal: New zellij tab
Ctrl + W                           → Terminal: Close zellij tab
EOF
}

prioritize_entries() {
  awk '
  {
    line = $0
    prio = 50
    if (match(line, /Terminal/)) prio = 0
    if (match(line, /Browser/) && !match(line, /Browser[[:space:]]*\(/)) prio = 1
    if (match(line, /File manager/))  prio = 2
    if (match(line, /Launch apps/))  prio = 3
    if (match(line, /menu/))  prio = 4
    if (match(line, /Full screen/))  prio = 7
    if (match(line, /Close window/))  prio = 8
    if (match(line, /killactive/))  prio = 8
    if (match(line, /Toggle.*floating/))  prio = 9
    if (match(line, /togglefloating/))  prio = 9
    if (match(line, /Toggle.*split/))  prio = 10
    if (match(line, /Clipboard/))  prio = 12
    if (match(line, /Screenshot/))  prio = 15
    if (match(line, /Screenrecord/))  prio = 16
    if (match(line, /(Switch|Next|Former|Previous).*workspace/))  prio = 17
    if (match(line, /Move.*to.*workspace/))  prio = 18
    if (match(line, /movetoworkspace/))  prio = 18
    if (match(line, /Swap window/))  prio = 19
    if (match(line, /Move.*focus/))  prio = 20
    if (match(line, /movefocus/))  prio = 20
    if (match(line, /Move window$/))  prio = 21
    if (match(line, /Resize window/))  prio = 22
    if (match(line, /scratchpad/))  prio = 25
    if (match(line, /special/))  prio = 25
    if (match(line, /nightlight/))  prio = 29
    if (match(line, /XF86/))  prio = 99

    # print "priority<TAB>line"
    printf "%d\t%s\n", prio, line
  }' |
  sort -k1,1n -k2,2 |
  cut -f2-
}

monitor_height=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .height')
menu_height=$((monitor_height * 40 / 100))

build_keymap_cache

{
  static_bindings
  dynamic_bindings |
    sort -u |
    parse_keycodes |
    parse_bindings
} |
  prioritize_entries |
  walker --dmenu -p 'Keybindings' --width 800 --height "$menu_height"
