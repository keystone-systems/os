---
date: 2026-07-27
landing: fast-forward
status: draft
supersedes:
  - 2026-07-27-sops-recovery-validation-plan.md
  - 2026-07-27-sops-credential-validation-addendum.md
---

# Root storage and recovery plan

This revision removes the hand-maintained JSON manifest and secrets inventory
from the credential-audit design. Evaluated Nix host modules hold public
configuration; the selected secrets root holds encrypted values. LUKS recovery
uses one conventional `luks-recovery.yaml` document with one derived scalar
path per installed Linux host.

The first implementation slice defines root storage because the recovery
target depends on it. Host kind selects ext4/LUKS or ZFS with a LUKS
credential-store zvol. The operator supplies stable root device IDs and may
override the ZFS mode. Encryption, filesystem type, recovery paths, and on-disk
names are not user options.

## Contract surface

The user-facing storage declaration is:

```nix
storage.devices = [
  "/dev/disk/by-id/..."
];

# Optional on workstation and server hosts.
storage.mode = "raidz2";
```

The derived defaults are:

| Host kind | One root disk | Multiple root disks |
| --- | --- | --- |
| laptop, edge device, thin client | ext4 in LUKS2 | rejected |
| workstation | ZFS `single` | ZFS `stripe` |
| server | ZFS `single` | ZFS `mirror` |

Workstation and server hosts may override a multi-disk root with `stripe`,
`mirror`, `raidz1`, `raidz2`, or `raidz3` when enough disks are present.
Version 1 uses one root vdev containing every declared root disk. Separate data
pools are not part of this contract.

Each Linux host has one recovery target regardless of disk count:

- ext4 hosts: the root LUKS2 container;
- ZFS hosts: `/dev/zvol/rpool/credstore`, which contains the key used to unlock
  the native encrypted `rpool/crypt` hierarchy.

The recovery scalar path is always
`hosts.<hostname>.luks.recovery_secret` inside `luks-recovery.yaml`. The
installer records the resulting LUKS UUID as tool-owned host state after
formatting. The user does not supply either value.

Public SSH, PAM/U2F, SOPS/PIV, and WebAuthn registrations remain Nix module
data. Hardware-resident private keys, authenticator secrets, PINs, PUKs, and
management keys remain outside Git and SOPS.

## Repository ownership

| Repository | Responsibility |
| --- | --- |
| `ks.systems/os` | High-level contracts, reusable modules, installer, derived audit projection, and non-mutating proof tooling |
| `ks.systems/ks-config` | Host kinds, stable root devices, optional ZFS modes, public credential registrations, and installed host state |
| `ks.systems/secrets` | `luks-recovery.yaml`, SOPS recipient policy, other narrowly scoped ciphertext, and synthetic fixtures |

An embedded layout uses `ks-config/secrets/`. A split layout uses the
`ks-config` flake input named `secrets`. Both expose the same files and scalar
paths.

## Projected git graph

Time flows upward. Filled nodes are implemented in the current worktree; hashes
identify committed nodes. Open nodes remain implementation work.

```text
◇  v1.0.0
│
○  feat(setup): guide recovery generation and hardware enrollment
○  test(storage): boot ext4, stripe, mirror, and RAIDZ2 install realizations
○  feat(storage): derive encrypted root layouts from host kind
○  test(secrets): prove derived recovery targets with synthetic ciphertext
○  feat(secrets): audit conventional recovery values
●  docs(requirements): define root storage and simplify recovery contracts
│
●  docs(reports): expand credential audit scope                 4b36fb1
●  docs(requirements): broaden credential contracts             7c65230
●  docs(requirements): define secrets contract                  2a9cea8
●  docs(requirements): define ks-config contract                008d148
●  docs(reports): plan SOPS recovery validation                 7e331a4
│
●  main                                                         68a33e4
```

## Validation order

1. Pure evaluation derives filesystem type, ZFS mode, recovery target, and
   recovery scalar path from host kind, hostname, and root device count.
2. Evaluation rejects empty or duplicate devices, mutable physical device
   names, multiple ext4 root disks, and invalid ZFS mode counts.
3. Tests use synthetic embedded and external secrets repositories to verify
   conventional discovery and public SOPS metadata without decrypting
   production ciphertext.
4. Install realizations boot one-disk ext4, two-disk workstation stripe,
   two-disk server mirror, and four-disk server RAIDZ2 roots.
5. A synthetic recovery key passes `cryptsetup --test-passphrase` against the
   derived LUKS target without changing its header.
6. Physical-host proofs occur only through separately authorized workflows.
   They must preserve existing password, FIDO2, TPM2, and recovery slots.

## Out of scope

- Separate data pools, arbitrary ZFS vdev graphs, cache, log, and spare devices.
- Disabling root encryption or selecting ext4 versus ZFS directly.
- Hand-authored LUKS UUIDs, recovery references, or credential inventories.
- Decrypting production ciphertext in automated tests.
- Changing a physical host's password, keyslots, or boot state as part of this
  contract change.
