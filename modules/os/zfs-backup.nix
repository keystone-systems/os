# ZFS Backup Module
#
# Auto-derives sanoid snapshot management, syncoid replication, receiver
# user/dataset setup, and Prometheus metrics from keystone.hosts ZFS
# backup topology.
#
# See conventions/os.zfs-backup.md (30 rules)
# Follows the journal-remote.nix pattern of auto-deriving from keystone.hosts.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  hostname = config.networking.hostName;
  hosts = config.keystone.hosts;

  # Find this host's entry in the registry
  currentHostEntry = findFirst (h: h.hostname == hostname) null (attrValues hosts);

  # Sender: does this host declare ZFS backups?
  hasBackups =
    currentHostEntry != null && currentHostEntry.zfs != null && currentHostEntry.zfs.backups != { };

  backupDecls = if hasBackups then currentHostEntry.zfs.backups else { };
  backedUpPools = attrNames backupDecls;

  # Parse "host:pool" target string (convention rule 9)
  parseTarget =
    targetStr:
    let
      parts = splitString ":" targetStr;
    in
    {
      hostKey = elemAt parts 0;
      pool = elemAt parts 1;
    };

  # Validate target string format (exactly "host:pool")
  isValidTarget =
    targetStr:
    let
      parts = splitString ":" targetStr;
    in
    length parts == 2 && elemAt parts 0 != "" && elemAt parts 1 != "";

  # All target strings across all pools (for assertions)
  allTargetStrings = concatMap (pc: pc.targets) (attrValues backupDecls);

  # Build flat list of syncoid command definitions
  syncoidCmds =
    let
      mkCommands =
        sourcePool: poolCfg:
        concatMap (
          target:
          let
            parsed = parseTarget target;
            targetHost = hosts.${parsed.hostKey} or null;
            sshTarget = if targetHost.sshTarget != null then targetHost.sshTarget else targetHost.hostname;
            name = "${sourcePool}-to-${parsed.hostKey}";
            keyDir = "/run/syncoid/${name}";
          in
          if targetHost != null then
            [
              (nameValuePair name {
                source = sourcePool;
                # convention rules 13-17: raw send, no-sync-snap, skip-parent, exclude, compress
                target = "${hostname}-sync@${sshTarget}:${parsed.pool}/backups/${hostname}/${sourcePool}";
                sendOptions = "w";
                extraArgs = [
                  "--no-sync-snap"
                  "--skip-parent"
                  "--exclude-datasets=nix|docker|containers|images|libvirt"
                  "--compress=none"
                  "--sshkey"
                  "${keyDir}/ssh_key"
                ];
                # convention rules 18-21: SSH key handling with sandbox fix
                service = {
                  serviceConfig = {
                    ExecStartPre = [
                      "+${pkgs.coreutils}/bin/install -d -m 0700 ${keyDir}"
                      "+${pkgs.coreutils}/bin/install -m 0600 /etc/ssh/ssh_host_ed25519_key ${keyDir}/ssh_key"
                    ];
                    ReadWritePaths = [ keyDir ];
                    ExecStopPost = [ "${backupMetricsScript} ${name}" ];
                  };
                };
              })
            ]
          else
            [ ]
        ) poolCfg.targets;
    in
    flatten (mapAttrsToList mkCommands backupDecls);

  # Receiver: find all incoming backup connections targeting this host
  incomingBackups =
    let
      perHost = mapAttrsToList (
        _name: hostCfg:
        if hostCfg.zfs != null then
          flatten (
            mapAttrsToList (
              sourcePool: poolCfg:
              map (
                target:
                let
                  parsed = parseTarget target;
                  targetHostEntry = hosts.${parsed.hostKey} or null;
                in
                if targetHostEntry != null && targetHostEntry.hostname == hostname then
                  {
                    senderHostname = hostCfg.hostname;
                    senderPublicKey = hostCfg.hostPublicKey;
                    inherit sourcePool;
                    targetPool = parsed.pool;
                  }
                else
                  null
              ) poolCfg.targets
            ) hostCfg.zfs.backups
          )
        else
          [ ]
      ) hosts;
    in
    filter (x: x != null) (flatten perHost);

  hasIncomingBackups = incomingBackups != [ ];
  uniqueSenderHostnames = unique (map (b: b.senderHostname) incomingBackups);

  # ZFS binary (matches kernel module version)
  zfsBin = "${config.boot.zfs.package}/bin/zfs";

  # Metrics: snapshot age/count exporter (convention rules 25-26)
  snapshotMetricsScript = pkgs.writeShellScript "zfs-snapshot-metrics" ''
    outfile="/var/lib/prometheus-node-exporter/zfs_snapshots.prom"
    tmpfile="''${outfile}.tmp.$$"

    {
    ${concatMapStringsSep "\n" (pool: ''
      count=$(${zfsBin} list -t snapshot -r ${escapeShellArg pool} -H -o name 2>/dev/null | wc -l || echo 0)
      newest=$(${zfsBin} list -t snapshot -r ${escapeShellArg pool} -H -o creation -s creation 2>/dev/null | tail -1)
      if [ -n "$newest" ]; then
        newest_epoch=$(${pkgs.coreutils}/bin/date -d "$newest" +%s 2>/dev/null || echo 0)
        now=$(${pkgs.coreutils}/bin/date +%s)
        age=$((now - newest_epoch))
      else
        age=-1
      fi
      echo "zfs_snapshot_count{pool=\"${pool}\"} $count"
      echo "zfs_snapshot_newest_age_seconds{pool=\"${pool}\"} $age"
    '') backedUpPools}
    } > "$tmpfile"

    mv "$tmpfile" "$outfile"
  '';

  # Metrics: per-target backup exit code/timestamp (convention rule 27)
  backupMetricsScript = pkgs.writeShellScript "zfs-backup-metrics" ''
    name="$1"
    exit_status="''${EXIT_STATUS:-1}"
    outfile="/var/lib/prometheus-node-exporter/zfs_backup_''${name}.prom"
    tmpfile="''${outfile}.tmp.$$"

    {
      echo "zfs_backup_last_exit_code{target=\"$name\"} $exit_status"
      if [ "$exit_status" = "0" ]; then
        echo "zfs_backup_last_success_timestamp{target=\"$name\"} $(${pkgs.coreutils}/bin/date +%s)"
      elif [ -f "$outfile" ]; then
        # Preserve last success timestamp on failure
        ${pkgs.gnugrep}/bin/grep -F "zfs_backup_last_success_timestamp" "$outfile" || true
      fi
    } > "$tmpfile"

    mv "$tmpfile" "$outfile"
  '';
