# Registry-derived zrepl snapshot and pull-replication topology (REQ-033).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrNames
    attrValues
    concatMap
    filter
    findFirst
    flatten
    hasPrefix
    mapAttrsToList
    mkIf
    optionals
    splitString
    unique
    ;
  osCfg = config.keystone.os;
  hostname = config.networking.hostName;
  hosts = config.keystone.hosts;
  current = findFirst (host: host.hostname == hostname) null (attrValues hosts);
  backups = if current != null && current.zfs != null then current.zfs.backups else { };
  registry = osCfg.storage.zfs.datasets;
  durableClasses = [
    "system"
    "state"
    "critical-state"
  ];
  dataDatasets = attrNames (
    lib.filterAttrs (_: dataset: builtins.elem dataset.class durableClasses) registry
  );
  credstoreDatasets = attrNames (
    lib.filterAttrs (_: dataset: dataset.class == "key-escrow") registry
  );
  replicatedPools = attrNames backups;
  format = pkgs.formats.yaml { };

  validTarget =
    target:
    let
      parts = splitString ":" target;
    in
    builtins.length parts == 2 && builtins.elemAt parts 0 != "" && builtins.elemAt parts 1 != "";
  parseTarget =
    target:
    let
      parts = splitString ":" target;
    in
    {
      hostKey = builtins.elemAt parts 0;
      pool = builtins.elemAt parts 1;
    };
  safeParseTarget =
    target:
    if validTarget target then
      parseTarget target
    else
      {
        hostKey = "";
        pool = "";
      };

  sourceTargets = flatten (
    mapAttrsToList (
      sourcePool: poolCfg:
      map (
        target:
        let
          parsed = safeParseTarget target;
        in
        {
          inherit sourcePool target;
          sourceHost = current;
          sourceKey = currentKey;
          inherit (parsed) hostKey pool;
          policy = poolCfg.targetPolicies.${target} or null;
          targetHost = hosts.${parsed.hostKey} or null;
          local = parsed.hostKey != "" && parsed.hostKey == currentKey;
        }
      ) poolCfg.targets
    ) backups
  );

  findHostKey =
    wantedHostname:
    let
      matches = filter (key: hosts.${key}.hostname == wantedHostname) (attrNames hosts);
    in
    if matches == [ ] then "" else builtins.head matches;
  currentKey = findHostKey hostname;

  allIncoming = flatten (
    mapAttrsToList (
      sourceKey: sourceHost:
      if sourceHost.zfs == null then
        [ ]
      else
        flatten (
          mapAttrsToList (
            sourcePool: poolCfg:
            map (
              target:
              let
                parsed = safeParseTarget target;
              in
              {
                inherit
                  sourceKey
                  sourceHost
                  sourcePool
                  target
                  ;
                inherit (parsed) hostKey pool;
                policy = poolCfg.targetPolicies.${target} or null;
                local = parsed.hostKey == sourceKey;
              }
            ) poolCfg.targets
          ) sourceHost.zfs.backups
        )
    ) hosts
  );
  incoming = filter (entry: entry.hostKey == currentKey) allIncoming;
  incomingPoolsDeclared = builtins.all (
    entry:
    builtins.hasAttr entry.pool osCfg.storage.zfs.pools
    && osCfg.storage.zfs.pools.${entry.pool}.role == "fleet-data"
    && osCfg.storage.zfs.pools.${entry.pool}.importService != null
  ) incoming;
  receiverImportServices = unique (
    filter (service: service != null) (
      map (entry: osCfg.storage.zfs.pools.${entry.pool}.importService) (
        filter (entry: builtins.hasAttr entry.pool osCfg.storage.zfs.pools) incoming
      )
    )
  );

  slug = value: lib.replaceStrings [ "." ":" "/" ] [ "-" "-" "-" ] value;
  listener = entry: "${slug entry.sourceHost.hostname}-${slug entry.sourcePool}-${slug entry.pool}";
  streamPort = entry: stream: entry.policy.port + (if stream == "credstore" then 1 else 0);
  datasetsForPool = pool: datasets: filter (dataset: hasPrefix "${pool}/" dataset) datasets;
  filesystems =
    pool: stream:
    lib.genAttrs (datasetsForPool pool (if stream == "data" then dataDatasets else credstoreDatasets)) (
      _: true
    );
  retentionGrid =
    policy:
    "1x1h(keep=all) | ${toString policy.retention.hourly}x1h | ${toString policy.retention.daily}x1d | ${toString policy.retention.monthly}x30d";
  preserveForeign = {
    type = "regex";
    negate = true;
    regex = "^zrepl_";
  };
  keepZrepl = policy: {
    type = "grid";
    grid = retentionGrid policy;
    regex = "^zrepl_";
  };

  mkServe =
    entry: stream:
    if entry.local then
      {
        type = "local";
        listener_name = "${listener entry}-${stream}";
      }
    else
      {
        type = "tcp";
        listen = "${current.tailscaleIP}:${toString (streamPort entry stream)}";
        clients = {
          "${entry.targetHost.tailscaleIP}" = entry.targetHost.hostname;
        };
      };
  mkConnect =
    entry: stream:
    if entry.local then
      {
        type = "local";
        listener_name = "${listener entry}-${stream}";
        client_identity = hostname;
      }
    else
      {
        type = "tcp";
        address = "${entry.sourceHost.tailscaleIP}:${toString (streamPort entry stream)}";
      };
  receiverRoot = entry: "${entry.pool}/replicas/${entry.sourceHost.hostname}";
  receiverRootBase = entry: "${entry.pool}/replicas";
  mkSourceJob = entry: stream: {
    type = "source";
    name = "source-${slug entry.target}-${slug entry.sourcePool}-${stream}";
    serve = mkServe entry stream;
    filesystems = filesystems entry.sourcePool stream;
    snapshotting.type = "manual";
    send =
      if stream == "data" then
        { encrypted = true; }
      else
        {
          raw = true;
          encrypted = false;
        };
  };
  mkPullJob = entry: stream: {
    type = "pull";
    name = "pull-${slug entry.sourceHost.hostname}-${slug entry.sourcePool}-${stream}";
    connect = mkConnect entry stream;
    # zrepl appends the complete source dataset path below root_fs. Keep the
    # source pool out of this prefix so rpool/crypt/... lands exactly once.
    root_fs = receiverRoot entry;
    interval = entry.policy.schedule;
    conflict_resolution.initial_replication = "most_recent";
    pruning = {
      keep_sender = [
        {
          type = "regex";
          regex = ".*";
        }
      ];
      keep_receiver = [
        preserveForeign
        (keepZrepl entry.policy)
      ];
    };
    recv = {
      placeholder.encryption = "off";
      properties.override = {
        mountpoint = "none";
        canmount = "off";
        "org.openzfs.systemd:ignore" = "on";
      };
    }
    // lib.optionalAttrs (entry.policy.receiveBandwidthLimit != null) {
      bandwidth_limit.max = entry.policy.receiveBandwidthLimit;
    };
  };

  snapJobs = map (sourcePool: {
    type = "snap";
    name = "snap-${slug sourcePool}";
    filesystems = filesystems sourcePool "data" // filesystems sourcePool "credstore";
    snapshotting = {
      type = "periodic";
      prefix = "zrepl_";
      interval = "1h";
    };
    pruning.keep = [
      preserveForeign
      {
        type = "grid";
        grid = "1x1h(keep=all) | 24x1h | 7x1d | 4x7d | 6x30d";
        regex = "^zrepl_";
      }
    ];
  }) replicatedPools;
  dataSourceJobs = map (entry: mkSourceJob entry "data") sourceTargets;
  credstoreSourceJobs = map (entry: mkSourceJob entry "credstore") sourceTargets;
  dataPullJobs = map (entry: mkPullJob entry "data") incoming;
  credstorePullJobs = map (entry: mkPullJob entry "credstore") incoming;
  receiverRootDatasets = unique (
    concatMap (entry: [
      (receiverRootBase entry)
      (receiverRoot entry)
    ]) incoming
  );
  receiverRootSetup = pkgs.writeShellScript "zrepl-receiver-roots" ''
    set -eu
    ${lib.concatMapStringsSep "\n" (dataset: ''
      if ! ${config.boot.zfs.package}/bin/zfs list -H -o name ${lib.escapeShellArg dataset} >/dev/null 2>&1; then
        ${config.boot.zfs.package}/bin/zfs create \
          -o canmount=off \
          -o mountpoint=none \
          ${lib.escapeShellArg dataset}
      fi
      type="$(${config.boot.zfs.package}/bin/zfs get -H -o value type ${lib.escapeShellArg dataset})"
      if [ "$type" != filesystem ]; then
        echo "zrepl receiver root ${dataset} exists but is not a filesystem" >&2
        exit 1
      fi
      ${config.boot.zfs.package}/bin/zfs set \
        canmount=off \
        mountpoint=none \
        org.openzfs.systemd:ignore=on \
        ${lib.escapeShellArg dataset}
    '') receiverRootDatasets}
  '';
  dataJobs = snapJobs ++ dataSourceJobs ++ dataPullJobs;
  credstoreJobs = credstoreSourceJobs ++ credstorePullJobs;
  credstoreSettings = {
    global = {
      control.sockpath = "/run/zrepl/credstore-control";
      monitoring = [
        {
          type = "prometheus";
          listen = "127.0.0.1:9812";
        }
      ];
    };
    jobs = credstoreJobs;
  };
  credstoreConfig = format.generate "zrepl-credstore.yml" credstoreSettings;
  remoteSourceTargets = filter (entry: !entry.local) sourceTargets;
  ports = concatMap (
    entry:
    map (streamPort entry) [
      "data"
      "credstore"
    ]
  ) (filter (entry: entry.policy != null) remoteSourceTargets);
  targetStrings = concatMap (pool: pool.targets) (attrValues backups);
  policiesComplete = builtins.all (entry: entry.policy != null) (sourceTargets ++ incoming);
  tailnetComplete = builtins.all (
    entry:
    entry.local
    || (
      entry.sourceHost.tailscaleIP != null
      && builtins.hasAttr entry.hostKey hosts
      && hosts.${entry.hostKey}.tailscaleIP != null
    )
  ) (sourceTargets ++ incoming);
  bandwidthValid = value: value == null || builtins.match "[1-9][0-9]* (K|M|G)i?B" value != null;
  scheduleValid = value: builtins.match "[1-9][0-9]*(s|m|h)" value != null;
  policiesMatchTargets = builtins.all (
    poolCfg:
    lib.sort builtins.lessThan poolCfg.targets
    == lib.sort builtins.lessThan (attrNames poolCfg.targetPolicies)
  ) (attrValues backups);
