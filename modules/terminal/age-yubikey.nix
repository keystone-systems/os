# Keystone Terminal Age-YubiKey Identity Management
#
# Writes the age-plugin-yubikey identity file consumed by sops (via
# SOPS_AGE_KEY_FILE) and `ks secrets edit`. Recipient management and
# re-encryption are handled by `ks secrets sync` / `ks secrets rekey`.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.ageYubikey = {
#   enable = true;
#   identities = [
#     { serial = "36854515"; identity = "AGE-PLUGIN-YUBIKEY-17DDRYQ..."; }
#     { serial = "36862273"; identity = "AGE-PLUGIN-YUBIKEY-1G9UNYQ..."; }
#   ];
# };
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.ageYubikey;

  # Serial comments let tooling pick the identity matching the connected key.
  identityFileText =
    concatStringsSep "\n" (map (id: "# serial:${id.serial}\n${id.identity}") cfg.identities) + "\n";
in
{
  options.keystone.terminal.ageYubikey = {
    enable = mkEnableOption "age-plugin-yubikey identity file management";

    identities = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            serial = mkOption {
              type = types.str;
              description = "YubiKey serial number (from `ykman info`)";
              example = "36854515";
            };
            identity = mkOption {
              type = types.str;
              description = "AGE-PLUGIN-YUBIKEY identity string (from `age-plugin-yubikey`)";
              example = "AGE-PLUGIN-YUBIKEY-17DDRYQ5ZFMHALWQJTKHAV";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Age-plugin-yubikey identities with serial numbers. Generate identity with:
          age-plugin-yubikey --identity
        Get serial with:
          ykman info
      '';
    };

    identityPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.age/yubikey-identity.txt";
      description = "Path where the combined identity file is written";
    };
  };

  config = mkIf cfg.enable {
    home.file.".age/yubikey-identity.txt" = {
      text = identityFileText;
    };

    home.sessionVariables = {
      AGE_IDENTITIES_FILE = cfg.identityPath;
    };

    home.packages = with pkgs; [
      sops
      ssh-to-age
      age-plugin-yubikey
    ];
  };
}
