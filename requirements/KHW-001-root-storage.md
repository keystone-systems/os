# KHW-001: Root Storage Hardware

| | |
| --- | --- |
| **ID** | KHW-001 |
| **Title** | Root Storage Hardware |
| **Status** | Draft |
| **Date** | 2026-07-27 |
| **Owner** | ks.systems/os |

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this
document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## Overview

This document defines the Keystone Linux root-storage contract. Host kind
determines the filesystem and encryption architecture. The operator declares
physical root disks and may override the ZFS topology mode. Keystone derives
the filesystem type, encryption, on-disk names, and recovery scalar path.

The contract covers only the disks that make up the bootable root filesystem.
Additional ZFS pools, application disks, removable media, and network storage
are outside its scope. For example, a server may have a five-disk RAIDZ2 data
pool without those disks becoming part of its root-storage declaration.

## Requirements

### KHW-001.1: Host-kind policy

1. Keystone MUST derive the root-storage implementation from the Linux host
   kind.
2. Laptop, edge-device, and thin-client hosts MUST use ext4 inside one LUKS2
   container.
3. Workstation and server hosts MUST use a ZFS root pool with native encrypted
   root datasets and the LUKS2 credential-store architecture defined by
   `KHW-001.5`.
4. Root encryption MUST be enabled and MUST NOT have a user-facing disable
   option.
5. A user MUST NOT select `ext4` or `zfs` directly.
6. macOS hosts and non-root storage are outside this contract.

### KHW-001.2: Root devices

1. Every Linux host MUST declare `storage.devices` with at least one root
   device.
2. A physical installation MUST use unique, stable
   `/dev/disk/by-id/...` references. Mutable kernel names such as `/dev/sda`
   and `/dev/nvme0n1` MUST be rejected.
3. An ext4 host MUST declare exactly one root device. Evaluation MUST reject an
   ext4 host with multiple root devices.
4. A ZFS host MUST accept one or more root devices.
5. Every declared device MUST be a member of the root layout. The root
   declaration MUST NOT contain spare, cache, log, or separate data-pool
   devices.
6. Before modifying storage, the installer MUST resolve and display every
   selected device and require explicit confirmation that all listed devices
   may be erased.
7. Virtual-machine and image tests MAY replace physical by-id paths with
   deterministic virtual devices while preserving the declared device count.

### KHW-001.3: ZFS topology

1. A one-device ZFS root MUST use `single`.
2. A workstation ZFS root with more than one device MUST default to `stripe`
   (RAID0).
3. A server ZFS root with more than one device MUST default to `mirror`
   (RAID1, including an N-way mirror when more than two devices are supplied).
4. A user MAY set `storage.mode` on a workstation or server with multiple root
   devices to override the default.
5. The supported modes and minimum device counts MUST be:

   | Mode | Minimum devices | Root vdev |
   | --- | ---: | --- |
   | `single` | 1 | one device only |
   | `stripe` | 2 | all devices striped |
   | `mirror` | 2 | all devices in one mirror |
   | `raidz1` | 3 | one RAIDZ1 vdev |
   | `raidz2` | 4 | one RAIDZ2 vdev |
   | `raidz3` | 5 | one RAIDZ3 vdev |

6. `single` with more than one device, a mode below its minimum device count,
   an unknown mode, a mode on a one-device root, or any mode override on an
   ext4 host MUST fail evaluation.
7. Version 1 MUST treat all declared root devices as one vdev. Arbitrary
   multi-vdev root topology is outside scope.
8. A stripe MUST be described as having no disk-failure tolerance. A mirror or
   RAIDZ mode MUST NOT be described as a backup.

### KHW-001.4: Boot layout

1. Every root device MUST have a GPT layout and an EFI System Partition.
2. Bootloader installation and updates MUST write the required boot files to
   every declared root device so that a redundant topology remains bootable
   after the first enumerated disk fails.
3. EFI System Partitions and any partition metadata required before unlock MAY
   remain unencrypted; the root filesystem and its persistent operating-system
   data MUST follow `KHW-001.5`.
