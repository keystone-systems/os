# Keystone Terminal — GitHub token for per-user nix.conf (Darwin focus).
#
# On Darwin keystone hosts there is no nix-darwin system module (see
# lib/templates.nix mkDarwinInventoryHost — Darwin hosts are standalone
# home-manager only). `nix flake update` runs as the user, so authenticating
# GitHub flake fetches happens via the user's ~/.config/nix/nix.conf, not
# /etc/nix/nix.conf.
#
# This module materializes ~/.config/nix/access-tokens.conf at home-manager
# activation time from a token source — by default `gh auth token`, which
# leverages the existing gh CLI login the user already has. No agenix secret
# is required on macOS for this path.
#
# Pair with `keystone.terminal.github` (the PAT module) when you also want
# GITHUB_TOKEN/GH_TOKEN exported into the shell; the two modules are
# independent and complement each other.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  termCfg = config.keystone.terminal;
  cfg = termCfg.githubTokenNix;
  accessTokensFile = "${config.xdg.configHome}/nix/access-tokens.conf";
in
{
  options.keystone.terminal.githubTokenNix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Materialize ~/.config/nix/access-tokens.conf at home-manager
        activation time so per-user `nix flake update` invocations
        authenticate to GitHub. Primarily useful on Darwin where there
        is no system-level nix.conf writer.
      '';
    };

    source = lib.mkOption {
      type = lib.types.enum [
        "gh-auth"
        "tokenFile"
      ];
      default = "gh-auth";
      description = ''
        Where to read the token at activation time.
          gh-auth   : shell out to `gh auth token`. Requires gh CLI logged
                      in. Recommended on Darwin where agenix is not
                      typically wired.
          tokenFile : read from `tokenFile` (e.g. an agenix runtime path).
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/agenix/nix-github-token";
      description = ''
        Path to a token file when `source = "tokenFile"`. Ignored
        otherwise.
      '';
    };
  };

  config = lib.mkIf (termCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.source == "gh-auth" || cfg.tokenFile != null;
        message =
          "keystone.terminal.githubTokenNix.tokenFile must be set when " + "source = \"tokenFile\".";
      }
    ];

    # Append the include directive into the user nix.conf. `home.file.<p>.text`
    # is typed as `lines`, which concatenates across modules — composes with
    # the Darwin block in shell.nix that sets experimental-features.
    home.file.".config/nix/nix.conf".text = lib.mkAfter ''
      !include ${accessTokensFile}
    '';

    home.activation.keystoneGithubTokenNix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.coreutils}/bin/mkdir -p "$(dirname ${lib.escapeShellArg accessTokensFile})"
      umask 0177
      token=""
      ${
        if cfg.source == "gh-auth" then
          ''
            if command -v gh >/dev/null 2>&1; then
              token="$(gh auth token 2>/dev/null || true)"
            fi
          ''
        else
          ''
            if [ -r ${lib.escapeShellArg cfg.tokenFile} ]; then
              token="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg cfg.tokenFile})"
            fi
          ''
      }
      if [ -n "$token" ]; then
        tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg (accessTokensFile + ".XXXXXX")})"
        printf 'access-tokens = github.com=%s\n' "$token" > "$tmp"
        ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${lib.escapeShellArg accessTokensFile}
      else
        echo "keystone.terminal.githubTokenNix: no token available; skipping ${accessTokensFile}" >&2
      fi
    '';
  };
}
