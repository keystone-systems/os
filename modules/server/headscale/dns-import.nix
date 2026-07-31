# Keystone Headscale DNS Import Module
#
# Consumes DNS records from keystone.server.generatedDNSRecords and integrates
# them into headscale's extra_records configuration.
#
# Usage on headscale host:
#   keystone.headscale = {
#     enable = true;
#     dnsRecords =
#       oceanConfig.keystone.server.generatedDNSRecords
#       ++ mercuryConfig.keystone.server.generatedDNSRecords;
#   };
#
{
  lib,
  config,
  ...
}:
let
  cfg = config.keystone.headscale;
in
{
  options.keystone.headscale = {
    enable = lib.mkEnableOption "Headscale DNS integration";

    dnsRecords = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            type = lib.mkOption {
              type = lib.types.str;
              default = "A";
            };
            value = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = ''
        DNS records to add to headscale's extra_records.
        Typically aggregated from keystone.server.generatedDNSRecords of all hosts.
      '';
    };

    extraRecords = lib.mkOption {
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
      description = "Additional manual DNS records to include";
    };
  };

  config = lib.mkIf cfg.enable {
    # Merge dnsRecords into headscale configuration
    services.headscale.settings.dns.extra_records = cfg.dnsRecords ++ cfg.extraRecords;
  };
}
