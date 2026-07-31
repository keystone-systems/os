# Keystone Experimental Feature Flag
#
# Zero-dependency module declaring keystone.experimental.
# Import this in every module layer (NixOS, home-manager) so the flag
# is available everywhere. Nix deduplicates identical imports.
{ lib, ... }:
{
  options.keystone.experimental = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable experimental features. When true, modules marked as experimental
      are auto-enabled. When false (default), only the stable v1 surface is
      active.

      Defaults to false per process.enable-by-default rule 17.
    '';
  };
}
