# Keystone AdGuard Home Service Module
#
# AdGuard Home is a network-wide ad and tracker blocker.
# Default subdomain: adguard.home
# Default port: 3000
# Default access: tailscaleAndLocal (DNS should be accessible from local network)
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.adguard;
in
{
  options.keystone.server.services.adguard = serverLib.mkServiceOptions {
    description = "AdGuard Home DNS";
    subdomain = "adguard.home";
    port = 3000;
    access = "tailscaleAndLocal";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.adguard = {
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
