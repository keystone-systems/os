# Keystone Attic Service Module
#
# Attic is a Nix binary cache server.
# Default subdomain: cache
# Default port: 8199
# Default access: tailscale
#
# The atticd-init oneshot service auto-creates the cache and generates
# push tokens on first boot. For a clean start (e.g. after database
# corruption or version upgrade), delete state and restart:
#
#   sudo systemctl stop atticd atticd-init
#   sudo rm -rf /var/lib/private/atticd
#   sudo systemctl start atticd atticd-init
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.attic;
in
{
  options.keystone.server.services.attic =
    serverLib.mkServiceOptions {
      description = "Attic Nix binary cache server";
      subdomain = "cache";
      port = 8199;
      access = "tailscale";
      maxBodySize = "4G";
    }
    // {
      environmentFile = lib.mkOption {
        type = lib.types.path;
        default = "/run/agenix/attic-server-token-key";
        description = "Path to env file with ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64. Defaults to conventional agenix secret.";
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public key for nix substituter verification (optional)";
      };

      cacheName = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Name of the cache to auto-create on startup.";
      };
    };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    assertions = lib.optional (cfg.environmentFile == "/run/agenix/attic-server-token-key") {
      assertion = config.age.secrets ? "attic-server-token-key";
      message = "keystone.server.services.attic requires age.secrets.\"attic-server-token-key\" to be declared.";
    };

    environment.systemPackages = [ pkgs.attic-client ];

    keystone.server._enabledServices.attic = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };

    services.atticd = {
      enable = true;
      environmentFile = cfg.environmentFile;
      settings = {
        listen = "127.0.0.1:${toString cfg.port}";
        storage = {
          type = "local";
          # Storage must be a subdirectory, not the StateDirectory root.
          # Attic shards local storage by path prefix (e.g. s/se/server.db),
          # which collides with the SQLite database if both share the same directory.
          path = "/var/lib/atticd/storage";
        };
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "6 months";
        };
      };
    };

    systemd.services.atticd-init = {
      description = "Initialize Attic cache";
      after = [ "atticd.service" ];
      requires = [ "atticd.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = cfg.environmentFile;
        # Must match atticd.service: DynamicUser maps /var/lib/atticd to
        # /var/lib/private/atticd so we see the same database and write
        # output files (public-key, push-token) to the correct location.
        DynamicUser = true;
        User = "atticd";
        Group = "atticd";
        StateDirectory = "atticd";
      };

      script =
        let
          # Generate config from the same settings atticd uses. We can't reference
          # the NixOS module's internal checkedConfigFile, so we regenerate it.
          serverConfigFile =
            (pkgs.formats.toml { }).generate "attic-server.toml"
              config.services.atticd.settings;
          atticadm = "${pkgs.attic-server}/bin/atticadm -f ${serverConfigFile}";
          attic = "${pkgs.attic-client}/bin/attic";
          curl = "${pkgs.curl}/bin/curl";
        in
        ''
          set -eu

          # Wait for atticd to accept connections
          for i in $(seq 1 30); do
            if ${curl} -sf http://127.0.0.1:${toString cfg.port}/ >/dev/null 2>&1; then
              break
            fi
            echo "Waiting for atticd... ($i/30)"
            sleep 1
          done

          # Generate a short-lived admin token with full permissions for initialization.
          # Wildcards are safe here — the token expires in 5 minutes and never leaves localhost.
          TOKEN=$(${atticadm} make-token \
            --sub "init" \
            --validity "5m" \
            --push "*" \
            --pull "*" \
            --create-cache "*" \
            --configure-cache "*" \
            --configure-cache-retention "*" \
            --delete "*" \
            --destroy-cache "*")

          # Temporary config dir for attic CLI login state
          export XDG_CONFIG_HOME="$(mktemp -d)"
          trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT

          ${attic} login init http://127.0.0.1:${toString cfg.port} "$TOKEN"

          # Create cache (idempotent — exits 1 if cache already exists)
          if ${attic} cache create init:${cfg.cacheName}; then
            echo "Created cache '${cfg.cacheName}'"
          else
            echo "Cache '${cfg.cacheName}' already exists (or creation failed — check atticd logs)"
          fi

          # Make cache publicly readable so nix substituters work without auth
          ${attic} cache configure init:${cfg.cacheName} --public

          # Extract public key from cache info and write to file
          ${attic} cache info init:${cfg.cacheName} \
            | ${pkgs.gnugrep}/bin/grep "Public Key:" \
            | ${pkgs.gawk}/bin/awk '{print $3}' \
            > /var/lib/atticd/public-key

          # Generate long-lived push token for builder machines
          PUSH_TOKEN=$(${atticadm} make-token \
            --sub "builder" \
            --validity "10y" \
            --push "${cfg.cacheName}" \
            --pull "${cfg.cacheName}")

          echo "$PUSH_TOKEN" > /var/lib/atticd/push-token
          chmod 600 /var/lib/atticd/push-token

          echo "========================================="
          echo "Attic public key:"
          cat /var/lib/atticd/public-key
          echo "Push token written to /var/lib/atticd/push-token"
          echo "========================================="
        '';
    };

    # Self-configure the server host as a substituter so it can also pull
    # from its own cache. Clients use the binary-cache-client module instead.
    nix.settings = lib.mkIf (cfg.publicKey != null && config.keystone.domain != null) {
      substituters = [ "https://${cfg.subdomain}.${config.keystone.domain}" ];
      trusted-public-keys = [ cfg.publicKey ];
    };
  };
}
