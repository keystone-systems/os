# Keystone Binary Cache Client Module
#
# Configures a NixOS machine to use an Attic binary cache as a substituter.
# Import this on client machines that should pull from or push to the cache.
#
# Usage:
#   keystone.binaryCache = {
#     enable = true;
#     # url is auto-derived from keystone.domain (https://cache.<domain>)
#     publicKey = "cache.example.com-1:AAAA...=";
#
#     push.enable = true;  # tokenFile defaults to /run/agenix/attic-push-token
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.binaryCache;
in
{
  options.keystone.binaryCache = {
    enable = mkEnableOption "Keystone binary cache client";

    url = mkOption {
      type = types.str;
      default = "https://cache.${config.keystone.domain}";
      defaultText = literalExpression ''"https://cache.''${config.keystone.domain}"'';
      example = "https://cache.example.com";
      description = "Base URL of the Attic binary cache. Defaults to cache.<domain>.";
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "cache.example.com-1:AAAA...=";
      description = "Public key for verifying store path signatures from the cache.";
    };

    push = {
      enable = mkEnableOption "push support to the binary cache";

      cacheName = mkOption {
        type = types.str;
        default = "main";
        description = "Name of the cache on the Attic server.";
      };

      tokenFile = mkOption {
        type = types.path;
        default = "/run/agenix/attic-push-token";
        description = "Path to Attic auth token. Defaults to conventional agenix secret.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions =
      lib.optional (cfg.push.enable && cfg.push.tokenFile == "/run/agenix/attic-push-token")
        {
          assertion = config.age.secrets ? "attic-push-token";
          message = "keystone.binaryCache.push requires age.secrets.\"attic-push-token\" to be declared.";
        };

    nix.settings.substituters = mkAfter [
      # Append cacheName because nix probes <url>/nix-cache-info, and attic
      # serves that endpoint at /<cache>/nix-cache-info (not at the root).
      "${cfg.url}/${cfg.push.cacheName}"
    ];
    nix.settings.trusted-public-keys = mkIf (cfg.publicKey != null) (mkAfter [ cfg.publicKey ]);

    environment.systemPackages = mkIf cfg.push.enable [ pkgs.attic-client ];

    systemd.services.attic-watch-store = mkIf cfg.push.enable {
      description = "Attic Watch Store";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        StateDirectory = "attic-watch-store";
        LoadCredential = "token:${cfg.push.tokenFile}";
        ExecStart = pkgs.writeShellScript "attic-watch-store" ''
          set -eu
          export XDG_CONFIG_HOME="/var/lib/attic-watch-store"
          # attic login takes the base server URL (without cache name), not the
          # substituter URL — the cache name is only specified in push/pull commands.
          ${pkgs.attic-client}/bin/attic login cache ${cfg.url} $(cat $CREDENTIALS_DIRECTORY/token)
          exec ${pkgs.attic-client}/bin/attic watch-store cache:${cfg.push.cacheName}
        '';
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
