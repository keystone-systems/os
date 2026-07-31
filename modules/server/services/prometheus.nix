# Keystone Prometheus Service Module
#
# Prometheus is a monitoring and alerting toolkit.
# Default subdomain: prometheus
# Default port: 9090
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
  cfg = serverCfg.services.prometheus;
in
{
  options.keystone.server.services.prometheus = serverLib.mkServiceOptions {
    description = "Prometheus monitoring";
    subdomain = "prometheus";
    port = 9090;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.prometheus = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };

    services.prometheus = {
      enable = true;
      port = cfg.port;
      retentionTime = "90d";
      checkConfig = "syntax-only";

      exporters.node = {
        enable = true;
        enabledCollectors = [
          "systemd"
          "processes"
        ];
        port = 9100;
      };
    };
  };
}
