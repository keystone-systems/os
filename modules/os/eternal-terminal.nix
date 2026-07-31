# Keystone OS Eternal Terminal Module
#
# Provides Eternal Terminal (et) for persistent remote shell sessions.
# ET uses SSH for initial authentication, then maintains a persistent
# connection over a separate port that survives network changes.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.services.eternalTerminal;
in
{
  config = mkIf (osCfg.enable && cfg.enable) {
    services.eternal-terminal = {
      enable = true;
      port = cfg.port;
    };

    # Open ET port only on tailscale interface for security
    networking.firewall.interfaces."tailscale0" = {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
