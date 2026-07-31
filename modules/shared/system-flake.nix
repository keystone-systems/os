# Keystone System Flake — declarative consumer-flake pointer.
#
# Declares the authoritative path to the consumer flake that produced the
# running NixOS system.  At activation time the resolved path is written to
# /run/current-system/keystone-system-flake (a plain file containing an
# absolute path followed by a newline).
#
# `ks update` and `ks switch` read that file as their single source of truth.
# The only accepted override is an explicit `ks --flake <path>` flag.
#
{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.keystone.systemFlake;
in
{
  imports = [ ./update.nix ];

  options.keystone.systemFlake = {
    path = mkOption {
      type = types.path;
      default = "/home/${config.keystone.os.adminUsername}/repos/${config.keystone.os.adminUsername}/ks-config";
      defaultText = literalExpression ''
        "/home/''${config.keystone.os.adminUsername}/repos/''${config.keystone.os.adminUsername}/ks-config"
      '';
      description = ''
        Absolute path to the consumer flake that produced this system.
        Read by `ks update` and `ks switch` as the single source of truth.

        In development mode (keystone.development = true) point this at the
        live worktree.  The worktree-based pattern uses `ks --flake <path>`
        explicitly; no CWD detection or env-var magic is needed.
      '';
    };
  };

  config = {
    # Write the resolved path into the system derivation so that it is
    # available at /run/current-system/keystone-system-flake after every
    # nixos-rebuild switch / boot. The effective update channel is written
    # alongside it so runtime tools do not depend on session env freshness.
    system.systemBuilderCommands = ''
      printf '%s\n' "${cfg.path}" > $out/keystone-system-flake
      printf '%s\n' "${config.keystone.update.channel}" > $out/keystone-update-channel
    '';
  };
}
