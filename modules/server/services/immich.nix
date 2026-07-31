# Keystone Immich Service Module
#
# Immich is a self-hosted photo and video management solution.
# Default subdomain: photos
# Default port: 2283
# Default access: tailscale
# Default maxBodySize: 50G (for large video uploads)
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.immich;
in
{
  options.keystone.server.services.immich = serverLib.mkServiceOptions {
    description = "Immich photo and video management";
    subdomain = "photos";
    port = 2283;
    access = "tailscale";
    maxBodySize = "50G";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.immich = {
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
