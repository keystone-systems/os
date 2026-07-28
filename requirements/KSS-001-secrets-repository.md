# KSS-001: Secrets Repository

| | |
| --- | --- |
| **ID** | KSS-001 |
| **Title** | Secrets Repository |
| **Status** | Draft |
| **Date** | 2026-07-27 |
| **Owner** | ks.systems/os |

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this
document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## Overview

This document defines the encrypted-store and custody contract for
Keystone-managed credentials. Public host and credential registrations live in
the evaluated Nix configuration required by
[KSC-001](./KSC-001-configuration-repository.md). This repository owns secret
payloads, SOPS recipient policy, public ciphertext metadata, and their
validation artifacts.

LUKS recovery uses one conventional SOPS document and derived scalar paths. It
does not use a separate inventory file. Hardware-backed SSH, PIV,
FIDO2/WebAuthn, and PAM/U2F private keys remain with their authenticators and
are not repository payloads.

Revision (2026-07-27): the earlier draft's public `inventory.json` was
withdrawn before acceptance. Its consumer and credential metadata duplicated
the Nix registrations, requiring a shell validator to reconcile two manually
maintained sources.

## Requirements

### KSS-001.1: Conventional LUKS recovery document

1. The selected secrets root from `KSC-001.2` MUST contain the canonical SOPS
   document `luks-recovery.yaml`.
2. Every installed Linux host derived under `KHW-001.5` MUST have exactly one
   encrypted scalar at:

   ```text
   hosts.<hostname>.luks.recovery_secret
   ```

3. A host that has not yet been installed MUST omit that scalar. Its absent
   tool-owned LUKS UUID distinguishes this valid pre-install state from a
   missing credential on an installed host.
4. A user MUST NOT declare a document path, scalar path, credential ID, consumer,
   encoding, or recovery-target type for an individual host.
5. The hostname keys in the document MUST exactly match evaluated NixOS host
   names. Missing installed hosts, unknown hosts, duplicate YAML keys,
   plaintext values, or non-scalar recovery values MUST fail validation.
6. `luks-recovery.yaml` MUST be authenticated SOPS ciphertext and MUST NOT
   contain plaintext recovery values in Git history.
7. Every recovery value MUST be a base64url encoding without padding of at
   least 32 cryptographically random bytes. The enrolled value MUST be the
   scalar's UTF-8 bytes with no trailing newline.
8. Validation MUST derive consumers, expected scalar paths, target types, and
   installed LUKS UUIDs from Nix. It MUST NOT require or generate a second
   public inventory.
9. Automated repository checks MAY enumerate production SOPS documents and
   inspect their public SOPS metadata, paths, keys, and recipients. They MUST
   NOT decrypt production ciphertext.

The canonical document has this public structure, with ciphertext abbreviated:

```yaml
hosts:
  example-host:
    luks:
      recovery_secret: ENC[...]
sops:
  # Standard SOPS metadata; recipient policy is defined below.
```

### KSS-001.2: Recipients and custody

1. `luks-recovery.yaml` MUST include at least one age recipient authorized by
   the downstream recipient policy and backed by a human-present YubiKey PIV
   identity.
2. It MUST also include a tested offline recovery recipient independent of the
   daily YubiKey and every target host.
3. A target host MUST NOT be the sole recipient of its own recovery
   credential.
4. A runtime host recipient SHOULD NOT receive LUKS recovery access unless a
   separate lower-level requirement documents why post-boot decryption is
   necessary.
5. SOPS creation rules MUST contain only public recipients and MUST apply this
   policy only to `luks-recovery.yaml`.
6. After a recipient change, affected documents MUST be rekeyed and
   independently decrypted before a working recipient is removed.
7. Exportable credentials MAY be stored only as SOPS ciphertext under an
   explicit recipient and consumer policy.
8. Hardware-backed private keys and authenticator secrets MUST remain on their
   authenticators. PINs, PUKs, management keys, and biometric material MUST
   NOT be committed, including under SOPS encryption.
9. Recipient changes MUST be independently verified before removing a working
   recipient.

### KSS-001.3: Plaintext boundary

1. Recovery validation MUST ask SOPS and its age plugin to perform YubiKey
   authentication; Keystone tooling MUST NOT collect the PIV PIN itself.
2. Decrypted recovery material MUST travel only through process memory or
   anonymous pipes.
