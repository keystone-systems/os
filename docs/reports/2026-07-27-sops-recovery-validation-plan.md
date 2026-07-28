---
date: 2026-07-27
landing: fast-forward
status: superseded
superseded-by: 2026-07-27-root-storage-recovery-plan.md
---

# SOPS recovery validation plan

> Superseded by
> [Root storage and recovery plan](./2026-07-27-root-storage-recovery-plan.md).
> The replacement derives recovery targets from evaluated Nix host modules and
> removes the separate JSON manifest and inventory.

This plan refines the KS OS v1 SOPS migration into its first executable slice:
an opt-in `ks-secrets recovery-check` command that discovers a consumer's
secrets layout, validates its public host/recovery inventory, asks SOPS to use
the operator's YubiKey, and proves the decrypted recovery credential against
the corresponding live LUKS volume without persisting or printing it.

The primary persona is an engineer preparing or auditing a first Keystone
machine. They understand Git and Nix but should not need to understand SOPS
metadata, age plugins, LUKS keyslots, or SSH stream handling to determine
whether recovery is ready.

## Projected git graphs

Time flows upward. The lowest `○` is the next commit. Every planned line lands
on main as its own commit; the stack is fast-forwarded and never squashed.

### ks.systems/os

```text
◇  v1.0.0 (next)
│
○  feat(secrets): enable recovery audit
│  ── milestone: SOPS recovery audit · flag: sops_recovery_audit ──
○  docs(secrets): document recovery audit
○  test(secrets): pin repository contracts
○  feat(secrets): prove recovery keys against LUKS
○  feat(secrets): validate recovery inventory
○  feat(secrets): discover repository topology
○  docs(requirements): define secrets contract
○  docs(requirements): define ks-config contract
○  docs(reports): plan SOPS recovery validation
│
●  docs: prose review — three realizations consistently    68a33e4  ← main
◇  v1.0.0-rc.4 — 2026-05-21
```

The first three planned commits form the contract PR. Discovery and inventory
form the next PR. Live proof is stacked on discovery, and its contract-pinned
tests and operator documentation land before the explicit default-on flip.
Until that flip, the command requires the `sops_recovery_audit` experimental
gate; explicit preview runs enable it.

### ks.systems/ks-config

This is a planned repository with no history yet. Its lower-level requirements
may choose any Nix implementation that produces the OS-owned contract.

```text
◇  v0.1.0 (next)
│
○  test(manifest): pin the OS repository contract
○  feat(manifest): export secrets and LUKS metadata
○  docs(requirements): define manifest implementation
│  ── milestone: SOPS recovery audit ──
◇  (no history — planned repository)
```

### ks.systems/secrets

This is a planned repository with no history yet. Its fixtures contain only
synthetic credentials and its lower-level requirements own the concrete SOPS
document and recipient schema.

```text
◇  v0.1.0 (next)
│
○  test(recovery): pin the OS secrets contract
○  feat(recovery): add synthetic LUKS fixtures
○  feat(recovery): declare SOPS recovery inventory
○  docs(requirements): define recovery implementation
│  ── milestone: SOPS recovery audit ──
◇  (no history — planned repository)
```

The shared milestone closes only when both downstream repositories trace their
implementation requirements to `KSC-001` or `KSS-001` and the OS checker
passes against each layout.

## Repository ownership

| Repository | Responsibility |
| --- | --- |
| `ks.systems/os` | High-level contracts, `ks-secrets` command, contract fixtures, install-realization proof |
| `ks.systems/ks-config` | Lower-level requirements and Nix implementation producing the fleet manifest |
| `ks.systems/secrets` | Lower-level requirements, SOPS schema, recipient policy, ciphertext, synthetic fixtures |

The reference `ncrmro/ks-config` and `ncrmro/secrets` repositories supply
migration evidence. They do not define the reusable interface. Their existing
agenix compatibility names remain migration inputs rather than being embedded
in the new contracts.

## Public manifest boundary

The checker consumes a versioned JSON value exported by the configuration
flake's `fleetMeta`; it does not scrape `hosts.nix`, `flake.nix`, or arbitrary
secret files. The producer may continue using `hosts.nix` internally.

At minimum, the export supplies:

