# ISO installer module evaluation test
#
# Verifies that the ISO installer NixOS configuration evaluates correctly
# without building the full ISO image (which requires ~4GB+ RAM for mksquashfs).
# This catches module option errors, missing imports, and package breakage
# at evaluation time — fast enough for CI.
#
# Build: nix build ./tests#test-iso-evaluation
#
{
  pkgs,
  lib,
}:
let
  # Use eval-config.nix directly since lib.nixosSystem is only available
  # on the nixpkgs flake output, not on pkgs.lib.
  evalConfig = import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Evaluate the ISO configuration the same way flake.nix does,
  # but only force evaluation of config options — not the ISO image derivation.
  # We import the module path directly rather than going through
  # self.nixosModules to avoid pulling in all parent flake inputs.
  isoEval = evalConfig {
    system = "x86_64-linux";
    modules = [
      "${pkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      ../../modules/iso-installer.nix
      {
        _module.args.sshKeys = [ ];
        # Match the kernel override from flake.nix
        boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;
      }
    ];
  };

  # Evaluate key config attributes to prove the module loads without errors.
  # We avoid evaluating system.build.isoImage which triggers the expensive
  # mksquashfs derivation.
  configChecks = {
    systemPackages = builtins.length isoEval.config.environment.systemPackages > 0;
    installerService = isoEval.config.systemd.services.keystone-installer.serviceConfig.ExecStart != "";
    sshEnabled = isoEval.config.services.openssh.enable;
    # boot.supportedFilesystems is an attrset in nixos-unstable (e.g. { zfs = true; })
    zfsSupport = isoEval.config.boot.supportedFilesystems.zfs or false;
    flakesEnabled = builtins.elem "flakes" isoEval.config.nix.settings.experimental-features;
    networkManager = isoEval.config.networking.networkmanager.enable;
    hostId = isoEval.config.networking.hostId != "";
  };

  # Fail the build if any check is false
  failedChecks = lib.filterAttrs (_: v: !v) configChecks;
in
pkgs.runCommand "test-iso-evaluation" { } ''
  echo "ISO installer evaluation tests"
  echo "=============================="
  echo ""
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: passed: if passed then "echo '  PASS: ${name}'" else "echo '  FAIL: ${name}' && exit 1"
    ) configChecks
  )}
  echo ""
  ${
    if failedChecks == { } then
      ''
        echo "All ISO evaluation checks passed!"
      ''
    else
      ''
        echo "FAILED checks: ${builtins.concatStringsSep ", " (builtins.attrNames failedChecks)}"
        exit 1
      ''
  }
  touch $out
''
