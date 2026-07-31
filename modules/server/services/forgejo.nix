# Keystone Forgejo Service Module
#
# Forgejo is a self-hosted Git service (Gitea fork).
# Default subdomain: git
# Default port: 3001
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
  cfg = serverCfg.services.forgejo;
in
{
  options.keystone.server.services.forgejo = serverLib.mkServiceOptions {
    description = "Forgejo Git service";
    subdomain = "git";
    port = 3001;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.forgejo = {
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