```json
{
  "schemaVersion": 1,
  "secrets": {
    "layout": "embedded",
    "path": "secrets"
  },
  "hosts": {
    "example": {
      "hostname": "example",
      "machine": {
        "sshTarget": "example.internal",
        "user": "root",
        "hostPublicKey": "ssh-ed25519 PUBLIC"
      },
      "luks": [
        {
          "name": "crypted",
          "uuid": "00000000-0000-0000-0000-000000000000",
          "device": "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000",
          "recoverySecret": "hosts/example/luks/crypted"
        }
      ]
    }
  }
}
```

An external layout replaces `path` with a stable flake-input or repository
reference. A local checkout override is a CLI input and must identify itself
as an override in the result. Absolute workstation paths never enter the
manifest.

## Command flow

The first interface is intentionally narrow:

```text
ks-secrets recovery-check --config <flake-or-path> [--host <name>]
ks-secrets recovery-check --config <flake-or-path> --inventory-only
```

1. Evaluate and schema-check `fleetMeta`.
2. Resolve the embedded or external secrets store without decrypting it.
3. Compare host-volume recovery references with encrypted SOPS inventory.
4. Report every host and volume; unreachable or unmanaged entries are explicit.
5. Match the connected YubiKey recipient reported by `age-plugin-yubikey`
   against the recovery document's public SOPS recipient metadata. A missing
   local age identity stub is reported with setup guidance rather than created
   silently.
6. For a live proof, build an ephemeral `known_hosts` file from the manifest's
   pinned key and establish non-interactive root or `sudo -n` access.
7. Verify the remote block device is LUKS2 and its UUID matches the manifest.
8. Invoke SOPS normally so `age-plugin-yubikey` owns PIN and touch interaction.
9. Stream the exact decrypted bytes through SSH to
   `cryptsetup open --test-passphrase --key-file=-`.
10. Emit a redacted per-volume result and discard all process state.

The command never asks for a PIN or LUKS credential itself. It never puts the
credential in an argument, environment variable, temporary file, Nix value,
or log. Remote privilege prompting is prohibited because it would compete with
the secret stream on standard input.

## Result model

Each host-volume pair ends in one stable state:

- `verified`
- `inventory-missing`
- `recipient-unavailable`
- `decrypt-failed`
- `host-unreachable`
- `host-identity-mismatch`
- `volume-identity-mismatch`
- `privilege-unavailable`
- `key-rejected`
- `not-remotely-checkable`

`verified` means only that the named recovery credential passes LUKS
test-passphrase against the named volume. It is not a reboot test and does not
prove TPM or FIDO2 enrollment.

## Validation ladder

1. Shell formatting, ShellCheck, and argument/parser tests.
2. Pure fixtures for both repository layouts and all invalid inventory states.
3. Process-boundary tests proving a synthetic key never appears in arguments,
   environment, files, logs, or Nix outputs.
4. An install-realization VM with a real LUKS2 volume for accepted/rejected
   keys, UUID mismatch, and non-mutating header comparison.
5. A manual YubiKey PIV/SOPS exercise using synthetic ciphertext.
6. A redacted physical-host recovery audit only after the lower tiers pass.

Tests carry the hard-requirement traceability comments defined in
[`requirements/README.md`](../../requirements/README.md).

## Explicitly out of scope

- Enrolling, changing, or deleting a LUKS credential.
- TPM2 or FIDO2 enrollment and reboot proof.
- Bootstrapping a host SOPS identity.
- Migrating service secrets or replacing agenix declarations.
- Inferring undocumented secret layouts.
- Writing validation state back to either consumer repository.

Those workflows can build on the discovery and plaintext-safe execution
boundary after recovery validation is proven.

## Technical basis

- [SOPS documents stdout-based decryption](https://getsops.io/docs/usage/advanced/)
  as the way to avoid writing decrypted data to disk.
- [`age-plugin-yubikey`](https://github.com/str4d/age-plugin-yubikey#configuration)
  keeps secret key material on the YubiKey while a local identity file tells
  the age client which device credential to use.
- [`cryptsetup open --test-passphrase`](https://gitlab.com/cryptsetup/cryptsetup/-/blob/main/man/cryptsetup-open.8.adoc)
  verifies a passphrase without activating a mapping; `--key-file=-` reads the
  key bytes from standard input.
