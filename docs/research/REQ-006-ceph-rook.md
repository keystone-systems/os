# Research: Ceph/Rook + Blob Storage

**Relates to**: REQ-006 (Clusters, FR-006/FR-007)

## Decision

Deploy Rook operator with Ceph on ZFS datasets. Three storage classes: block (RBD), filesystem (CephFS), object (RGW with S3 API).

## Ceph on ZFS

- Use ZFS **datasets (directories)**, NOT zvols for OSDs
- Set `recordsize=64K` to match Ceph object size
- Disable ZFS sync for Ceph datasets (Ceph handles consistency)
- Enable `compression=lz4` and `atime=off`

## Storage Classes

| Class                      | Use Case                          |
| -------------------------- | --------------------------------- |
| `ceph-block` (RBD)         | Databases, stateful apps          |
| `ceph-filesystem` (CephFS) | Shared storage (ReadWriteMany)    |
| `ceph-object` (RGW)        | Backups, logs, container registry |

## Cloud Sync

- ZFS snapshots to S3: `zfs send | zstd | aws s3 cp -`
- Ceph RGW cloud sync: replicate objects to cloud S3 via zone groups
- Lifecycle policies: transition to Glacier after 30 days, expire after 365

## Resource Requirements

- OSDs: 4-8GB RAM each
- MONs: 4GB RAM each (minimum 3 for quorum)
- Network: 10Gbps+ recommended, separate cluster network for OSD traffic

## Key Finding

Both ZFS checksums and Ceph replication provide integrity — ZFS catches local corruption, Ceph replicates across nodes. Minimum 3 nodes for production; single node for development.
