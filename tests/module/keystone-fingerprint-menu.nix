{
  pkgs,
  lib,
}:
pkgs.runCommand "test-keystone-fingerprint-menu"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      jq
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    export USER="testuser"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.jq
      ]
    }"

    mkdir -p "$HOME/.local/bin" "$XDG_RUNTIME_DIR" "$PWD/bin"

    cat > "$PWD/bin/keystone-fingerprint-menu" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/desktop/home/scripts/keystone-fingerprint-menu.sh" "$@"
    EOF
    chmod +x "$PWD/bin/keystone-fingerprint-menu"
    ln -s "$PWD/bin/keystone-fingerprint-menu" "$HOME/.local/bin/keystone-fingerprint-menu"

    cat > "$PWD/bin/keystone-detach" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/detach-command.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/keystone-detach"

    cat > "$PWD/bin/ghostty" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exit 0
    EOF
    chmod +x "$PWD/bin/ghostty"

    cat > "$PWD/bin/notify-send" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/notify-send.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/notify-send"

    # ── Test 1: fprintd-list unavailable ──
    entries_json="$(keystone-fingerprint-menu entries-json)"
    printf '%s\n' "$entries_json" | jq -e '
      length == 4
      and .[0].Text == "Status"
      and (.[0].Subtext | contains("not available"))
      and .[1].Text == "Enroll finger"
      and .[2].Text == "Verify finger"
      and .[3].Text == "Delete fingerprints"
    ' >/dev/null

    summary_text="$(keystone-fingerprint-menu summary)"
    printf '%s\n' "$summary_text" | grep -F 'fprintd unavailable' >/dev/null

    # ── Test 2: fprintd-list with enrolled fingers ──
    cat > "$PWD/bin/fprintd-list" <<'FPEOF'
    #!${pkgs.bash}/bin/bash
    printf 'found 1 devices\n'
    printf 'Device at /net/reactivated/Fprint/Device/0:\n'
    printf 'Using device /net/reactivated/Fprint/Device/0\n'
    printf 'Fingerprints for user %s on ELAN Fingerprint Sensor (press type):\n' "$1"
    printf '   - right-index-finger\n'
    FPEOF
    chmod +x "$PWD/bin/fprintd-list"

    entries_json="$(keystone-fingerprint-menu entries-json)"
    printf '%s\n' "$entries_json" | jq -e '
      .[0].Text == "Status"
      and (.[0].Subtext | contains("1 finger(s) enrolled"))
    ' >/dev/null

    summary_text="$(keystone-fingerprint-menu summary)"
    printf '%s\n' "$summary_text" | grep -F 'right-index-finger' >/dev/null

    # ── Test 3: fprintd-list with no enrolled fingers ──
    cat > "$PWD/bin/fprintd-list" <<'FPEOF'
    #!${pkgs.bash}/bin/bash
    printf 'found 1 devices\n'
    printf 'Device at /net/reactivated/Fprint/Device/0:\n'
    printf 'Using device /net/reactivated/Fprint/Device/0\n'
    printf 'Fingerprints for user %s on ELAN Fingerprint Sensor (press type):\n' "$1"
    FPEOF
    chmod +x "$PWD/bin/fprintd-list"

    entries_json="$(keystone-fingerprint-menu entries-json)"
    printf '%s\n' "$entries_json" | jq -e '
      .[0].Text == "Status"
      and (.[0].Subtext | contains("No fingers enrolled"))
    ' >/dev/null

    # ── Test 4: dispatch enroll launches Ghostty ──
    keystone-fingerprint-menu dispatch enroll
    grep -F 'ghostty' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null
    grep -F 'fprintd-enroll' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null

    # ── Test 4b: dispatch verify ──
    keystone-fingerprint-menu dispatch verify
    grep -F 'ghostty' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null
    grep -F 'fprintd-verify' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null

    # ── Test 4c: dispatch delete ──
    keystone-fingerprint-menu dispatch delete
    grep -F 'ghostty' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null
    grep -F 'fprintd-delete' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null

    # ── Test 4d: dispatch blocked sends notification ──
    keystone-fingerprint-menu dispatch $'blocked\tFingerprint\tService unavailable'
    grep -F 'Service unavailable' "$XDG_RUNTIME_DIR/notify-send.txt" >/dev/null

    # ── Test 5: preview outputs ──
    preview_enroll="$(keystone-fingerprint-menu preview enroll)"
    printf '%s\n' "$preview_enroll" | grep -F 'fprintd-enroll' >/dev/null

    preview_verify="$(keystone-fingerprint-menu preview verify)"
    printf '%s\n' "$preview_verify" | grep -F 'fprintd-verify' >/dev/null

    preview_delete="$(keystone-fingerprint-menu preview delete)"
    printf '%s\n' "$preview_delete" | grep -F 'fprintd-delete' >/dev/null

    printf '\nAll keystone-fingerprint-menu tests passed.\n'
    touch "$out"
  ''
