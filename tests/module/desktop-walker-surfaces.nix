# Red/green gate for GitHub issue #390 — gate Walker surfaces and repair
# setup, update, and wifi flows. Each assertion below encodes a requirement
# from engineering issue #391 (ISSUE-REQ-1..8). These tests MUST fail on main
# and pass once all fixes land.
{ pkgs }:
pkgs.runCommand "test-desktop-walker-surfaces"
  {
    nativeBuildInputs = with pkgs; [ gnugrep ];
  }
  ''
    set -euo pipefail

    repo="${../..}"
    scripts="$repo/modules/desktop/home/scripts"
    bindings="$repo/modules/desktop/home/hyprland/bindings.nix"
    waybar="$repo/modules/desktop/home/components/waybar.nix"
    default_nix="$scripts/default.nix"
    main_menu="$scripts/keystone-main-menu.sh"
    setup_menu="$scripts/keystone-setup-menu.sh"

    fail() {
      echo "FAIL: $1" >&2
      exit 1
    }

    # ISSUE-REQ-2: $mod+Escape must default to the System menu.
    if ! grep -F '"$mod, Escape, exec, keystone-menu system"' "$bindings" >/dev/null; then
      fail "ISSUE-REQ-2: \$mod+Escape bind must be 'keystone-menu system' (was 'keystone-menu')"
    fi

    # ISSUE-REQ-8: Waybar network click must open the Keystone Wi-Fi flow, not nm-connection-editor.
    if grep -F 'on-click = "nm-connection-editor"' "$waybar" >/dev/null; then
      fail "ISSUE-REQ-8: waybar network on-click must not be 'nm-connection-editor'"
    fi
    if ! grep -E 'on-click = "keystone-wifi-menu' "$waybar" >/dev/null; then
      fail "ISSUE-REQ-8: waybar network on-click must invoke 'keystone-wifi-menu'"
    fi

    # ISSUE-REQ-6: Update entry must not be the blocked 'Use nix flake update' placeholder.
    if grep -F 'Use nix flake update for system updates.' "$main_menu" >/dev/null; then
      fail "ISSUE-REQ-6: Update entry must not remain a blocked 'Use nix flake update' placeholder"
    fi

    # ISSUE-REQ-7: Wifi entry must not be the blocked 'not implemented yet' placeholder.
    if grep -F 'Wifi setup is not implemented yet.' "$setup_menu" >/dev/null; then
      fail "ISSUE-REQ-7: Wifi entry must not remain a blocked 'not implemented yet' placeholder"
    fi

    # ISSUE-REQ-7: A keystone-wifi-menu script must exist.
    if [[ ! -f "$scripts/keystone-wifi-menu.sh" ]]; then
      fail "ISSUE-REQ-7: modules/desktop/home/scripts/keystone-wifi-menu.sh must exist"
    fi

    # ISSUE-REQ-3/4: Setup controllers MUST NOT source a sibling helper that is
    # not packaged. writeShellScriptBin places each script in its own $out/bin,
    # so a sibling keystone-desktop-config.sh path never resolves at runtime.
    #
    # keystone-update-menu.sh was removed in favour of `ks menu update` — the
    # Rust binary can't accidentally source a sibling path, so it's exempt from
    # this sweep.
    for s in \
      "$scripts/keystone-audio-menu.sh" \
      "$scripts/keystone-monitor-menu.sh" \
      "$scripts/keystone-printer-menu.sh" \
      "$scripts/keystone-package-menu.sh"; do
      if grep -F 'source "''${SCRIPT_DIR}/keystone-desktop-config.sh"' "$s" >/dev/null; then
        fail "ISSUE-REQ-3/4: $(basename "$s") must not source a sibling keystone-desktop-config.sh — helper must be packaged"
      fi
    done

    # ISSUE-REQ-5: Fingerprint menu runtime inputs must include fprintd.
    if ! grep -E 'pkgs\.fprintd' "$default_nix" >/dev/null; then
      fail "ISSUE-REQ-5: default.nix must include pkgs.fprintd in keystoneFingerprintMenu runtimeInputs"
    fi

    # ISSUE-REQ-1: Top-level menu entries must be gated by capability env vars
    # wired from the Nix module.
    if ! grep -E 'KEYSTONE_MENU_SHOW_(PHOTOS|AGENTS|CONTEXTS)' "$main_menu" >/dev/null; then
      fail "ISSUE-REQ-1: keystone-main-menu.sh must gate Photos/Agents/Contexts entries via KEYSTONE_MENU_SHOW_* env vars"
    fi

    touch "$out"
  ''
