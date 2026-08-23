# Keystone Services Registry
#
# Shared top-level options declaring which host runs each infrastructure service.
# Set once per infrastructure, consumed by multiple modules:
#
#   - modules/os/mail.nix: auto-enables Stalwart when hostName matches services.mail.host
#   - modules/os/git-server.nix: auto-enables Forgejo when hostName matches services.git.host
#   - modules/os/agents.nix: agentctl provision uses mail.host for secret recipients
#   - modules/os/users.nix: bridges forgejo.enable into home-manager when git.host is set
#   - ks.systems/terminal: installs Forgejo clients when forgejo.enable is true
#
# Usage:
#   keystone.services = {
#     mail.host = "ocean";
#     git.host = "ocean";
#   };
{ lib, config, ... }:
with lib;
let
  cfg = config.keystone.services;
  hosts = config.keystone.hosts;
  hostNames = mapAttrsToList (_: h: h.hostname) hosts;
  validateHost =
    name: host:
    optional (host != null && hosts != { } && !elem host hostNames) {
      assertion = false;
      message = "keystone.services.${name}.host = \"${host}\" does not match any hostname in keystone.hosts. Valid hostnames: ${concatStringsSep ", " hostNames}";
    };

  # The primary Keystone user — first user key in keystone.os.users.
  # Used for tag ownership in generated ACL rules.
  primaryUser = head (attrNames config.keystone.os.users);

  # Immich ML port — upstream default, used for ACL and firewall rules
  immichMLPort = 3003;

  # Resolve a worker hostname to its ACL destination identity.
  # Client-role hosts stay user-owned in Headscale (adding tags would strip
  # their user identity and break admin access rules). Server/agent-role
  # hosts use tag:svc-immich-ml since they are already tag-based.
  resolveWorkerDst =
    hName:
    let
      hostEntry = findFirst (h: h.hostname == hName) null (attrValues hosts);
      role = if hostEntry != null then hostEntry.role else "client";
    in
    if role == "client" then
      "${primaryUser}@:${toString immichMLPort}"
    else
      "tag:svc-immich-ml:${toString immichMLPort}";

  # Generate ACL rules for immich server <-> worker communication.
  # Only generated on the server host (where generatedACLRules is consumed).
  immichACLRules =
    let
      serverHost = cfg.immich.host;
      workers = cfg.immich.workers;
      isCurrentHostServer = config.networking.hostName == serverHost;
    in
    optionals (isCurrentHostServer && workers != [ ]) [
      {
        action = "accept";
        src = [ "tag:svc-immich" ];
        dst = map resolveWorkerDst workers;
      }
    ];
