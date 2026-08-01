# Keystone OS — GitHub token for the nix daemon.
#
# Materializes /etc/nix/access-tokens.conf from a root-readable sops
# secret and `!include`s it into nix.conf so flake fetches authenticate
# to GitHub and hit the 5000/hr authenticated rate ceiling instead of
# the 60/hr anonymous one.
#
# The token value never enters the Nix store: the secret stays in the
# sops runtime dir, and a hardened systemd oneshot copies it into the
# include file at activation time.
#
# Auto-discovery order (when `tokenFile` is unset):
#   1. nix-github-token              — dedicated nix-daemon secret
#   2. ${adminUsername}-github-token — user-home PAT shared as os-level
#   3. (nothing found) — module stays inert, no assertion failure
#
# See conventions/tool.nix.md for the os-level access-tokens convention.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os.githubTokenNix;
  adminUsername = config.keystone.os.adminUsername;
  userPatSecretName = "${adminUsername}-github-token";

  effectiveTokenFile =
    if cfg.tokenFile != null then
      cfg.tokenFile
    else if config.keystone.secrets.provided ? "nix-github-token" then
      config.keystone.secrets.provided."nix-github-token".path
    else if config.keystone.secrets.provided ? ${userPatSecretName} then
      config.keystone.secrets.provided.${userPatSecretName}.path
    else
      null;

  basename = if effectiveTokenFile == null then "" else baseNameOf effectiveTokenFile;
  validBasename =
    lib.hasSuffix "-github-token" basename && builtins.match "[a-z0-9-]+" basename != null;
in
{
  options.keystone.os.githubTokenNix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Wire a sops-decrypted GitHub token into /etc/nix/nix.conf via
        a root-readable include file, so the nix daemon uses the
        authenticated 5000/hr GitHub rate-limit ceiling for flake fetches.

        Token source is auto-discovered from declared keystone secrets when
        `tokenFile` is unset — first `nix-github-token` (dedicated), then
        `''${adminUsername}-github-token` (user-PAT shared at os-level).
        The module stays inert if neither is declared.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/nix-github-token";
      description = ''
        Explicit path to the decrypted token file. Overrides the auto-
        discovery chain. The adopter is responsible for declaring a
        `keystone.secrets.provided.<name>` entry that produces this file with
        `owner = "root"; mode = "0440";` (group-readable) when the same
        secret backs the user shell env, or `mode = "0400";` when
        dedicated to the nix daemon.

        See conventions/tool.nix.md.
      '';
    };

    includePath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nix/access-tokens.conf";
      description = ''
        Path of the include file the oneshot writes. Referenced from
        `nix.extraOptions` as `!include <path>`.
      '';
    };
  };

  config = lib.mkIf (config.keystone.os.enable && cfg.enable && effectiveTokenFile != null) {
    assertions = [
      {
        assertion = validBasename;
        message =
          "keystone.os.githubTokenNix effective token file basename '${basename}' does not match "
          + "the OS-level naming convention. Use 'nix-github-token' (portable), "
          + "'<hostname>-nix-github-token' (host-scoped dedicated), or "
          + "'<username>-github-token' (user-PAT shared at os-level). See "
          + "conventions/tool.nix.md.";
      }
    ];

    systemd.services.nix-github-access-token = {
      description = "Materialize ${cfg.includePath} from ${effectiveTokenFile}";
      # Secrets are installed during system activation (sops-nix), before
      # systemd units start — no explicit ordering needed.
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ (builtins.dirOf cfg.includePath) ];
        # /run/secrets lives on a ramfs mount; PrivateTmp would shadow it.
        PrivateTmp = false;
      };

      script = ''
        set -eu
        if [ ! -s ${lib.escapeShellArg effectiveTokenFile} ]; then
          echo "nix-github-access-token: ${effectiveTokenFile} missing or empty" >&2
          exit 1
        fi
        umask 0137
        tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg (cfg.includePath + ".XXXXXX")})"
        trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
        {
          printf 'access-tokens = github.com=%s\n' \
            "$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg effectiveTokenFile})"
        } > "$tmp"
        ${pkgs.coreutils}/bin/chown root:root "$tmp"
        ${pkgs.coreutils}/bin/chmod 0640 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${lib.escapeShellArg cfg.includePath}
        trap - EXIT
      '';
    };

    nix.extraOptions = lib.mkAfter ''
      !include ${cfg.includePath}
    '';
  };
}