in
{
  config = mkIf (osCfg.enable && (backups != { } || incoming != [ ])) {
    assertions =
      map (target: {
        assertion = validTarget target && builtins.hasAttr (safeParseTarget target).hostKey hosts;
        message = "ZFS backup target '${target}' MUST reference a known '<host>:<pool>'.";
      }) targetStrings
      ++ [
        {
          assertion = osCfg.storage.type == "zfs";
          message = "zrepl backup endpoints require ZFS storage.";
        }
        {
          assertion = policiesComplete;
          message = "Every ZFS backup target MUST define a matching targetPolicies entry.";
        }
        {
          assertion = policiesMatchTargets;
          message = "ZFS targetPolicies keys MUST exactly match the declared targets.";
        }
        {
          assertion = tailnetComplete;
          message = "Both ends of every remote ZFS target MUST declare tailscaleIP.";
        }
        {
          assertion = incomingPoolsDeclared;
          message = "Every zrepl receiver pool MUST be a declared fleet-data pool with an importService.";
        }
        {
          assertion = builtins.length ports == builtins.length (unique ports);
          message = "Remote zrepl data and credstore source ports MUST NOT collide.";
        }
        {
          assertion = backups == { } || credstoreDatasets == [ "rpool/credstore" ];
          message = "The key-escrow registry MUST contain exactly rpool/credstore.";
        }
        {
          assertion = builtins.all (
            sourcePool:
            builtins.all (dataset: hasPrefix "${sourcePool}/crypt/" dataset) (
              datasetsForPool sourcePool dataDatasets
            )
          ) replicatedPools;
          message = "Replicated data datasets MUST be native-encrypted children of their source pool's crypt root.";
        }
        {
          assertion = builtins.all (
            entry: entry.policy == null || bandwidthValid entry.policy.receiveBandwidthLimit
          ) (sourceTargets ++ incoming);
          message = "zrepl receive bandwidth limits MUST be positive IEC byte rates such as '10 MiB'.";
        }
        {
          assertion = builtins.all (entry: entry.policy == null || scheduleValid entry.policy.schedule) (
            sourceTargets ++ incoming
          );
          message = "zrepl schedules MUST be positive second, minute, or hour durations such as '1h'.";
        }
      ];

    services.zrepl = {
      enable = true;
      settings = {
        global.monitoring = [
          {
            type = "prometheus";
            listen = "127.0.0.1:9811";
          }
        ];
        jobs = dataJobs;
      };
    };

    environment.etc."zrepl/credstore.yml".source = credstoreConfig;

    systemd.services = {
      zrepl-credstore = {
        description = "zrepl credstore replication daemon";
        wantedBy = [ "zfs.target" ];
        requires = [
          "local-fs.target"
        ]
        ++ optionals (incoming != [ ]) [
          "zrepl-receiver-roots.service"
        ];
        after = [
          "zfs.target"
        ]
        ++ optionals (incoming != [ ]) [
          "zrepl-receiver-roots.service"
        ];
        path = [ config.boot.zfs.package ];
        restartTriggers = [ credstoreConfig ];
        serviceConfig = {
          ExecStartPre = "${config.services.zrepl.package}/bin/zrepl --config ${credstoreConfig} configcheck";
          ExecStart = "${config.services.zrepl.package}/bin/zrepl --config ${credstoreConfig} daemon";
          Restart = "on-failure";
          RuntimeDirectory = "zrepl";
          RuntimeDirectoryMode = "0700";
        };
      };
    }
    // lib.optionalAttrs (incoming != [ ]) {
      zrepl = {
        requires = [ "zrepl-receiver-roots.service" ];
        after = [ "zrepl-receiver-roots.service" ];
      };
      zrepl-receiver-roots = {
        description = "Provision fail-closed zrepl receiver roots";
        requires = receiverImportServices;
        after = [ "zfs-mount.service" ] ++ receiverImportServices;
        before = [
          "zrepl.service"
          "zrepl-credstore.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = receiverRootSetup;
          RemainAfterExit = true;
        };
      };
    };

    # The fleet Prometheus receives Alloy remote-write metrics from every
    # endpoint. Keep alert expressions beside the metric-producing module so
    # consumers cannot silently retain the retired Syncoid series.
    services.prometheus.rules = optionals config.services.prometheus.enable [
      (builtins.toJSON {
        groups = [
          {
            name = "zrepl";
            rules = [
              {
                alert = "ZreplReplicationFilesystemErrors";
                expr = "zrepl_replication_filesystem_errors > 0";
                "for" = "10m";
                labels.severity = "warning";
                annotations.summary = "zrepl replication has filesystem errors on {{ $labels.instance }} ({{ $labels.zrepl_job }})";
              }
              {
                alert = "ZreplReplicationFilesystemErrors";
                expr = "zrepl_replication_filesystem_errors > 0";
                "for" = "3h";
                labels.severity = "critical";
                annotations.summary = "zrepl replication keeps failing on {{ $labels.instance }} ({{ $labels.zrepl_job }})";
              }
              {
                alert = "ZreplReplicationStale";
                expr = "time() - zrepl_replication_last_successful > 2 * 3600";
                "for" = "15m";
                labels.severity = "warning";
                annotations.summary = "zrepl replication is over two intervals stale on {{ $labels.instance }} ({{ $labels.zrepl_job }})";
              }
              {
                alert = "ZreplReplicationStale";
                expr = "time() - zrepl_replication_last_successful > 6 * 3600";
                "for" = "15m";
                labels.severity = "critical";
                annotations.summary = "zrepl replication is critically stale on {{ $labels.instance }} ({{ $labels.zrepl_job }})";
              }
              {
                alert = "ZreplSnapshotsInactive";
                expr = "sum by (instance) (increase(zrepl_zfs_snapshot_duration_count[2h])) == 0";
                "for" = "15m";
                labels.severity = "warning";
                annotations.summary = "zrepl created no snapshots for two intervals on {{ $labels.instance }}";
              }
              {
                alert = "ZreplMetricsAbsent";
                expr = "absent(zrepl_start_time)";
                "for" = "10m";
                labels.severity = "critical";
                annotations.summary = "zrepl metrics are absent from Prometheus";
              }
              {
                alert = "ZfsPoolCapacityHigh";
                expr = "zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.80";
                "for" = "30m";
                labels.severity = "warning";
                annotations.summary = "ZFS pool {{ $labels.pool }} on {{ $labels.instance }} is over 80% full";
              }
              {
                alert = "ZfsPoolCapacityHigh";
                expr = "zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.90";
                "for" = "30m";
                labels.severity = "critical";
                annotations.summary = "ZFS pool {{ $labels.pool }} on {{ $labels.instance }} is over 90% full";
              }
            ];
          }
        ];
      })
    ];

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = ports;
  };
}
