# Convention: ZFS Backup (os.zfs-backup)

Standards for ZFS snapshot management, off-site replication, and backup
verification across the keystone fleet. Sanoid handles snapshot creation and
retention; syncoid handles replication. The `keystone.hosts` registry drives
backup topology — each host declares its source pools and target hosts, and
all configuration auto-derives from that single declaration.

## Tool Choice

1. Snapshot creation and retention MUST use **sanoid** — the NixOS built-in
   `services.zfs.autoSnapshot` (zfs-auto-snapshot) MUST NOT be used, as it shares
   the `autosnap_*` naming prefix with sanoid and will conflict on retention pruning.
2. Replication MUST use **syncoid** (from the same project as sanoid) — it natively
   understands sanoid's snapshot naming and supports `--include-snaps=autosnap` for
   selective transfer.
3. Keystone modules MUST NOT configure `services.zfs.autoSnapshot` — the
   `autoSnapshot` option was removed from `keystone.os.storage.zfs` to prevent
   conflicts with sanoid.

## Snapshot Retention

4. Every ZFS host with `zfs.backups` declared in `keystone.hosts` MUST have sanoid
   enabled with at minimum the following retention tiers:
   - **hourly**: 24 snapshots (1 day of hourly coverage)
   - **daily**: 7 snapshots (1 week)
   - **weekly**: 4 snapshots (1 month)
   - **monthly**: 6 snapshots (6 months)
5. Sanoid MUST be configured with `recursive = true` and `processChildrenOnly = true`
   on source pools — this snapshots all child datasets without snapshotting the
   unmounted pool root.
6. Sanoid MUST be configured with `autoprune = true` to enforce retention limits
   automatically.
7. Datasets that contain only immutable or reproducible data (e.g., `/nix`) SHOULD
   set `com.sun:auto-snapshot = false` to avoid wasting snapshot space — sanoid
   honors this ZFS property.

## Backup Topology

8. Backup topology MUST be declared in `keystone.hosts` via `zfs.backups.<pool>.targets`,
   following the `process.enable-by-default` convention (rules 5-7) — one declaration
   drives config for sender (sanoid + syncoid) and receiver (sync users + ZFS delegation).
9. Target strings MUST follow the `<hostKey>:<pool>` format (e.g., `"ocean:ocean"`,
   `"maia:lake"`).
10. A host MAY declare both local and remote replication targets — local targets
    replicate within the same machine to a different pool; remote targets replicate
    over SSH.
11. Every host with user data SHOULD have at least one off-site replication target
    to protect against single-host failure.

## Replication (Syncoid)

12. Syncoid MUST run on an hourly timer (`services.syncoid.interval = "hourly"`)
    to keep replicas current.
13. Syncoid MUST use `--sendoptions w` (raw send) to preserve ZFS native encryption
    end-to-end — the receiving host never sees unencrypted data.
14. Syncoid MUST use `--no-sync-snap` to avoid creating its own snapshots — sanoid
    is the single source of truth for snapshot creation.
15. Syncoid MUST use `--skip-parent` to avoid sending the unmounted pool root dataset.
16. Syncoid MUST exclude non-essential datasets via `--exclude-datasets` with a pattern
    covering at minimum: `nix`, `docker`, `containers`, `images`, `libvirt`.
17. Syncoid SHOULD use `--compress=none` when sending raw-encrypted datasets — the
    data is already incompressible due to encryption.

## SSH Authentication

18. Remote syncoid MUST authenticate using the host's SSH key
    (`/etc/ssh/ssh_host_ed25519_key`), NOT per-user or agent keys.
19. The host's public key (`hostPublicKey` in `keystone.hosts`) MUST be registered
    in the receiver host's sync user `authorized_keys`.
20. The syncoid systemd service MUST copy the host SSH key to a syncoid-readable
    path (e.g., `/run/syncoid/<name>/ssh_key`) via an `ExecStartPre=+` script
    running as root.
21. The systemd service MUST NOT have `InaccessiblePaths` directives that block
    access to the SSH key path — if the NixOS syncoid module's default sandboxing
    conflicts, the service override MUST add `ReadWritePaths` for the key directory.

## Receiver Configuration

