# Regression test for the canonical-path polkit rule that makes
# auth_admin_keep apply to keystone-approve-exec.
#
# pkexec calls realpath() on its target before handing it to polkit,
# so the XML policy's `exec.path` annotation pointing at the
# `/run/current-system` symlink never matches and polkit falls back to
# the generic `auth_admin` (no `_keep`), re-prompting on every call.
# The JS rule in security.polkit.extraConfig matches the canonical
# Nix store path (interpolated at build time) so the keep cache hits.
#
# Asserts the rendered rule contains the canonical store path, gates
# on subject.active, returns AUTH_ADMIN_KEEP, and does NOT reference
# the /run/current-system symlink.
#
# Build: nix build .#test-polkit-keystone-approve-cache
{
  pkgs,
  lib ? pkgs.lib,
  self,
}:
let
  result = (import "${pkgs.path}/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.operating-system
      {
        system.stateVersion = "25.05";
        boot.loader.systemd-boot.enable = true;
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];
  };

  rendered = result.config.security.polkit.extraConfig;

  hasCanonicalKeystonePath =
    let
      # Canonical store path looks like /nix/store/<32 hash chars>-keystone-approve-exec/bin/keystone-approve-exec
      pattern = "/nix/store/[a-z0-9]+-keystone-approve-exec/bin/keystone-approve-exec";
    in
    builtins.match ".*${pattern}.*" rendered != null;

  hasSymlinkPath = lib.hasInfix "/run/current-system/sw/bin/keystone-approve-exec" rendered;
  hasAuthAdminKeep = lib.hasInfix "AUTH_ADMIN_KEEP" rendered;
  hasSubjectActiveGate = lib.hasInfix "subject.active" rendered;

  fail = msg: throw "polkit-keystone-approve-cache: ${msg}\nrendered extraConfig:\n${rendered}";

  checks =
    lib.optional (!hasCanonicalKeystonePath)
      "rendered rule must reference /nix/store/<hash>-keystone-approve-exec/bin/keystone-approve-exec (the canonical path pkexec hands to polkit)"
    ++ lib.optional hasSymlinkPath "rendered rule must NOT reference /run/current-system/sw/bin/keystone-approve-exec — pkexec realpath()s the target so the symlink path never matches and the rule would silently regress to auth_admin (no _keep)"
    ++
      lib.optional (!hasAuthAdminKeep)
        "rendered rule must return AUTH_ADMIN_KEEP — without it, single-prompt update flow regresses to a re-prompt on every pkexec call"
    ++
      lib.optional (!hasSubjectActiveGate)
        "rendered rule must gate on subject.active — without it, inactive sessions can also cache, breaching the XML policy's allow_inactive=no semantic";

in
if checks != [ ] then
  fail (lib.concatStringsSep "\n  - " ([ "" ] ++ checks))
else
  pkgs.runCommand "test-polkit-keystone-approve-cache" { } ''
    echo "polkit-keystone-approve-cache: rule references canonical helper path,"
    echo "  returns AUTH_ADMIN_KEEP, gates on subject.active, and avoids the"
    echo "  /run/current-system symlink trap."
    touch $out
  ''
