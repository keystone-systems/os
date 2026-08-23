{
  pkgs,
  lib,
  terminal,
  home-manager,
}:
let
  catalog = pkgs.runCommand "theme-hook-transaction-catalog" { } ''
    for theme in tokyo-night kanagawa; do
      mkdir -p "$out/$theme"
      printf 'themes {}\n' > "$out/$theme/zellij.kdl"
      printf 'inherits = "base16_default_dark"\n' > "$out/$theme/helix.toml"
      printf 'theme[main_bg]="#000000"\n' > "$out/$theme/btop.theme"
      printf 'gui: {}\n' > "$out/$theme/lazygit.yml"
    done
  '';
  hook = pkgs.writeShellApplication {
    name = "keystone-theme-hook";
    text = ''
      printf '%s\n' "$1" >> "$HOME/theme-hook.log"
      if [ "$1" = kanagawa ]; then
        exit 1
      fi
    '';
  };
in
pkgs.testers.nixosTest {
  name = "theme-hook-transaction";

  nodes.machine = {
    imports = [ home-manager.nixosModules.home-manager ];
    options.keystone = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    config = {
      nixpkgs.overlays = [ terminal.overlays.default ];
      users.users.tester = {
        isNormalUser = true;
        home = "/home/tester";
      };
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.tester = {
          imports = [ terminal.homeModules.default ];
          home.stateVersion = "24.11";
          keystone.terminal = {
            enable = true;
            ai.enable = false;
            git.enable = false;
            sandbox.enable = false;
            theme = {
              name = "tokyo-night";
              catalogs = [
                {
                  name = "test";
                  path = catalog;
                }
              ];
              postSwitchHooks = [ hook ];
            };
          };
        };
      };
      system.stateVersion = "24.11";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("su - tester -c 'keystone-theme-switch tokyo-night'")
    machine.succeed("grep -q '\"theme\": \"tokyo-night\"' /home/tester/.local/state/keystone/themes/current/.keystone-theme.json")
    machine.fail("su - tester -c 'keystone-theme-switch kanagawa'")
    machine.succeed("grep -q '\"theme\": \"tokyo-night\"' /home/tester/.local/state/keystone/themes/current/.keystone-theme.json")
    machine.succeed("test $(tail -n 1 /home/tester/theme-hook.log) = tokyo-night")
  '';
}
