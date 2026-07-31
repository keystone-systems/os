{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  pm = config.keystone.passwordManagers;
  terminalEnabled = config.keystone.terminal.enable or false;
  desktopEnabled = config.keystone.desktop.enable or false;

  managerType =
    name: defaults:
    types.submodule {
      options = {
        cli = {
          enable = mkEnableOption "${name} CLI";
          package = mkOption {
            type = types.package;
            default = defaults.cli;
            defaultText = literalExpression defaults.cliText;
            description = "Package providing the ${name} CLI.";
          };
        };
        desktop = {
          enable = mkEnableOption "${name} desktop application";
          package = mkOption {
            type = types.package;
            default = defaults.desktop;
            defaultText = literalExpression defaults.desktopText;
            description = "Package providing the ${name} desktop application.";
          };
        };
      };
    };
in
{
  options.keystone.passwordManagers = {
    bitwarden = mkOption {
      type = managerType "Bitwarden" {
        cli = pkgs.bitwarden-cli;
        cliText = "pkgs.bitwarden-cli";
        desktop = pkgs.bitwarden-desktop;
        desktopText = "pkgs.bitwarden-desktop";
      };
      default = { };
      description = "Bitwarden password manager install options.";
    };

    # Identifier-safe key (matches `bitwarden`); the display name stays
    # "1Password". A `"1password"` key would force quoted-attribute syntax
    # in every consumer config.
    onepassword = mkOption {
      type = managerType "1Password" {
        cli = pkgs._1password-cli;
        cliText = "pkgs._1password-cli";
        desktop = pkgs._1password-gui;
        desktopText = "pkgs._1password-gui";
      };
      default = { };
      description = "1Password manager install options.";
    };
  };

  config.home.packages =
    optional (terminalEnabled && pm.bitwarden.cli.enable) pm.bitwarden.cli.package
    ++ optional (desktopEnabled && pm.bitwarden.desktop.enable) pm.bitwarden.desktop.package
    ++ optional (terminalEnabled && pm.onepassword.cli.enable) pm.onepassword.cli.package
    ++ optional (desktopEnabled && pm.onepassword.desktop.enable) pm.onepassword.desktop.package;
}