in
{
  config = mkIf osCfg.enable (mkMerge [
    # --- Assertions ---
    {
      assertions =
        # Sender assertions: validate target format
        (optionals hasBackups (
          map (target: {
            assertion = isValidTarget target;
            message = "ZFS backup target '${target}' is malformed. Must be 'host:pool' format (e.g., 'ocean:ocean').";
          }) allTargetStrings
        ))
        ++
          # Sender assertions: all backup targets must reference valid hosts
          (optionals hasBackups (
            map (
              target:
              let
                parsed = parseTarget target;
              in
              {
                assertion = !isValidTarget target || hasAttr parsed.hostKey hosts;
                message = "ZFS backup target '${target}' references unknown host '${parsed.hostKey}'. It must exist in keystone.hosts.";
              }
            ) allTargetStrings
          ))
        ++ [
          # ZFS backups require ZFS storage on the sender
          {
            assertion = !hasBackups || osCfg.storage.type == "zfs";
            message = "ZFS backups are declared for this host but storage type is '${osCfg.storage.type}'. ZFS backups require storage.type = \"zfs\".";
          }
          # ZFS incoming backups require ZFS storage on the receiver
          {
            assertion = !hasIncomingBackups || osCfg.storage.type == "zfs";
            message = "ZFS incoming backups target this host but storage type is '${osCfg.storage.type}'. Receiving ZFS backups requires storage.type = \"zfs\".";
          }
        ]
        ++
          # Receiver assertions: senders must have hostPublicKey for SSH auth
          (optionals hasIncomingBackups (
            map (backup: {
              assertion = backup.senderPublicKey != null;
              message = "ZFS backup sender '${backup.senderHostname}' targets this host but has no hostPublicKey set in keystone.hosts. SSH authentication requires hostPublicKey.";
            }) incomingBackups
          ));
    }

    # --- Sender: sanoid snapshot management (convention rules 4-7) ---
    (mkIf hasBackups {
      services.sanoid = {
        enable = true;
        datasets = mapAttrs (_pool: _poolCfg: {
          recursive = true;
          process_children_only = true;
          autoprune = true;
          autosnap = true;
          hourly = 24;
          daily = 7;
          weekly = 4;
          monthly = 6;
        }) backupDecls;
      };
    })

    # --- Sender: syncoid replication (convention rules 12-21) ---
    (mkIf hasBackups {
      services.syncoid = {
        enable = true;
        interval = "hourly";
        commands = builtins.listToAttrs syncoidCmds;
      };
    })

    # --- Sender: snapshot metrics timer (convention rules 25-26) ---
    (mkIf hasBackups {
      systemd.services.zfs-snapshot-metrics = {
        description = "Export ZFS snapshot metrics for Prometheus";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = snapshotMetricsScript;
        };
      };

      systemd.timers.zfs-snapshot-metrics = {
        description = "ZFS snapshot metrics exporter (every 5 min)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:0/5";
          Persistent = true;
        };
      };
    })

    # --- Ensure metrics directory exists ---
    (mkIf (hasBackups || hasIncomingBackups) {
      systemd.tmpfiles.rules = [
        "d /var/lib/prometheus-node-exporter 0755 root root -"
      ];
    })

    # --- Receiver: sync users (convention rules 22, 19) ---
    (mkIf hasIncomingBackups {
      users.users = builtins.listToAttrs (
        map (
          senderHostname:
          let
            backup = findFirst (b: b.senderHostname == senderHostname) null incomingBackups;
          in
          nameValuePair "${senderHostname}-sync" {
            isSystemUser = true;
            group = "${senderHostname}-sync";
            home = "/var/empty";
            shell = "${pkgs.bash}/bin/bash";
            openssh.authorizedKeys.keys = optional (
              backup != null && backup.senderPublicKey != null
            ) backup.senderPublicKey;
          }
        ) uniqueSenderHostnames
      );

      users.groups = builtins.listToAttrs (
        map (senderHostname: nameValuePair "${senderHostname}-sync" { }) uniqueSenderHostnames
      );
    })

    # --- Receiver: ZFS dataset initialization and permission delegation (convention rules 23-24) ---
    (mkIf hasIncomingBackups {
      system.activationScripts.zfsBackupDatasets = {
        deps = [ "users" ];
        text = concatStringsSep "\n" (
          map (backup: ''
            # Create backup dataset hierarchy if it doesn't exist
            if ! ${zfsBin} list ${escapeShellArg "${backup.targetPool}/backups/${backup.senderHostname}/${backup.sourcePool}"} >/dev/null 2>&1; then
              ${zfsBin} create -p ${escapeShellArg "${backup.targetPool}/backups/${backup.senderHostname}/${backup.sourcePool}"} || true
            fi
            # Delegate ZFS permissions to sync user
            ${zfsBin} allow -u ${escapeShellArg "${backup.senderHostname}-sync"} receive,create,mount,rollback,destroy ${escapeShellArg "${backup.targetPool}/backups/${backup.senderHostname}"} || true
          '') incomingBackups
        );
      };
    })
  ]);
}