3. Plaintext MUST NOT enter Git, the Nix store, persistent files, environment
   variables, command-line arguments, shell history, logs, screenshots, test
   evidence, or error messages.
4. Shell tracing MUST be disabled around every operation that could expose
   decrypted material.
5. Automated decryption and credential-proof tests MUST use synthetic
   credentials and MUST NOT report those tests as proof of a production
   credential.
6. Public-metadata checks MAY inspect production ciphertext as permitted by
   `KSS-001.1.9`; they MUST NOT decrypt it.
7. Hardware-backed operations MUST use the authenticator's normal protocol
   and prompt path; Keystone MUST neither export its key nor collect its
   authentication secrets.

### KSS-001.4: Credential proof

1. Before consuming a recovery credential, the checker MUST evaluate the
   target from Nix, verify the remote SSH host against its pinned host key, and
   verify the installed target's LUKS UUID.
2. The credential MUST be selected from `luks-recovery.yaml` using the derived
   hostname path and streamed over the verified SSH connection to a
   non-interactive privileged
   `cryptsetup open --test-passphrase --key-file=-` operation.
3. Privilege escalation MUST complete before the secret stream begins and MUST
   be non-interactive. Validation MUST fail if prior authorization is
   unavailable.
4. Validation MUST NOT open a new mapping, enroll or remove a key, change a
   LUKS header, reboot a host, or rely on TPM2 or FIDO2 auto-unlock.
5. A successful test-passphrase result proves only that the stored recovery
   credential unlocks the identified target. It MUST NOT be reported as boot
   proof, TPM2 proof, or FIDO2 proof.
6. Results MUST distinguish configuration, recipient, decryption, host
   identity, reachability, volume identity, privilege, and rejected-credential
   failures.
7. Evidence MUST contain only host, target, requirement IDs, timestamp,
   outcome, and redacted diagnostics.
8. Every enabled hardware credential MUST be proven through its actual
   protocol against its declared consumer.
9. Proof of one credential, protocol, account, service, or relying party MUST
   NOT prove another.
10. Checks MUST be read-only except for protocol-required counters and audit
    events.
11. Enrollment, rotation, revocation, recovery, and destructive reset MUST be
    explicit workflows separate from verification.

### KSS-001.5: Downstream implementation

1. `ks.systems/secrets` MUST maintain lower-level requirements describing its
   SOPS creation rules, recipient policy, ciphertext checks, and synthetic
   fixtures.
2. Each lower-level requirement MUST cite the applicable `KSS-001.M` section.
3. An embedded secrets directory MUST implement the same contract and
   separation as an external secrets repository.
4. Lower-level requirements MUST define the storage location and proof
   procedure for each supported non-LUKS credential class, including whether
   each value is public, SOPS-encrypted, hardware-resident, or held only in
   offline recovery custody.
5. Other SOPS documents MAY exist for credentials that require a narrower
   recipient set, but LUKS recovery values MUST remain consolidated in the
   one canonical `luks-recovery.yaml` document.

## Verification

- Synthetic embedded and external repositories MUST pin `KSS-001.1` and
  `KSS-001.2`.
- Validation fixtures MUST cover pre-install hosts, missing installed hosts,
  undeclared host keys, duplicate YAML keys, plaintext, invalid SOPS metadata,
  and unexpected recipients.
- Repository scans MUST reject production SOPS documents stored outside
  conventionally or explicitly supported paths, without decrypting them.
- Pipe and process inspection tests MUST prove the synthetic recovery value is
  absent from arguments, environment, files, logs, and Nix outputs.
- An install-realization VM with a real LUKS2 volume MUST exercise UUID
  matching and `--test-passphrase` success and failure.
- A physical YubiKey exercise MUST prove PIV-backed SOPS decryption while
  recording only redacted evidence; CI MAY use a software age identity for the
  same command boundary.
- SSH fixtures MUST prove fresh-challenge signatures and pinned host identity.
- PAM/U2F and WebAuthn verification MUST exercise their actual protocol
  boundaries; metadata inspection alone is insufficient.
- Automated tests MUST NOT treat proof from one security-key applet as proof
  for another.
- Repository review MUST verify downstream requirement traceability until a
  cross-repository linter exists.

## Downstream references

- [KHW-001: Root Storage Hardware](./KHW-001-root-storage.md)
- [KSC-001: Configuration Repository](./KSC-001-configuration-repository.md)
- `ks.systems/secrets` lower-level requirements
- SOPS creation rules and `luks-recovery.yaml`
