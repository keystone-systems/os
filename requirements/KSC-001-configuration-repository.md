# KSC-001: Configuration Repository

| | |
| --- | --- |
| **ID** | KSC-001 |
| **Title** | Configuration Repository |
| **Status** | Draft |
| **Date** | 2026-07-27 |
| **Owner** | ks.systems/os |

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this
document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## Overview

This document defines the public configuration contract consumed by Keystone
tooling. Existing Nix host registrations are the source of truth. Public
security metadata is registered alongside the host or subject that consumes
it, and tools derive an evaluable projection when they need machine-readable
data.

There is no separately maintained JSON fleet manifest or credential inventory.
Secret values remain in the SOPS repository defined by
[KSS-001](./KSS-001-secrets-repository.md); hardware-resident private keys
remain on their authenticators.

Revision (2026-07-27): the earlier draft's committed public-manifest and
cross-repository inventory model was withdrawn before acceptance. It
duplicated Nix host declarations, recovery paths, storage types, and
credential assignments.

## Requirements

### KSC-001.1: Nix-native discovery

1. The configuration repository MUST expose every managed Linux host as one
   named NixOS configuration from a clean checkout.
2. Host kind, root storage, remote identity, and public credential
   registrations MUST be Nix module data associated with their existing host
   or subject.
3. Tools MUST derive their public machine-readable projection from evaluated
   Nix configuration. A user MUST NOT maintain an equivalent JSON or YAML
   manifest by hand.
4. The evaluated projection MUST expose a contract version.
5. Public evaluation MUST succeed without decrypting a secret, contacting a
   managed host, or requiring a hardware key.
6. Evaluation MUST report a missing or unsupported contract version and any
   missing required option. It MUST NOT search arbitrary files.
7. Evaluation MUST NOT copy plaintext credentials, private identities, PINs,
   recovery values, or decrypted SOPS output into the Nix store, derivation
   arguments, logs, or public projections.

### KSC-001.2: Secrets repository topology

1. A configuration repository MUST choose one of two secrets layouts:
   embedded or external.
2. An embedded layout MUST use the conventional `secrets/` directory at the
   configuration repository root.
3. An external layout MUST use the flake input named `secrets`.
4. A repository containing both an embedded `secrets/` directory and an
   external `secrets` input MUST fail as ambiguous.
5. A repository with neither layout MUST remain evaluable for public-only
   checks but MUST fail operations that require secrets.
6. An operator command MAY accept a local external-repository override;
   committed configuration MUST NOT contain its absolute path.
7. Both layouts MUST expose the same conventional paths and semantics defined
   by `KSS-001`; host modules MUST NOT vary secret references by layout.

### KSC-001.3: Host and root-storage identity

1. Every managed Linux host MUST declare one supported host kind and satisfy
   [KHW-001](./KHW-001-root-storage.md).
2. Root filesystem type, encryption architecture, storage defaults, recovery
   target type, and recovery scalar path MUST be derived from host kind,
   hostname, and root devices.
3. A user MUST NOT configure a filesystem type, encryption disable, LUKS UUID,
   mapping name, recovery scalar path, or secrets-document path.
4. Tool-owned host state MUST record the installed LUKS UUID after formatting.
   Before installation, the UUID MUST be absent; tooling MUST NOT guess it or
   copy it from another host.
5. A host that supports remote checks MUST declare its SSH endpoint, SSH user,
   and pinned SSH host public key.
6. An address or DNS name MUST NOT be treated as host identity without the
   pinned host key.
7. Hosts, stable root device references, installed LUKS UUIDs, and public
   credential identifiers MUST be unique in the evaluated fleet.

### KSC-001.4: Credential registration

1. Every credential that Keystone manages or audits MUST have a stable public
   registration associated with its host, user, service, or relying party.
2. A registration MUST declare the credential class, subject, purpose,
   custody boundary, public reference, and class-specific verification method.
3. Credentials with distinct protocol, relying-party, principal, or proof
   boundaries MUST remain distinct even when they share one physical key or
   applet.
4. An SSH registration MUST distinguish user, host, and automation identities
   and declare its public key or fingerprint, authorized account or
   principals, hardware-backed status, and any logical SOPS reference required
   by an exportable software-key implementation.
5. A PAM/U2F registration MUST declare the local user, PAM consumers,
   authorization mapping, authenticator or credential public reference, and
   required user-presence and user-verification policy.
6. A WebAuthn registration MUST declare the relying-party ID, permitted
   origins, account or subject, credential ID or stable public reference,
   authenticator role, discoverability expectation, and user-verification
   policy.
7. A SOPS/PIV registration MUST declare the public age recipient, key role,
   PIV slot or stable public reference, and secret classes it may decrypt.
8. A registration MUST NOT contain an authenticator private key, PIV or FIDO2
   PIN, PUK, management key, WebAuthn private key, SSH private key, or recovery
   value.
9. Multiple credentials of the same class MUST be allowed when their stable
   identifiers and consumers differ.
10. Configured metadata MUST remain distinct from verification evidence. A
    registration MUST NOT be reported as verified until its class-specific
    proof succeeds.

### KSC-001.5: Downstream implementation

1. `ks.systems/ks-config` MUST maintain lower-level requirements describing
   its host modules, secrets-layout selection, public registrations, derived
   projection, and tool-owned installed state.
2. Each lower-level requirement MUST cite the applicable `KSC-001.M` section.
3. Downstream tests MUST pin machine-verifiable statements using the
   traceability comments required by [the register](./README.md).
4. Migration code MAY translate an existing host registry into these Nix
   options, but it MUST NOT retain a second user-edited credential manifest.
5. Public registration metadata and installed identifiers MUST remain
   separate from encrypted values and authenticator-resident private keys.

## Verification

- Pure Nix evaluation MUST enumerate the configured hosts, their kinds, root
  storage, recovery targets, remote identities, and credential registrations
  without reading secret plaintext.
- Fixtures MUST cover embedded, external, absent, and ambiguous secrets
  layouts and pin `KSC-001.2`.
- Host fixtures MUST cover derived ext4 and ZFS recovery targets, hosts with
  and without installed UUIDs, duplicate identities, and pinned SSH host
  identities.
- Credential fixtures MUST cover multiple SSH, PAM/U2F, SOPS/PIV, and WebAuthn
  registrations, including multiple credentials of the same class.
- Validation MUST reject private-key and private-identity formats in every
  public string value, regardless of the field name containing them.
- A closure scan MUST prove that synthetic recovery values do not appear in
  Nix outputs or evaluation logs.
- Repository review MUST verify downstream requirement traceability until a
  cross-repository linter exists.

## Downstream references

- [KHW-001: Root Storage Hardware](./KHW-001-root-storage.md)
- [KSS-001: Secrets Repository](./KSS-001-secrets-repository.md)
- `ks.systems/ks-config` lower-level requirements
- Keystone host and credential Nix modules
