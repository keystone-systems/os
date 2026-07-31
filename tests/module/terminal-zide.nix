{
  pkgs,
  self,
  home-manager,
  ...
}:
let
  hmConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeModules.notes
      self.homeModules.terminal
      {
        nixpkgs.overlays = [ self.overlays.default ];
        home.username = "testuser";
        home.homeDirectory = "/home/testuser";
        home.stateVersion = "25.05";

        keystone.terminal = {
          enable = true;
          sandbox.enable = false;
          git = {
            userName = "Test User";
            userEmail = "testuser@example.com";
          };
        };
      }
    ];
  };

  packages = hmConfig.config.home.packages;
  zidePackage = builtins.head (builtins.filter (pkg: (pkg.pname or "") == "keystone-zide") packages);
in
pkgs.runCommand "terminal-zide-check" { } ''
  set -euo pipefail

  test -x "${zidePackage}/bin/zide"
  test -x "${zidePackage}/bin/zide-pick"
  test -x "${zidePackage}/bin/zide-edit"
  test -x "${zidePackage}/bin/zide-rename"

  "${zidePackage}/bin/zide" --help >/dev/null
  "${zidePackage}/bin/zide-pick" --help >/dev/null
  "${zidePackage}/bin/zide-edit" --help >/dev/null
  "${zidePackage}/bin/zide-rename" --help >/dev/null

  grep -F 'zide-pick' "${zidePackage}/layouts/default.kdl" >/dev/null
  grep -F 'command "$EDITOR"' "${zidePackage}/layouts/default.kdl" >/dev/null
  grep -F 'YAZI_CONFIG_HOME' "${zidePackage}/bin/.zide-pick-wrapped" >/dev/null
  test -f "${zidePackage}/yazi/plugins/auto-layout.yazi/init.lua"

  touch "$out"
''
