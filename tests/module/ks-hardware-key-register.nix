{
  pkgs,
  ...
}:
let
  agePluginMock = pkgs.writeShellScriptBin "age-plugin-yubikey" ''
    printf '%s\n' \
      'Serial: 12345' \
      'Recipient: age1yubikey1testrecipient'
  '';
  pamU2fMock = pkgs.writeShellScriptBin "pamu2fcfg" ''
    printf '%s\n' 'alice:pam-handle,pam-public-key'
  '';
in
pkgs.runCommand "test-ks-hardware-key-register"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    set -euo pipefail

    mkdir -p "$TMPDIR/consumer/modules" "$TMPDIR/consumer/hardware-keys"
    touch "$TMPDIR/consumer/modules/keys.nix"
    touch "$TMPDIR/consumer/hardware-keys/yubi-test"
    printf '%s\n' \
      'sk-ssh-ed25519@openssh.com AAAATEST alice-yubi-test' \
      > "$TMPDIR/consumer/hardware-keys/yubi-test.pub"

    PATH="${agePluginMock}/bin:${pamU2fMock}/bin:$PATH" \
    USER=alice \
    HOSTNAME=hardware-key-test \
      ${pkgs.bash}/bin/bash ${../../packages/ks/ks.sh} \
        hardware-key register yubi-test \
        --serial 12345 \
        --owner alice \
        --repo "$TMPDIR/consumer" \
        > "$TMPDIR/output"

    grep -F 'keystone.hardwareKeys.yubi-test = "12345";' "$TMPDIR/output" >/dev/null
    grep -F 'keystone.hardwareKeyRegistrations.yubi-test = {' "$TMPDIR/output" >/dev/null
    grep -F 'sshPublicKeys = [ "sk-ssh-ed25519@openssh.com AAAATEST" ];' "$TMPDIR/output" >/dev/null
    grep -F 'pamU2f = [ "pam-handle,pam-public-key" ];' "$TMPDIR/output" >/dev/null
    grep -F 'ageRecipients = [ "age1yubikey1testrecipient" ];' "$TMPDIR/output" >/dev/null
    grep -F 'keystone.keys.alice.hardwareKeys.yubi-test = {' "$TMPDIR/output" >/dev/null
    grep -F 'handleSource = ../hardware-keys/yubi-test;' "$TMPDIR/output" >/dev/null

    touch "$out"
  ''
