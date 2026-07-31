# Keystone Loki Service Module
#
# Loki is a log aggregation system.
# Default subdomain: loki
# Default port: 3100
# Default access: tailscale
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.loki;
in
{
  options.keystone.server.services.loki = serverLib.mkServiceOptions {
    description = "Loki log aggregation";
    subdomain = "loki";
    port = 3100;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.loki = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };

    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.port;
        auth_enabled = false;

        common = {
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          replication_factor = 1;
          path_prefix = "/var/lib/loki";
        };

        schema_config = {
          configs = [
            {
              from = "2024-04-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        storage_config = {
          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          delete_request_store = "filesystem";
        };

        limits_config = {
          retention_period = "90d";
          allow_structured_metadata = true;
        };
      };
    };
  };
}
