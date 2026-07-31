# Keystone DNS Module
#
# Auto-generates DNS records from enabled services for headscale integration.
# Records are exported via keystone.server.generatedDNSRecords for consumption
# by the headscale host.
#
{
  lib,
  config,
  ...
}:
let
  cfg = config.keystone.server;
  domain = config.keystone.domain;

  # Build DNS records from enabled services
  enabledServices = lib.filterAttrs (
    n: v: (v.enable or false) && (v.registerDNS or true)
  ) cfg._enabledServices;

  mkDNSRecord = name: svc: {
    name = "${svc.subdomain}.${domain}";
    type = "A";
    value = cfg.tailscaleIP;
  };

  dnsRecords = lib.mapAttrsToList mkDNSRecord enabledServices;
in
{
  options.keystone.server = {
    tailscaleIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "100.64.0.6";
      description = "Tailscale IP address for this host. Used for DNS record generation.";
    };

    generatedDNSRecords = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            type = lib.mkOption { type = lib.types.str; };
            value = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = ''
        Auto-generated DNS records for enabled services.
        Consume these on the headscale host via keystone.headscale.dnsRecords.
        Note: This is an output option set by the module based on enabled services.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && domain != null && cfg.tailscaleIP != null) {
    keystone.server.generatedDNSRecords = dnsRecords;
  };
}
