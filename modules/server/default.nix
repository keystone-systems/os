# Keystone Server Module
#
# This module provides a unified server services configuration:
# - Auto-configures nginx reverse proxy with SSL
# - Auto-configures ACME wildcard certificates
# - Auto-generates headscale DNS records
# - Standard defaults for domains, ports, access control
#
# Usage:
#   keystone.domain = "example.com";  # shared top-level domain
#   keystone.server = {
#     enable = true;
#     tailscaleIP = "100.64.0.6";
#     acme.credentialsFile = config.age.secrets.cloudflare-api-token.path;
#
#     services.immich.enable = true;      # -> photos.example.com, port 2283, tailscale
#     services.vaultwarden.enable = true; # -> vaultwarden.example.com, port 8222
#     services.forgejo.enable = true;     # -> git.example.com, port 3001
#   };
#
# Port Allocation Registry:
#   Port | Service      | Notes
#   -----|--------------|-------------
#   2283 | immich       |
#   3000 | adguard      | Admin UI
#   3001 | forgejo      | HTTP
#   3002 | grafana      |
#   3100 | loki         |
#   8070 | miniflux     |
#   8080 | headscale    |
#   8082 | mail         | Stalwart admin
#   8199 | attic        | Binary cache
#   8222 | vaultwarden  |
#   8333 | seaweedfs    | S3-compatible API (proxied); 8880/8888/9333 internal
#   9090 | prometheus   |
#
{
  lib,
  config,
  ...
}:
let
  cfg = config.keystone.server;

  # Collect ports from enabled services for conflict detection
  enabledServices = lib.filterAttrs (n: v: v.enable or false) cfg._enabledServices;
  enabledPorts = lib.mapAttrsToList (n: v: {
    name = n;
    port = v.port;
  }) enabledServices;
  portList = map (s: s.port) enabledPorts;
  uniquePorts = lib.unique portList;
in
{
  imports = [
    # Legacy modules (to be migrated)
    ./vpn.nix
    ./mail.nix
    ./monitoring.nix
    ./headscale.nix

    # New infrastructure
    ./acme.nix
    ./nginx.nix
    ./dns.nix

    # Service modules
    ./services/immich.nix
    ./services/vaultwarden.nix
    ./services/forgejo.nix
    ./services/grafana
    ./services/prometheus.nix
    ./services/loki.nix
    ./services/headscale.nix
    ./services/miniflux.nix
    ./services/attic.nix
    ./services/mail.nix
    ./services/adguard.nix
    ./services/seaweedfs.nix
    ./services/journal-remote.nix

    # Headscale DNS integration
    ./headscale/dns-import.nix
  ];

  options.keystone.server = {
    enable = lib.mkEnableOption "Keystone server services";

    # Legacy options (keep for backwards compatibility)
    vpn = {
      enable = lib.mkEnableOption "VPN server with Headscale (Kubernetes-based)";
    };

    mail = {
      enable = lib.mkEnableOption "Mail server (legacy module)";
    };

    monitoring = {
      enable = lib.mkEnableOption "Monitoring stack with Prometheus and Grafana (legacy module)";
    };

    headscale = {
      enable = lib.mkEnableOption "Headscale exit node (legacy module)";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (
      config.keystone.domain == null
    ) "keystone.domain is not set. Sub-services cannot auto-derive their subdomains.";

    assertions = [
      {
        assertion = lib.length portList == lib.length uniquePorts;
        message =
          let
            # Find duplicate ports
            findDuplicates =
              ports:
              let
                counts = lib.groupBy (p: toString p.port) enabledPorts;
                duplicates = lib.filterAttrs (port: services: lib.length services > 1) counts;
              in
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  port: services: "port ${port} used by: ${lib.concatMapStringsSep ", " (s: s.name) services}"
                ) duplicates
              );
          in
          "keystone.server: Port conflict detected among enabled services. ${findDuplicates enabledPorts}";
      }
    ];
  };
}
