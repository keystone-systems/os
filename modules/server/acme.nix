# Keystone ACME Module
#
# Auto-configures wildcard SSL certificate via ACME/Let's Encrypt using
# DNS-01 challenge with Cloudflare.
#
# Required secret:
#   The credentialsFile must contain:
#   CLOUDFLARE_DNS_API_TOKEN=your_token
#
#   Example with agenix:
#   age.secrets.cloudflare-api-token = {
#     file = "${inputs.agenix-secrets}/secrets/cloudflare-api-token.age";
#     owner = "acme";
#     group = "acme";
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
      default = "/run/agenix/cloudflare-api-token";
      description = "Path to Cloudflare API token for DNS-01 challenge. Defaults to conventional agenix secret.";
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
    assertions = [
      {
        assertion = cfg.acme.credentialsFile != null;
        message = "keystone.server.acme.credentialsFile must be set for ACME DNS-01 challenge";
      }
    ]
    ++ lib.optional (cfg.acme.credentialsFile == "/run/agenix/cloudflare-api-token") {
      assertion = config.age.secrets ? "cloudflare-api-token";
      message = "keystone.server.acme requires age.secrets.\"cloudflare-api-token\" to be declared.";
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acme.email;

      certs."wildcard-${lib.replaceStrings [ "." ] [ "-" ] domain}" = {
        domain = "*.${domain}";
        extraDomainNames = [ domain ] ++ cfg.acme.extraDomainNames;
        dnsProvider = "cloudflare";
        environmentFile = cfg.acme.credentialsFile;
        group = "nginx";
        extraLegoFlags = [ "--dns.resolvers=1.1.1.1:53" ];
      };
    };
  };
}
