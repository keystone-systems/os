# Regression test for the polkit rule that lets walker-launched updates
# take a `systemd-inhibit` lock without an interactive auth prompt.
# Rule lives in modules/desktop/nixos.nix; servers don't get the grant.
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
      self.nixosModules.desktop
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
        keystone.desktop.enable = true;
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];
  };

  rendered = result.config.security.polkit.extraConfig;

  # Tokens in order, `.*` between, to tolerate formatting refactors. The
  # trailing `;` after YES is what distinguishes the live rule from a
  # comment that quotes it.
  ruleTokensInOrder =
    builtins.match (
      ".*subject\\.user == \"testuser\""
      + ".*action\\.id\\.indexOf\\(\"org\\.freedesktop\\.login1\\.inhibit-\"\\)"
      + ".*polkit\\.Result\\.YES;.*"
    ) rendered != null;

  fail = msg: throw "polkit-update-session-inhibit: ${msg}\nrendered extraConfig:\n${rendered}";
in
if !ruleTokensInOrder then
  fail ''subject.user == "<adminUsername>", action.id.indexOf("…inhibit-"), polkit.Result.YES; must appear in order''
else
  pkgs.runCommand "test-polkit-update-session-inhibit" { } ''
    echo "polkit-update-session-inhibit: rule present, token order intact."
    touch $out
  ''
