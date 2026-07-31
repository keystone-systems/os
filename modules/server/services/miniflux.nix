# Keystone Miniflux Service Module
#
# Miniflux is a minimalist RSS/Atom feed reader.
# Default subdomain: miniflux
# Default port: 8070
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
  cfg = serverCfg.services.miniflux;
in
{
  options.keystone.server.services.miniflux = serverLib.mkServiceOptions {
    description = "Miniflux RSS reader";
    subdomain = "miniflux";
    port = 8070;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.miniflux = {
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