22. Receiver hosts MUST auto-create sync users (`<hostname>-sync`) derived from
    `keystone.hosts` entries — no manual user creation in nixos-config.
23. Receiver hosts MUST auto-initialize backup datasets
    (`<targetPool>/backups/<sourceHostname>/<sourcePool>`) and delegate ZFS
    permissions (`receive`, `create`, `mount`, `rollback`, `destroy`) to the
    sync user.
24. Receiver configuration MUST be fully derived from `keystone.hosts` topology —
    adding a new sender host MUST NOT require manual config on the receiver.

## Monitoring & Metrics

See `process.grafana-dashboard-development` for how keystone dashboards consume
these metrics and present backup state on system and host dashboard pages.

25. Every host with backups MUST export Prometheus metrics via the node-exporter
    textfile collector:
    - `zfs_snapshot_newest_age_seconds` — age of the newest snapshot per pool
    - `zfs_snapshot_count` — total snapshot count per pool
    - `zfs_backup_last_exit_code` — exit code of the last syncoid run per target
    - `zfs_backup_last_success_timestamp` — timestamp of the last successful sync
26. The snapshot metrics timer MUST run at least every 5 minutes.
27. Syncoid services MUST write per-target metrics via `ExecStopPost` scripts,
    capturing both success and failure states.

## Verification (ks doctor)

See also `tool.journal-remote` rules 15-17 for the parallel pattern of per-subsystem
`ks doctor` health checks. See `process.grafana-dashboard-development` for the
dashboard requirements that consume the health signals defined here.

28. `ks doctor` MUST check the following ZFS backup health indicators on every host:
    - Sanoid timer is active and not in a failure state
    - Syncoid services have succeeded at least once in the last 2 hours (for hourly targets)
    - No syncoid services are in a `failed` state
    - Snapshot count per dataset is within expected retention bounds
29. `ks doctor` SHOULD report the age of the newest snapshot and flag if it exceeds
    2x the expected interval (e.g., >2 hours for hourly snapshots).
30. `ks doctor` SHOULD verify receiver-side backup health by checking that the
    replicated datasets exist and have recent snapshots.

## Golden Example

A workstation with one local NVMe pool replicated to two remote hosts:

```nix
# keystone/hosts.nix — single topology declaration
ncrmro-workstation = {
  hostname = "ncrmro-workstation";
  hostPublicKey = "ssh-ed25519 AAAAC3...";
  zfs = {
    backups.rpool.targets = [
      "ocean:ocean"    # NAS, same LAN
      "maia:lake"      # Off-site server
    ];
  };
};
```

This single declaration auto-derives:

- **On ncrmro-workstation** (sender): sanoid snapshots rpool children hourly, syncoid
  replicates to both ocean and maia every hour using the host SSH key
- **On ocean** (receiver): `ncrmro-workstation-sync` user created, backup dataset
  `ocean/backups/ncrmro-workstation/rpool` initialized with ZFS delegations
- **On maia** (receiver): same pattern, dataset `lake/backups/ncrmro-workstation/rpool`
- **Metrics**: snapshot age/count exported on all three hosts, syncoid exit codes
  exported on the workstation

Verification after deployment:

```bash
# Check sanoid is snapshotting
systemctl status sanoid.timer
zfs list -t snapshot -r rpool | tail -5

# Check syncoid replication
systemctl status syncoid-rpool-to-ocean.service
systemctl status syncoid-rpool-to-maia.service

# Check receiver-side replicas (from workstation)
ssh root@ocean zfs list -t snapshot -r ocean/backups/ncrmro-workstation | tail -5
ssh root@maia zfs list -t snapshot -r lake/backups/ncrmro-workstation | tail -5

# Check metrics
cat /var/lib/prometheus-node-exporter/zfs_snapshots.prom
cat /var/lib/prometheus-node-exporter/zfs_backup_rpool-to-ocean.prom

# Full fleet check
ks doctor
```

## Related conventions

- `os.systemd-over-activation` — receiver-side dataset initialization and
  permission delegation MUST run as a systemd oneshot ordered after the
  relevant pool-import unit, not as a `system.activationScripts` entry.
  Rule 17g depends on that ordering edge being expressible.
