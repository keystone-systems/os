{
  pkgs,
  ...
}:
# Wired into check-ks so the selection logic cannot regress unnoticed. The
# shell script beside it holds the cases; this only gives them a sandbox and
# the handful of tools they need. Unwired, the test would fail open.
pkgs.runCommand "test-ks-age-identity"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
    ];
  }
  ''
    cp ${../../packages/ks/ks.sh} ks.sh
    bash ${../ks-age-identity.sh} ks.sh
    touch "$out"
  ''
