---
date: 2026-07-27
landing: fast-forward
status: superseded
amends: 2026-07-27-sops-recovery-validation-plan.md
superseded-by: 2026-07-27-root-storage-recovery-plan.md
---

# SOPS credential validation plan — scope addendum

> Superseded by
> [Root storage and recovery plan](./2026-07-27-root-storage-recovery-plan.md).
> The replacement keeps public credential registrations in Nix and removes the
> separate JSON inventory.

The original recovery-validation report correctly defines the first
non-mutating proof, but scopes the repository contracts too narrowly around
LUKS. This addendum broadens the durable contract and `ks-secrets` architecture
to all Keystone-managed security credentials. LUKS recovery remains the first
implemented vertical slice; it no longer defines the whole inventory.

## Credential boundaries

One physical YubiKey may carry several unrelated credentials. Keystone must
inventory and prove each independently.

| Class | Public configuration or inventory | Secret or private custody | Required proof |
| --- | --- | --- | --- |
| LUKS recovery | Host, volume, LUKS UUID, secret reference | SOPS ciphertext plus independent offline recovery | `cryptsetup --test-passphrase`; a separate isolated reboot proves boot recovery |
| LUKS FIDO2 | LUKS token metadata, key role, UP/UV policy | FIDO2 HMAC secret remains on authenticator | Reboot with TPM absent, required PIN/touch, and password fallback retained |
| SOPS/PIV | Age recipient, key role, serial/slot reference | PIV private key remains on authenticator | Decrypt a synthetic canary through `age-plugin-yubikey` |
| SSH user or automation | Public key/fingerprint, principals, hardware-backed flag | Hardware key or agent; exportable software key only as narrowly scoped SOPS ciphertext | Sign and verify a fresh challenge; optionally prove restricted account authentication |
| SSH host | Pinned public host key and endpoint | Persistent host private key | Verified host-key handshake; address or DNS match alone is insufficient |
| PAM/U2F | User, PAM service, authorization mapping, UP/UV policy | FIDO2 credential remains on authenticator | Real local PAM transaction for the named service |
| WebAuthn/passkey | RP ID, permitted origins, subject, credential public reference, UV policy | Credential private key remains on authenticator or client platform | Real assertion ceremony for the expected RP ID, origin, credential, UP, and UV |

FIDO2 and PIV PINs, PUKs, management keys, biometric templates, hardware-backed
private keys, and WebAuthn private keys are not SOPS payloads. The repository
contract records their public metadata, custody role, recovery dependency, and
proof without attempting to export them.

## Command architecture

`ks-secrets` becomes a credential-audit command family:

```text
ks-secrets inventory --config <flake-or-path>
ks-secrets check sops --config <flake-or-path> [--identity <role>]
ks-secrets check luks --config <flake-or-path> [--host <name>]
ks-secrets check ssh --config <flake-or-path> [--identity <name>]
ks-secrets check pam --config <flake-or-path> --service <name>
ks-secrets check webauthn --config <flake-or-path> --rp <name>
```

The inventory command is non-interactive and consumes only public metadata.
Each check delegates authentication to the owning boundary:

- SOPS and `age-plugin-yubikey` own PIV PIN and touch interaction.
- SSH agents or authenticators own SSH passphrase, PIN, and touch interaction.
- The local PAM stack owns password, PIN, biometric, and touch interaction.
- The browser/client and relying party own the WebAuthn ceremony.
- `cryptsetup` consumes the streamed LUKS recovery bytes.

The shell command orchestrates these proofs and reports redacted results. It
does not implement a fake PAM conversation, collect WebAuthn client data, or
request authenticator secrets itself.

## Projected git graphs

Time flows upward. The lowest `○` is the next unimplemented commit. Existing
PR commits are `◉`; every line lands independently and is never squashed.

### ks.systems/os

```text
◇  v1.0.0 (next)
│
○  feat(secrets): enable credential audit
│  ── milestone: credential audit foundation · flag: credential_audit ──
○  docs(secrets): document credential audit
○  test(secrets): pin credential contracts
○  feat(secrets): verify WebAuthn credentials
○  feat(secrets): verify PAM security keys
○  feat(secrets): verify SSH identities
○  feat(secrets): prove LUKS recovery keys
○  feat(secrets): verify SOPS PIV identities
○  feat(secrets): discover credential inventory
◉  docs(reports): expand credential audit scope
◉  docs(requirements): broaden credential contracts
◉  docs(requirements): define secrets contract             2a9cea8  PR #3
◉  docs(requirements): define ks-config contract           008d148
◉  docs(reports): plan SOPS recovery validation            7e331a4
│
●  docs: prose review — three realizations consistently    68a33e4  ← main
◇  v1.0.0-rc.4 — 2026-05-21
```

### ks.systems/ks-config

```text
◇  v0.1.0 (next)
│
○  test(manifest): pin credential classes
○  feat(manifest): export credential inventory
○  docs(requirements): define credential mappings
│  ── milestone: credential audit foundation ──
◇  (no history — planned repository)
```

### ks.systems/secrets

```text
◇  v0.1.0 (next)
│
○  test(credentials): pin custody contracts
○  feat(credentials): add synthetic proof fixtures
○  feat(credentials): declare custody inventory
○  docs(requirements): define credential custody
│  ── milestone: credential audit foundation ──
◇  (no history — planned repository)
```

## Verification order

1. Inventory and schema fixtures for all credential classes.
2. Synthetic PIV/SOPS canary and LUKS test-passphrase proof.
3. Synthetic SSH fresh-challenge signing and host-key verification.
4. VM-local PAM/U2F transaction with explicit UP/UV policy.
5. Synthetic WebAuthn relying party verifying RP ID, origin, credential, UP,
   and UV.
6. Physical security-key exercises only after the synthetic boundaries pass.

A success in one row never satisfies another. In particular, a PIV canary
decrypt does not prove FIDO2, an SSH signature does not prove PAM, registration
metadata does not prove WebAuthn authentication, and TPM auto-unlock does not
prove LUKS recovery.

## Technical basis

- [OpenSSH supports signing and verifying data with SSH keys](https://man.openbsd.org/ssh-keygen#Y)
  through `ssh-keygen -Y sign` and `ssh-keygen -Y verify`.
- [Yubico's PAM U2F module](https://developers.yubico.com/pam-u2f/Manuals/pam_u2f.8.html)
  distinguishes user-presence and user-verification requirements.
- [WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/) scopes credentials to a
  relying-party ID and requires relying parties to validate authentication
  origins and assertions.
- [systemd's crypttab documentation](https://www.freedesktop.org/software/systemd/man/latest/crypttab.html)
  distinguishes FIDO2, PKCS#11/PIV, and TPM2 enrollment mechanisms even when
  one physical token implements more than one.