in
{
  options.keystone.services = {
    mail.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ocean";
      description = ''
        The networking.hostName of the mail server.
        Auto-enables Stalwart on that host. Used by agentctl provision
        to determine mail-password secret recipients.
      '';
    };

    git.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ocean";
      description = ''
        The networking.hostName of the git server.
        Auto-enables Forgejo on that host. Used by terminal to install forgejo-cli.
      '';
    };

    git.domain = mkOption {
      type = types.nullOr types.str;
      default = if config.keystone.domain != null then "git.${config.keystone.domain}" else null;
      description = "FQDN of the Forgejo instance (e.g., git.ncrmro.com). Used by terminal/forgejo.nix to generate tea config.";
    };

    git.sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port for git operations on the Forgejo instance.";
    };

    immich.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "The networking.hostName of the primary Immich server.";
    };

    immich.workers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of hostnames acting as GPU/ML workers.";
    };

    vaultwarden.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ocean";
      description = ''
        The networking.hostName of the Vaultwarden server.
        Auto-enables keystone.server.services.vaultwarden on that host
        and defaults keystone.terminal.secrets (rbw) on for users with
        terminal enabled across the fleet.
      '';
    };

    vaultwarden.domain = mkOption {
      type = types.nullOr types.str;
      default = if config.keystone.domain != null then "vaultwarden.${config.keystone.domain}" else null;
      description = "FQDN of the Vaultwarden instance (e.g., vaultwarden.ncrmro.com). Used by the terminal secrets bridge to set rbw base_url.";
    };

    cachedUserShare = {
      enable = mkEnableOption "a cached NFS user share between two fleet hosts";

      serverHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "workstation";
        description = "The networking.hostName of the host that exports the share.";
      };

      clientHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "laptop";
        description = "The networking.hostName of the Linux host that mounts and caches the share.";
      };

      exportPath = mkOption {
        type = types.str;
        default = "";
        example = "/srv/user-share";
        description = "Absolute server directory that becomes the NFS version 4 export root.";
      };

      owner = {
        uid = mkOption {
          type = types.int;
          default = 0;
          description = "User ID that owns all requests to the export.";
        };

        gid = mkOption {
          type = types.int;
          default = 0;
          description = "Group ID that owns all requests to the export.";
        };
      };

      client = {
        mountPoint = mkOption {
          type = types.str;
          default = "";
          example = "/mnt/user-share";
          description = "Absolute client directory for the mounted share.";
        };

        cache = {
          directory = mkOption {
            type = types.str;
            default = "/var/cache/fscache";
            description = "Directory in which cachefilesd stores cached file data.";
          };

          stopPercent = mkOption {
            type = types.ints.between 1 99;
            default = 20;
            description = ''
              Free-space percentage at which cachefilesd stops new allocations.
              This value is a watermark. It is not a storage quota.
            '';
          };

          cullPercent = mkOption {
            type = types.ints.between 1 99;
            default = 25;
            description = ''
              Free-space percentage below which cachefilesd removes old data.
              This value is a watermark. It is not a storage quota.
            '';
          };

          runPercent = mkOption {
            type = types.ints.between 1 99;
            default = 30;
            description = ''
              Free-space percentage above which cachefilesd stops data removal.
              This value is a watermark. It is not a storage quota.
            '';
          };
        };
      };
    };

    generatedTagOwners = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = ''
        Auto-generated Headscale tag owners from service topology.
        Consume on the headscale host via keystone.headscale.tagOwners.
      '';
    };

    generatedACLRules = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            action = mkOption {
              type = types.str;
              default = "accept";
            };
            comment = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            src = mkOption { type = types.listOf types.str; };
            dst = mkOption { type = types.listOf types.str; };
          };
        }
      );
      default = [ ];
      description = ''
        Auto-generated Headscale ACL rules from service topology.
        Consume on the headscale host via keystone.headscale.aclRules.
      '';
    };
  };

  config.keystone.services.generatedTagOwners =
    let
      hasWorkers = cfg.immich.host != null && cfg.immich.workers != [ ];
      hasTaggedWorkers = any (
        hName:
        let
          h = findFirst (h: h.hostname == hName) null (attrValues hosts);
        in
        h != null && h.role != "client"
      ) cfg.immich.workers;
    in
    optionalAttrs hasWorkers { "tag:svc-immich" = [ "${primaryUser}@" ]; }
    // optionalAttrs (hasWorkers && hasTaggedWorkers) { "tag:svc-immich-ml" = [ "${primaryUser}@" ]; };

  config.keystone.services.generatedACLRules = immichACLRules;

  config.assertions =
    (validateHost "mail" cfg.mail.host)
    ++ (validateHost "git" cfg.git.host)
    ++ (validateHost "immich" cfg.immich.host)
    ++ (concatMap (h: validateHost "immich.workers" h) cfg.immich.workers)
    ++ (validateHost "vaultwarden" cfg.vaultwarden.host)
    ++ (optionals cfg.cachedUserShare.enable (
      (validateHost "cachedUserShare.server" cfg.cachedUserShare.serverHost)
      ++ (validateHost "cachedUserShare.client" cfg.cachedUserShare.clientHost)
      ++ [
        {
          assertion = cfg.cachedUserShare.serverHost != null;
          message = "keystone.services.cachedUserShare.serverHost must be set when the share is enabled.";
        }
        {
          assertion = cfg.cachedUserShare.clientHost != null;
          message = "keystone.services.cachedUserShare.clientHost must be set when the share is enabled.";
        }
        {
          assertion = cfg.cachedUserShare.serverHost != cfg.cachedUserShare.clientHost;
          message = "keystone.services.cachedUserShare serverHost and clientHost must name different hosts.";
        }
        {
          assertion = hosts != { };
          message = "keystone.services.cachedUserShare requires entries in keystone.hosts.";
        }
      ]
    ))
    ++ (optional (cfg.vaultwarden.host != null && cfg.vaultwarden.domain == null) {
      assertion = false;
      message = ''
        keystone.services.vaultwarden.host is set ("${cfg.vaultwarden.host}") but
        keystone.services.vaultwarden.domain is null. The terminal secrets bridge
        cannot derive an rbw base_url without a domain.

        Either set keystone.domain (domain auto-derives to vaultwarden.''${keystone.domain})
        or set keystone.services.vaultwarden.domain explicitly.
      '';
    });
}
