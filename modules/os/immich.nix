# Immich Photo Management System
#
# Automatically configured based on keystone.services.immich:
# - host: The primary server (DB + Web)
# - workers: Remote GPU/ML workers
#
# Roles are auto-detected by hostname.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  services = config.keystone.services;
  hostName = config.networking.hostName;

  # Role detection
  isServer = services.immich.host == hostName;
  isWorker = elem hostName services.immich.workers;

  # Worker URL discovery
  getWorkerUrl =
    hName:
    let
      hostEntry = findFirst (h: h.hostname == hName) null (attrValues config.keystone.hosts);
      target =
        if hostEntry != null then
          (if hostEntry.sshTarget != null then hostEntry.sshTarget else hostEntry.fallbackIP)
        else
          hName;
    in
    "http://${target}:3003";

  # Server connects to the first worker if available, otherwise localhost
  mlUrl =
    if length services.immich.workers > 0 then
      getWorkerUrl (head services.immich.workers)
    else
      "http://localhost:3003";

  cfg = config.keystone.os.services.immich;
in
{
  options.keystone.os.services.immich = {
    enable = mkOption {
      type = types.bool;
      default = isServer || isWorker;
      description = "Auto-enabled if host matches keystone.services.immich host or workers.";
    };

    role = mkOption {
      type = types.enum [
        "server"
        "worker"
      ];
      default = if isServer then "server" else "worker";
      description = "Auto-detected role.";
    };

    acceleration = mkOption {
      type = types.nullOr (
        types.enum [
          "rocm"
          "cuda"
        ]
      );
      default = if isWorker then "rocm" else null;
      description = "GPU acceleration for workers. Defaults to rocm if host is a worker.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 2283;
    };

    mediaLocation = mkOption {
      type = types.path;
      default = "/var/lib/immich";
    };
  };

  config = mkIf cfg.enable {
    services.immich = mkMerge [
      # Common config
      {
        enable = true;
        machine-learning.environment.MPLCONFIGDIR = "/var/cache/immich/matplotlib";
      }
      # Server-specific
      (mkIf (cfg.role == "server") {
        host = cfg.host;
        port = cfg.port;
        mediaLocation = cfg.mediaLocation;
        machine-learning.enable = length services.immich.workers == 0;
        settings.machineLearning.url = mlUrl;
        environment.IMMICH_MACHINE_LEARNING_URL = lib.mkForce mlUrl;
      })
      # Worker-specific
      (mkIf (cfg.role == "worker") {
        # Disable non-ML components
        database.enable = false;
        redis.enable = false;
        # Satisfy module defaults and assertions
        redis.host = "localhost";
        database.host = "localhost";
        # Dummy secrets file path to satisfy assertion when database is disabled but host is set
        secretsFile = "${pkgs.writeText "immich-dummy-secrets" "DB_PASSWORD=unused"}";
        # Bind ML server to all interfaces so it's reachable over Tailscale
        machine-learning.environment.IMMICH_HOST = lib.mkForce "0.0.0.0";
      })
      # Acceleration
      (mkIf (cfg.acceleration == "rocm") {
        machine-learning.environment = {
          DEVICE = "rocm";
          HSA_OVERRIDE_GFX_VERSION = "10.3.0"; # Consumer GPU support
        };
      })
    ];

    # Manually disable server units on worker
    systemd.services.immich-server.enable = mkIf (cfg.role == "worker") false;
    systemd.services.immich-microservices.enable = mkIf (cfg.role == "worker") false;

    # Auto-register service tags for ACL generation.
    # Only server/agent roles get tags — client roles stay user-owned in
    # Headscale (adding tags would strip user identity and break admin ACLs).
    keystone.os.tailscale.tags =
      if cfg.role == "server" then
        [ "tag:svc-immich" ]
      else if
        isWorker
        && (findFirst (h: h.hostname == hostName) null (attrValues config.keystone.hosts)).role != "client"
      then
        [ "tag:svc-immich-ml" ]
      else
        [ ];

    # GPU Acceleration configuration (groups)
    users.users.immich.extraGroups = mkIf (cfg.acceleration != null) [
      "video"
      "render"
    ];

    # Open ML port only on tailscale interface for worker access
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = mkIf (cfg.role == "worker") [ 3003 ];
  };
}