4. Device, partition, mapping, pool, dataset, and mount names MUST be
   deterministic conventions derived from the host and disk index. They MUST
   NOT be additional user options.

### KHW-001.5: Encryption and recovery target

1. An ext4 host MUST use one LUKS2 boundary containing the root filesystem and
   any persistent swap used for hibernation.
2. A ZFS host MUST import an unencrypted `rpool`, unlock the conventional
   `/dev/zvol/rpool/credstore` LUKS2 volume, and use the exact key material
   stored inside that credential store to load the native encryption key for
   `rpool/crypt`.
3. A ZFS host's persistent root datasets MUST descend from the encrypted
   `rpool/crypt` hierarchy. The credential-store zvol MUST remain outside that
   encrypted hierarchy to avoid a circular unlock dependency.
4. Regardless of root device count, each Linux host MUST expose exactly one
   LUKS recovery target: the ext4 root container or the ZFS credential-store
   volume.
5. The recovery target's scalar path in `luks-recovery.yaml` MUST be
   `hosts.<hostname>.luks.recovery_secret`; users MUST NOT configure that path,
   the document path, a mapping name, or a recovery-target type.
6. The installer MUST generate the recovery value outside the Nix store,
   encrypt it immediately into the selected secrets repository, and enroll the
   same exact bytes in the recovery target.
7. The installer MUST define and preserve the credential byte encoding,
   including whether a trailing newline is present.
8. After formatting, the installer MUST write the discovered LUKS UUID to the
   downstream-defined tool-owned Nix state field and record that repository
   change in the setup transaction. A rerun with the same UUID MUST be a no-op;
   a different existing UUID MUST fail rather than be overwritten.
9. The target LUKS UUID MUST NOT be a user-authored option.
10. The recovery slot MUST be independent of the ordinary password fallback.
   Installing, evaluating, or auditing a host MUST NOT silently change that
   password or enroll, remove, or replace TPM2 or FIDO2 slots.
11. Recovery-key verification MUST be non-mutating and follow
    [KSS-001](./KSS-001-secrets-repository.md).

### KHW-001.6: User interface

1. The user-facing root-storage options MUST be limited to:

   ```nix
   storage.devices = [
     "/dev/disk/by-id/..."
   ];

   # Optional, and valid only for workstation/server ZFS roots.
   storage.mode = "raidz2";
   ```

2. Host kind MUST be declared by the existing host registration rather than
   repeated under storage.
3. Generated templates MUST omit `storage.mode` when the host-kind and device
   count defaults are desired.
4. Validation errors MUST name the host, derived storage implementation,
   selected mode, device count, and applicable requirement without exposing
   secret material.

## Verification

- Evaluation tests MUST cover the derived ext4 and ZFS implementations for
  every supported Linux host kind and pin `KHW-001.1`.
- Evaluation tests MUST accept one or many ZFS root devices and reject mutable,
  duplicate, empty, and multi-device ext4 declarations while pinning
  `KHW-001.2`.
- Mode tests MUST cover one-device `single`, multi-device workstation
  `stripe`, multi-device server `mirror`, each valid override, and every
  minimum-count failure while pinning `KHW-001.3`.
- Install realizations MUST cover a one-disk ext4 root, a two-disk workstation
  stripe, a two-disk server mirror, and a four-disk server RAIDZ2 root.
- A multi-disk boot test MUST prove that every root disk receives an EFI System
  Partition and bootloader payload.
- Recovery evaluation MUST produce exactly one conventional recovery target
  and scalar path for each Linux host without a hand-maintained inventory.
- Recovery proof tests MUST use synthetic credentials. A physical-host proof
  requires separately authorized hardware interaction and MUST NOT alter
  existing password, FIDO2, TPM2, or recovery slots.

## Downstream references

- [KSC-001: Configuration Repository](./KSC-001-configuration-repository.md)
- [KSS-001: Secrets Repository](./KSS-001-secrets-repository.md)
- Keystone host-kind constructors and root-storage module
- Keystone installer and install realization
