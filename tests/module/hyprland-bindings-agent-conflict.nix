{ pkgs }:
pkgs.runCommand "test-hyprland-bindings-agent-conflict"
  {
    nativeBuildInputs = with pkgs; [
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    bindings="${../..}/modules/desktop/home/hyprland/bindings.nix"

    grep -F '"$mod, T, layoutmsg, togglesplit"' "$bindings" >/dev/null
    grep -F '"$mod SHIFT, T, layoutmsg, togglesplit"' "$bindings" >/dev/null

    if grep -F '"$mod, J, layoutmsg, togglesplit"' "$bindings" >/dev/null; then
      echo "unexpected conflicting split-toggle binding on \$mod+J" >&2
      exit 1
    fi

    touch "$out"
  ''
