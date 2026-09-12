# REQ-034: Rootless Zvol-Backed Workstation VMs

Keystone workstation users run local `qemu:///session` VMs on sparse ZFS
volumes without a runtime privileged broker. System activation establishes the
storage boundary; VM lifecycle operations run as the invoking user.

Key words: RFC 2119 (MUST, MUST NOT, SHOULD, SHOULD NOT, MAY).

## Platform boundary

**REQ-034.1** A ZFS desktop with a local session client MUST default to zvol
storage below `rpool/crypt/vms`; incompatible explicit enablement MUST fail
evaluation. The subtree MUST inherit native encryption from `rpool/crypt`.

**REQ-034.2** The parent, `users`, and each Keystone user's parent MUST be
managed `ephemeral` datasets with no mountpoint, `canmount=off`, and automatic
snapshots disabled. A 500 GiB quota MUST bound the shared subtree by default.

**REQ-034.3** Each managed user MUST receive exactly `create`, `mount`,
`destroy`, `snapshot`, `rollback`, `volsize`, `volblocksize`, `compression`,
`snapdev`, `volmode`, and `userprop` delegation on their own parent. Keystone
MUST NOT delegate encryption keys, send/receive, quota mutation, or parent
destruction. `mount` is an OpenZFS authorization prerequisite; it does not
grant access to the global Linux mount namespace.

**REQ-034.4** A udev rule MUST use OpenZFS `zvol_id` to make only
`rpool/crypt/vms/users/<user>/*` block devices owner-readable and writable by
that user (`0600`). Other users' devices and unrelated zvols MUST remain
inaccessible.

## Lifecycle

**REQ-034.5** A VM MUST use
`rpool/crypt/vms/users/<user>/<vm>/disk0`: a non-mounted filesystem is its
checkpoint boundary and sparse raw zvol children are disks. NVRAM and swtpm
state MUST remain in normal user VM state.

**REQ-034.6** Default domain XML MUST expose zvols as raw block devices with
`cache=none`, `io=native`, and `discard=unmap`. Explicit `--disk-path` MUST
retain qcow2 compatibility.

**REQ-034.7** Snapshot, restore, list, post-install checkpoint, and reset MUST
dispatch by the domain's disk backend. Snapshot and rollback MUST require a
stopped domain. VM and snapshot names MUST be validated before constructing a
dataset or invoking ZFS.

**REQ-034.8** Legacy qcow2 cleanup MUST be dry-run by default, require an
explicit apply flag, reject active domains, and reject files outside recognized
user VM directories. It MUST NOT run automatically.

**REQ-034.9** Migration and cleanup MUST preserve existing zvols and all
`autosnap_*`, `migration-*`, manual, and `zrepl_*` snapshots. REQ-033 snapshot
and replication exclusion for the `ephemeral` class applies to this subtree.

## Acceptance

**REQ-034.10** Evaluation tests MUST cover defaults, overrides, invalid storage
and URI combinations, datasets, exact delegation, udev isolation, and quota.
CLI tests MUST cover file/block XML, name validation, backend dispatch, stopped
domain guards, and qcow2 cleanup.

**REQ-034.11** A NixOS VM test MUST prove two-user lifecycle and isolation,
device ownership across reboot, an unrelated zvol remaining root-owned, session
libvirt I/O, rollback, quota enforcement, and exclusion from scheduled
snapshots. Workstation acceptance MUST additionally build the exact closure and
complete one rootless lifecycle smoke test without sudo.
