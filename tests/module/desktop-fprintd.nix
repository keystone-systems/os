# desktop-fprintd — regression guard for the fprintd daemon + CLI wiring.
#
# The Walker fingerprint menu spawns `ghostty -e bash -lc '... fprintd-enroll'`
# for the actual enrollment step. That terminal does NOT inherit the wrapper's
# runtimeInputs PATH, so both the daemon and the CLI tools must be present at
# the NixOS system level. This test pins that at the rendered-config layer.
#
# Build: nix build .#checks.x86_64-linux.desktop-fprintd
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  result = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.operating-system
      self.nixosModules.desktop
      {
        system.stateVersion = "25.05";
        boot.loader.systemd-boot.enable = true;

        # Apply keystone overlay so pkgs.keystone.* (hyprpolkitagent etc.)
        # resolve during evaluation of nixos.nix's environment.systemPackages.
        nixpkgs.overlays = [ self.overlays.default ];

        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };

        keystone.desktop = {
          enable = true;
          user = "testuser";
        };

        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];
  };

  fprintdEnabled = result.config.services.fprintd.enable;

  systemPackageNames = map (p: lib.getName p) result.config.environment.systemPackages;
  fprintdInSystemPackages = builtins.elem "fprintd" systemPackageNames;
in
pkgs.runCommand "desktop-fprintd-check" { } ''
  errors=0

  if [ "${lib.boolToString fprintdEnabled}" = "true" ]; then
    echo "PASS: services.fprintd.enable is true when keystone.desktop.enable = true"
  else
    echo "FAIL: services.fprintd.enable must be true on desktop hosts — enrollment terminal inherits user PATH, not wrapper runtimeInputs" >&2
    errors=$((errors + 1))
  fi

  if [ "${lib.boolToString fprintdInSystemPackages}" = "true" ]; then
    echo "PASS: pkgs.fprintd is in environment.systemPackages"
  else
    echo "FAIL: pkgs.fprintd must be in environment.systemPackages so fprintd-enroll/list/verify/delete are on the global PATH" >&2
    errors=$((errors + 1))
  fi

  if [ "$errors" -gt 0 ]; then
    exit 1
  fi

  touch "$out"
''
