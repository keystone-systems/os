# Keystone Nginx Module
#
# Auto-configures nginx reverse proxy with:
# - Recommended settings (proxy, TLS, optimization, gzip)
# - VirtualHost generation from enabled services
# - Firewall rules for HTTP/HTTPS
#
{
  lib,
  config,
  ...
}:
let
  cfg = config.keystone.server;
  domain = config.keystone.domain;
  serverLib = import ./lib.nix { inherit lib; };

  # Get the ACME cert name
  certName = "wildcard-${lib.replaceStrings [ "." ] [ "-" ] domain}";

  # Build virtualHosts from enabled services
  mkVirtualHost = name: svc: {
    name = "${svc.subdomain}.${domain}";
    value = {
      forceSSL = true;
      useACMEHost = certName;
      extraConfig =
        let
          accessConfig = serverLib.accessPresets.${svc.access};
          bodySize = lib.optionalString (svc.maxBodySize != null) "client_max_body_size ${svc.maxBodySize};";
        in
        lib.concatStringsSep "\n" (
          lib.filter (s: s != "") [
            accessConfig
            bodySize
          ]
        );
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString svc.port}";
        proxyWebsockets = svc.websockets;
      };
    };
  };

  enabledServices = lib.filterAttrs (n: v: v.enable or false) cfg._enabledServices;
  virtualHosts = lib.mapAttrs' mkVirtualHost enabledServices;
in
{
  options.keystone.server._enabledServices = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          subdomain = lib.mkOption { type = lib.types.str; };
          port = lib.mkOption { type = lib.types.port; };
          access = lib.mkOption {
            type = lib.types.enum [
              "tailscale"
              "public"
              "local"
              "tailscaleAndLocal"
            ];
            default = "tailscale";
          };
          maxBodySize = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          websockets = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          registerDNS = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      }
    );
    default = { };
    internal = true;
    description = "Internal registry of enabled services for nginx/DNS generation";
  };

  config = lib.mkIf (cfg.enable && domain != null) {
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts = virtualHosts;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
