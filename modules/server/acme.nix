# Keystone ACME Module
#
# Auto-configures wildcard SSL certificate via ACME/Let's Encrypt using
# DNS-01 challenge with Cloudflare.
#
# Required secret:
#   The credentialsFile must contain:
#   CLOUDFLARE_DNS_API_TOKEN=your_token
#
#   Example (the env-file content lives under the `acme-env` key of
#   secrets/services/cloudflare.yaml):
#   keystone.secrets.provided.cloudflare-api-token = {
#     owner = "acme";
#     group = "acme";
#     scope = "service:cloudflare";
#     key = "acme-env";
#   };
#
{
  lib,
  config,
  ...
}:
let
  cfg = config.keystone.server;
  domain = config.keystone.domain;
  effectiveCredentialsFile =
    if cfg.acme.credentialsFile != null then
      cfg.acme.credentialsFile
    else
      # `or` fallback keeps the missing-secret case surfacing as the
      # assertion below, not as an attribute error.
      config.keystone.secrets.provided.cloudflare-api-token.path or "/run/secrets/cloudflare-api-token";
in
{
  options.keystone.server.acme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ACME wildcard certificate configuration. Set to true when using keystone.server.services.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "admin@${domain}";
      defaultText = lib.literalExpression ''"admin@''${keystone.domain}"'';
      example = "admin@example.com";
      description = "Email address for ACME account registration";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to Cloudflare API token for DNS-01 challenge. When null, uses
        the conventional `cloudflare-api-token` sops secret.
      '';
    };

    extraDomainNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "*.home.example.com"
        "example.com"
      ];
      description = "Additional domain names to include in the certificate";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.acme.enable && domain != null) {
    assertions = lib.optional (cfg.acme.credentialsFile == null) {
      assertion = config.keystone.secrets.provided ? "cloudflare-api-token";
      message = "keystone.server.acme requires keystone.secrets.provided.\"cloudflare-api-token\" to be declared.";
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acme.email;

      certs."wildcard-${lib.replaceStrings [ "." ] [ "-" ] domain}" = {
        domain = "*.${domain}";
        extraDomainNames = [ domain ] ++ cfg.acme.extraDomainNames;
        dnsProvider = "cloudflare";
        environmentFile = effectiveCredentialsFile;
        group = "nginx";
        extraLegoFlags = [ "--dns.resolvers=1.1.1.1:53" ];
      };
    };
  };
}
