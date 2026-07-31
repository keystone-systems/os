# Keystone SeaweedFS Blob Store Service Module
#
# SeaweedFS provides an S3-compatible object store (blob store) for self-hosted
# infrastructure. It supports hot/cold tiering, automatic expiration, and scales
# from single-node to distributed deployments.
#
# Default subdomain: s3
# Default port: 8333 (S3-compatible API, proxied via nginx)
#
# Internal ports (not exposed via nginx):
#   masterPort  (default 9333) - Metadata coordination (not proxied)
#   volumePort  (default 8880) - Data storage (not proxied)
#   filerPort   (default 8888) - Filesystem abstraction (not proxied)
#
# Use cases enabled here:
#   - Forgejo PR artifacts (attachment uploads)
#   - Forgejo issue/PR user uploads
#
# TODO: Configure Attic binary cache to use SeaweedFS S3 as storage backend
# TODO: Configure Forgejo LFS to use SeaweedFS S3 as storage backend
#
# S3 credentials are supplied via a JSON identity config file at s3ConfigFile.
# Generate with agenix and set keystone.server.services.seaweedfs.s3ConfigFile.
# Example identity file (JSON):
#   {
#     "identities": [
#       {
#         "name": "admin",
#         "credentials": [{"accessKey": "ACCESS_KEY", "secretKey": "SECRET_KEY"}],
#         "actions": ["Admin", "Read", "Write", "Tagging", "List"]
#       },
#       {
#         "name": "forgejo",
#         "credentials": [{"accessKey": "FJ_KEY", "secretKey": "FJ_SECRET"}],
#         "actions": ["Read", "Write", "Tagging", "List"]
#       }
#     ]
#   }
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.seaweedfs;
in
{
  options.keystone.server.services.seaweedfs =
    serverLib.mkServiceOptions {
      description = "SeaweedFS S3-compatible blob store";
      subdomain = "s3";
      port = 8333;
      access = "tailscale";
      maxBodySize = "10G";
      websockets = false;
      registerDNS = true;
    }
    // {
      masterPort = lib.mkOption {
        type = lib.types.port;
        default = 9333;
        description = "SeaweedFS master port (internal, not proxied).";
      };

      volumePort = lib.mkOption {
        type = lib.types.port;
        default = 8880;
        description = "SeaweedFS volume port (internal, not proxied).";
      };

      filerPort = lib.mkOption {
        type = lib.types.port;
        default = 8888;
        description = "SeaweedFS filer port (internal, not proxied).";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/seaweedfs";
        description = "Base directory for SeaweedFS data storage.";
      };

      s3ConfigFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/agenix/seaweedfs-s3-config";
        description = ''
          Path to the SeaweedFS S3 identity/credentials JSON config file.
          When null, S3 access control is disabled (anonymous access).
          Use an agenix secret for this in production.

          Expected JSON format:
            {
              "identities": [
                {
                  "name": "admin",
                  "credentials": [{"accessKey": "KEY", "secretKey": "SECRET"}],
                  "actions": ["Admin", "Read", "Write", "Tagging", "List"]
                }
              ]
            }
        '';
      };

      replication = lib.mkOption {
        type = lib.types.str;
        default = "000";
        description = ''
          SeaweedFS replication strategy for volumes.
          "000" = no replication (single copy, suitable for single-node setups).
          See SeaweedFS docs for multi-node replication codes.
        '';
      };

      dataCenter = lib.mkOption {
        type = lib.types.str;
        default = "DefaultDataCenter";
        description = ''
          SeaweedFS data center name for the filer.
          Useful for identifying nodes in multi-datacenter deployments.
        '';
      };
    };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.seaweedfs = {
      inherit (cfg)
        subdomain
        port
        access
        maxBodySize
        websockets
        registerDNS
        ;
    };

    users.users.seaweedfs = {
      isSystemUser = true;
      group = "seaweedfs";
      description = "SeaweedFS daemon user";
      home = cfg.dataDir;
      createHome = false;
    };

    users.groups.seaweedfs = { };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}'         0750 seaweedfs seaweedfs - -"
      "d '${cfg.dataDir}/master'  0750 seaweedfs seaweedfs - -"
      "d '${cfg.dataDir}/volume'  0750 seaweedfs seaweedfs - -"
      "d '${cfg.dataDir}/filer'   0750 seaweedfs seaweedfs - -"
    ];

    # --- Master: manages cluster metadata and volume locations ---
    systemd.services.seaweedfs-master = {
      description = "SeaweedFS Master";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.seaweedfs}/bin/weed"
          "master"
          "-port=${toString cfg.masterPort}"
          "-mdir=${cfg.dataDir}/master"
          "-defaultReplication=${cfg.replication}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # --- Volume: stores the actual file content ---
    systemd.services.seaweedfs-volume = {
      description = "SeaweedFS Volume";
      after = [
        "network.target"
        "seaweedfs-master.service"
      ];
      requires = [ "seaweedfs-master.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.seaweedfs}/bin/weed"
          "volume"
          "-port=${toString cfg.volumePort}"
          "-mserver=127.0.0.1:${toString cfg.masterPort}"
          "-dir=${cfg.dataDir}/volume"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # --- Filer: filesystem abstraction layer, required by S3 ---
    systemd.services.seaweedfs-filer = {
      description = "SeaweedFS Filer";
      after = [
        "network.target"
        "seaweedfs-master.service"
        "seaweedfs-volume.service"
      ];
      requires = [
        "seaweedfs-master.service"
        "seaweedfs-volume.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.seaweedfs}/bin/weed"
          "filer"
          "-port=${toString cfg.filerPort}"
          "-master=127.0.0.1:${toString cfg.masterPort}"
          "-dataCenter=${cfg.dataCenter}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # --- S3: S3-compatible API layer, fronted by nginx ---
    systemd.services.seaweedfs-s3 = {
      description = "SeaweedFS S3 API";
      after = [
        "network.target"
        "seaweedfs-filer.service"
      ];
      requires = [ "seaweedfs-filer.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        ExecStart =
          let
            # SECURITY: s3ConfigFile is a Nix path option, so it's an absolute path
            # validated at eval time. Systemd passes it directly to the process
            # without shell expansion, so no injection risk. We still guard with
            # ConditionPathExists to emit a clear failure instead of a cryptic crash.
            s3ConfigArg = lib.optionalString (cfg.s3ConfigFile != null) " -config=${cfg.s3ConfigFile}";
          in
          lib.concatStringsSep " " [
            "${pkgs.seaweedfs}/bin/weed"
            "s3"
            "-port=${toString cfg.port}"
            "-filer=127.0.0.1:${toString cfg.filerPort}"
            "-ip.bind=127.0.0.1"
          ]
          + s3ConfigArg;
        # Fail early with a clear message if the credentials file is missing,
        # rather than letting SeaweedFS start with anonymous S3 access.
        ConditionPathExists = lib.mkIf (cfg.s3ConfigFile != null) cfg.s3ConfigFile;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
