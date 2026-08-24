# Registry-derived zrepl snapshot and pull-replication topology (REQ-033).
{
  config,
  lib,
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
  escrowDatasets = attrNames (lib.filterAttrs (_: dataset: dataset.class == "key-escrow") registry);
  replicatedPools = attrNames backups;
  streams = [
    "data"
    "escrow"
  ];

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

  slug = value: lib.replaceStrings [ "." ":" "/" ] [ "-" "-" "-" ] value;
  listener = entry: "${slug entry.sourceHost.hostname}-${slug entry.sourcePool}-${slug entry.pool}";
  streamPort = entry: stream: entry.policy.port + (if stream == "escrow" then 1 else 0);
  filesystems =
    stream: lib.genAttrs (if stream == "data" then dataDatasets else escrowDatasets) (_: true);
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
  mkSourceJob = entry: stream: {
    type = "source";
    name = "source-${slug entry.target}-${slug entry.sourcePool}-${stream}";
    serve = mkServe entry stream;
    filesystems = filesystems stream;
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
  mkPullJob =
    entry: stream:
    {
      type = "pull";
      name = "pull-${slug entry.sourceHost.hostname}-${slug entry.sourcePool}-${stream}";
      connect = mkConnect entry stream;
      root_fs = "${entry.pool}/backups/${
        if stream == "data" then "zfs" else "escrow"
      }/${entry.sourceHost.hostname}/${entry.sourcePool}";
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
    }
    // lib.optionalAttrs (entry.policy.receiveBandwidthLimit != null) {
      recv.bandwidth_limit.max = entry.policy.receiveBandwidthLimit;
    };

  snapJobs = map (sourcePool: {
    type = "snap";
    name = "snap-${slug sourcePool}";
    filesystems = filesystems "data" // filesystems "escrow";
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
  sourceJobs = concatMap (entry: map (mkSourceJob entry) streams) sourceTargets;
  pullJobs = concatMap (entry: map (mkPullJob entry) streams) incoming;
  jobs = snapJobs ++ sourceJobs ++ pullJobs;
  remoteSourceTargets = filter (entry: !entry.local) sourceTargets;
  ports = concatMap (entry: map (streamPort entry) streams) (
    filter (entry: entry.policy != null) remoteSourceTargets
  );
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
          assertion = builtins.length ports == builtins.length (unique ports);
          message = "Remote zrepl data and escrow source ports MUST NOT collide.";
        }
        {
          assertion = backups == { } || escrowDatasets == [ "rpool/credstore" ];
          message = "The key-escrow registry MUST contain exactly rpool/credstore.";
        }
        {
          assertion = backups == { } || builtins.all (dataset: hasPrefix "rpool/crypt/" dataset) dataDatasets;
          message = "Replicated data datasets MUST be native-encrypted children of rpool/crypt.";
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
        inherit jobs;
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
