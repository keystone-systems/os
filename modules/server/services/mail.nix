# Keystone Mail Service Module
#
# Stalwart Mail server admin interface.
# Default subdomain: mail
# Default port: 8082
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
  cfg = serverCfg.services.mail;
in
{
  options.keystone.server.services.mail = serverLib.mkServiceOptions {
    description = "Stalwart Mail admin interface";
    subdomain = "mail";
    port = 8082;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.mail = {
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
