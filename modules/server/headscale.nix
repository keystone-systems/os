# Keystone Headscale Exit Node Module (Placeholder)
#
# This module will configure a Headscale exit node for VPN traffic routing.
# When implemented, it will:
# - Set up IP forwarding
# - Configure NAT/masquerading
# - Register as an exit node in Headscale
# - Handle firewall rules for VPN traffic
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.server.headscale;
in
{
  options.keystone.server.headscale = {
    # Exit node configuration options will be added here
    advertiseExitNode = mkOption {
      type = types.bool;
      default = true;
      description = "Advertise this node as an exit node";
    };

    # Additional options will be added when implemented
  };

  config = mkIf cfg.enable {
    # TODO: Implement Headscale exit node configuration
    # - Enable IP forwarding
    # - Configure NAT/masquerading
    # - Set up Headscale client
    # - Advertise as exit node

    warnings = [
      "keystone.server.headscale is not yet implemented - this is a placeholder for future functionality"
    ];
  };
}
