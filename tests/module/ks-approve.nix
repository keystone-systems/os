{
  pkgs,
  ks ? pkgs.keystone.ks,
}:
pkgs.runCommand "test-ks-approve"
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
    export PATH="$PWD/bin:${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.jq
      ]
    }"

    mkdir -p "$HOME" "$PWD/bin" "$PWD/logs"

    cat > "$PWD/bin/ks" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${ks}/bin/ks "$@"
    EOF
    chmod +x "$PWD/bin/ks"

    cat > "$PWD/bin/keystone-approve-exec" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    mode="exec"
    reason=""
    requested=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --validate) mode="validate"; shift ;;
        --reason) reason="$2"; shift 2 ;;
        --help|-h) exit 0 ;;
        --) shift; requested=("$@"); break ;;
        *) echo "unexpected helper arg: $1" >&2; exit 1 ;;
      esac
    done

    printf '%s\n' "$mode|$reason|''${requested[*]}" >> "$PWD/logs/helper.log"

    if [[ "$mode" == "validate" ]]; then
      if [[ "''${requested[*]}" == "keystone-enroll-fido2 --auto" ]]; then
        cat <<'JSON'
    {"displayName":"Enroll FIDO2 key","reason":"Allowlisted enrollment flow"}
    JSON
        exit 0
      fi
      printf 'Rejected command: %s\n' "''${requested[*]}" >&2
      exit 1
    fi

    printf '%s\n' "$reason|''${requested[*]}" > "$PWD/logs/executed.log"
    EOF
    chmod +x "$PWD/bin/keystone-approve-exec"

    cat > "$PWD/bin/pkexec" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    printf '%s\n' "$*" > "$PWD/logs/pkexec.log"
    exec "$@"
    EOF
    chmod +x "$PWD/bin/pkexec"

    cat > "$PWD/bin/sudo" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    printf '%s\n' "$*" > "$PWD/logs/sudo.log"
    exec "$@"
    EOF
    chmod +x "$PWD/bin/sudo"

    WAYLAND_DISPLAY=wayland-1 ks approve --reason "Enroll hardware key" -- keystone-enroll-fido2 --auto >"$PWD/logs/stdout-graphical.log"

    grep -F "Approval request: Enroll FIDO2 key" "$PWD/logs/stdout-graphical.log" >/dev/null
    grep -F -- "--reason Enroll hardware key -- keystone-enroll-fido2 --auto" "$PWD/logs/pkexec.log" >/dev/null
    [[ ! -e "$PWD/logs/sudo.log" ]]
    grep -F "exec|Enroll hardware key|keystone-enroll-fido2 --auto" "$PWD/logs/helper.log" >/dev/null

    rm -f "$PWD/logs/pkexec.log" "$PWD/logs/sudo.log"

    ks approve --reason "Enroll hardware key" -- keystone-enroll-fido2 --auto >"$PWD/logs/stdout-terminal.log"

    grep -F -- "--reason Enroll hardware key -- keystone-enroll-fido2 --auto" "$PWD/logs/sudo.log" >/dev/null
    [[ ! -e "$PWD/logs/pkexec.log" ]]

    if ks approve --reason "Nope" -- /bin/echo nope >"$PWD/logs/stdout-reject.log" 2>"$PWD/logs/stderr-reject.log"; then
      echo "ks approve unexpectedly accepted a rejected command" >&2
      exit 1
    fi

    grep -F "Rejected command:" "$PWD/logs/stderr-reject.log" >/dev/null

    touch "$out"
  ''
