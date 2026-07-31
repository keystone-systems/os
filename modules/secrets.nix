# Keystone Secrets Repository
#
# Shared option declaring the path to the agenix secrets repository.
# Set once per infrastructure, consumed by modules that auto-declare age.secrets:
#
#   - modules/os/users.nix: auto-declares age.secrets for sshAutoLoad
#
# Usage:
#   keystone.secrets.repo = inputs.agenix-secrets;
{ lib, ... }:
with lib;
{
  options.keystone.secrets.repo = mkOption {
    type = types.nullOr types.path;
    default = null;
    example = literalExpression "inputs.agenix-secrets";
    description = ''
      Path to agenix secrets repo. Used by keystone modules to auto-declare
      age.secrets entries. When null, secrets must be declared manually per-host.
    '';
  };
}
