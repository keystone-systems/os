---
title: NAS (Network Attached Storage)
description: NAS hardware with redundant storage pools across multiple physical devices
---

# NAS (Network Attached Storage)

A NAS usually provides a large shared storage pool distributed across multiple
physical disks, typically HDDs, with redundancy at the pool level.

In Keystone, a common pattern is:

- one root pool for the operating system, and
- one larger data pool for bulk storage.

Example Disko pattern from Maia for a multi-disk data pool:

```nix
{
  disko.devices = {
    # Section 1: define the disks that belong to the shared data pool
    disk.disk2 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD102KFBX-68M95N0_VH12TB1M";
      content = {
        type = "zfs";
        pool = "lake";
      };
    };

    disk.disk3 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD102KFBX-68M95N0_VH12TBYM";
      content = {
        type = "zfs";
        pool = "lake";
      };
    };

    # Section 2: declare the pool topology that ties those disks together
    zpool.lake = {
      type = "zpool";
      mode = "mirror";
      rootFsOptions = {
        mountpoint = "none";
      };
      options.ashift = "12";
    };
  };
}
```

The key idea is that multiple `disk.*` entries point at the same pool name, and
the pool topology is declared by the `zpool.<name>.mode` field.

Example of provisioning a ZFS dataset on that pool:

```nix
{
  disko.devices.zpool.lake = {
    type = "zpool";
    mode = "mirror";
    rootFsOptions = {
      mountpoint = "none";
    };
    options.ashift = "12";

    datasets = {
      # This creates the lake/backups dataset on the lake pool
      backups = {
        type = "zfs_fs";
        mountpoint = "/lake/backups";
        options = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "true";
        };
      };
    };
  };
}
```

That creates a dataset like `lake/backups` and mounts it at `/lake/backups`.

Example `zpool status` output:

```text
❯ zpool status
  # Section 1: large mirrored or parity data pool
  pool: ocean
 state: ONLINE
status: Some supported and requested features are not enabled on the pool.
        The pool can still be used, but some features are unavailable.
action: Enable all features using 'zpool upgrade'. Once this is done,
        the pool may no longer be accessible by software that does not support
        the features. See zpool-features(7) for details.
  scan: scrub repaired 0B in 19:51:33 with 0 errors on Sun Mar  1 22:52:34 2026
config:

        NAME                                          STATE     READ WRITE CKSUM
        ocean                                         ONLINE       0     0     0
          raidz2-0                                    ONLINE       0     0     0
            wwn-0x5000cca2a1d40778-part2              ONLINE       0     0     0
            ata-WDC_WD140EDGZ-11B2DA2_3WG56E1V-part2  ONLINE       0     0     0
            wwn-0x5000cca284c1f856-part2              ONLINE       0     0     0
            wwn-0x5000cca2c2d33656-part2              ONLINE       0     0     0
            wwn-0x5000cca2a1c21d4d-part2              ONLINE       0     0     0

errors: No known data errors

  # Section 2: root pool for the operating system
  pool: rpool
 state: ONLINE
status: Some supported and requested features are not enabled on the pool.
        The pool can still be used, but some features are unavailable.
action: Enable all features using 'zpool upgrade'. Once this is done,
        the pool may no longer be accessible by software that does not support
        the features. See zpool-features(7) for details.
  scan: scrub repaired 0B in 00:07:16 with 0 errors on Sun Mar  1 03:08:21 2026
config:

        NAME                               STATE     READ WRITE CKSUM
        rpool                              ONLINE       0     0     0
          nvme-eui.002538493141c1e8-part2  ONLINE       0     0     0

errors: No known data errors
```
