# Keystone Server Library
#
# Shared helpers for server service modules:
# - Access control presets (tailscale, public, local, tailscaleAndLocal)
# - mkServiceModule helper for consistent service definitions
# - Datasource UID constants for Grafana alert/dashboard provisioning
#
{ lib }:

{
  # Well-known datasource UIDs for Grafana provisioning
  # Alert rules and dashboards reference these to find the correct datasource
  datasourceUids = {
    prometheus = "prometheus";
    loki = "loki";
  };

  # Access control presets for nginx extraConfig
  # These restrict access based on client IP ranges
  accessPresets = {
    # Tailscale network only (100.64.0.0/10 IPv4, fd7a:115c:a1e0::/48 IPv6)
    tailscale = ''
      allow 100.64.0.0/10;
      allow fd7a:115c:a1e0::/48;
      deny all;
    '';

    # Tailscale + local network (192.168.1.0/24)
    tailscaleAndLocal = ''
      allow 100.64.0.0/10;
      allow fd7a:115c:a1e0::/48;
      allow 192.168.1.0/24;
      deny all;
    '';

    # Public access (no restrictions)
    public = "";

    # Local network only
    local = ''
      allow 192.168.1.0/24;
      deny all;
    '';
  };

  # Helper to create consistent service module options
  # Usage:
  #   options.keystone.server.services.myservice = mkServiceOptions {
  #     description = "My Service description";
  #     subdomain = "myservice";
  #     port = 8080;
  #     access = "tailscale";
  #   };
  mkServiceOptions =
    {
      description,
      subdomain,
      port,
      access ? "tailscale",
      maxBodySize ? null,
      websockets ? true,
      registerDNS ? true,
    }:
    {
      enable = lib.mkEnableOption description;

      subdomain = lib.mkOption {
        type = lib.types.str;
        default = subdomain;
        description = "Subdomain for this service (e.g., ${subdomain}.domain.com)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = port;
        description = "Port this service listens on";
      };

      access = lib.mkOption {
        type = lib.types.enum [
          "tailscale"
          "public"
          "local"
          "tailscaleAndLocal"
        ];
        default = access;
        description = ''
          Access control preset:
          - tailscale: Only allow Tailscale network
          - tailscaleAndLocal: Allow Tailscale and local network
          - public: No restrictions
          - local: Only allow local network
        '';
      };

      maxBodySize = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = maxBodySize;
        example = "50G";
        description = "Maximum request body size (nginx client_max_body_size)";
      };

      websockets = lib.mkOption {
        type = lib.types.bool;
        default = websockets;
        description = "Enable WebSocket proxying";
      };

      registerDNS = lib.mkOption {
        type = lib.types.bool;
        default = registerDNS;
        description = "Register this service in headscale DNS";
      };
    };
}
