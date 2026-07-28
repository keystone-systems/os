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
7. A software SSH private key, SSH passphrase, recovery code, or other
   exportable credential MAY be stored only as SOPS ciphertext under a
   separately scoped recipient policy with explicit consumers, rotation, and
   rollback.
8. A hardware-backed SSH private key, PIV private key, FIDO2/WebAuthn private
   key, or authenticator secret MUST remain with its authenticator or
   credential provider and MUST NOT be copied into this repository.
9. FIDO2 and PIV PINs, PUKs, management keys, biometric templates, and
   WebAuthn private-key material MUST NOT be committed, including under SOPS
   encryption.
10. A security key's PIV decryption authority, FIDO2/PAM authority, WebAuthn
    registrations, and SSH signing authority MUST be treated as independent
    credentials even when they share a physical key or serial number.
11. Procedures for a lost or compromised credential MUST identify every
    affected consumer and MUST NOT claim that unrelated applets or
    registrations were revoked without class-specific evidence.
12. An offline recovery-recipient proof MUST decrypt a synthetic canary and
    record the recipient identifier, timestamp, outcome, and redacted evidence.
    The downstream recipient policy MUST define how recent that proof must be.

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
7. A proof involving a hardware-backed private key MUST exercise its signing,
   assertion, HMAC, or decryption interface and MUST NOT attempt to export the
   key.
8. Keystone tooling MUST NOT collect a FIDO2 PIN, PIV PIN, PAM password,
   biometric, WebAuthn user-verification input, or SSH private-key passphrase
   when the owning authenticator, PAM stack, SSH agent, or client is
   responsible for that interaction.

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
8. An SSH signing identity MUST prove possession by signing a fresh challenge
   and verifying it against the declared public key. An SSH authentication
   check MAY also verify the declared account and principal policy
   without granting an interactive command.
9. An SSH host identity MUST be verified against its pinned host key and MUST
   NOT be inferred from an address, DNS name, or successful connection alone.
10. A PAM/U2F proof MUST exercise the declared PAM service through a real local
    authentication transaction with its required user-presence and
    user-verification policy.
11. A WebAuthn proof MUST complete an assertion for the declared relying-party
    ID and permitted origin and verify the expected credential, user presence,
    and user verification.
12. A SOPS/PIV proof MUST decrypt a synthetic canary with the declared
    recipient while leaving production ciphertext unopened.
13. A successful proof for one applet, SSH principal, PAM service, or WebAuthn
    relying party MUST NOT count as proof for another.
14. Checks MUST NOT alter enrollment, authorization policy, key material, or
    recovery slots. Protocol-required counters and audit events MAY change and
    MUST be documented.
15. Enrollment, registration, rotation, revocation, recovery, and destructive
    reset MUST be separate workflows, each requiring explicit authorization.

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
