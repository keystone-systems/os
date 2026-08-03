{
  pkgs,
  self,
  home-manager,
  ...
}:
let
  account = encryption: port: {
    email = "test@example.com";
    displayName = "Test User";
    login = "test";
    passwordCommand = "false";
    host = "imap.example.com";
    smtp = {
      host = "smtp.example.com";
      inherit encryption port;
    };
  };

  hmConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
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
            userEmail = "test@example.com";
          };
          mail = {
            enable = true;
            defaultAccount = "tls";
            accounts = {
              tls = account "tls" 465;
              "start-tls" = account "start-tls" 587;
              none = account "none" 25;
            };
          };
        };
      }
    ];
  };

  configFile = pkgs.writeText "himalaya-v2-config.toml" (
    hmConfig.config.xdg.configFile."himalaya/config.toml".text
  );
  himalayaPackage = builtins.head (
    builtins.filter (package: (package.pname or "") == "himalaya") hmConfig.config.home.packages
  );
in
pkgs.runCommand "terminal-mail-check" { } ''
  set -euo pipefail

  ${himalayaPackage}/bin/himalaya \
    --config ${configFile} \
    --json \
    account list > accounts.json

  ${pkgs.jq}/bin/jq -e '
    (.accounts | length) == 3
    and all(.accounts[]; (.backends | sort) == ["imap", "smtp"])
    and any(.accounts[]; .name == "tls" and .default)
  ' accounts.json >/dev/null

  grep -Fq 'smtp.server = "smtps://smtp.example.com:465"' ${configFile}
  grep -Fq 'smtp.server = "smtp://smtp.example.com:587"' ${configFile}
  grep -Fq 'smtp.server = "smtp://smtp.example.com:25"' ${configFile}

  test "$(grep -Fc 'smtp.starttls = true' ${configFile})" -eq 1
  test "$(grep -Fc 'mailbox.alias.inbox = "INBOX"' ${configFile})" -eq 3
  test "$(grep -Fc 'mailbox.alias.sent = "Sent Items"' ${configFile})" -eq 3
  test "$(grep -Fc 'mailbox.alias.drafts = "Drafts"' ${configFile})" -eq 3
  test "$(grep -Fc 'mailbox.alias.trash = "Deleted Items"' ${configFile})" -eq 3

  touch "$out"
''
