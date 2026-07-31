# Keystone Headscale Service Module
#
# Headscale is a self-hosted Tailscale control server.
# Default subdomain: mercury (typically the headscale server hostname)
# Default port: 8080
# Default access: public (required for external clients to connect)
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.headscale;
in
{
  options.keystone.server.services.headscale = serverLib.mkServiceOptions {
    description = "Headscale VPN control server";
    subdomain = "mercury";
    port = 8080;
    access = "public";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.headscale = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };
  };
}
