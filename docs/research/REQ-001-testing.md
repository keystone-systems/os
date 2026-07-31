# Research: Testing Infrastructure

**Relates to**: REQ-001 (Keystone OS)

## Testing Tiers

| Tier | Framework                   | Speed | Coverage                            | CI                     |
| ---- | --------------------------- | ----- | ----------------------------------- | ---------------------- |
| 1    | microvm.nix                 | ~5s   | TPM enrollment, module config       | Yes                    |
| 2    | NixOS Test (`runNixOSTest`) | ~30s  | Multi-node, remote unlock           | Selective (IFD issues) |
| 3    | libvirt + OVMF              | ~60s+ | Secure Boot, TPM PCR 7, full deploy | Manual                 |
| Fast | `nixos-rebuild build-vm`    | ~10s  | Desktop/terminal config             | Yes                    |

## Framework Capabilities

| Capability      | build-vm | microvm.nix | NixOS Test | libvirt |
| --------------- | -------- | ----------- | ---------- | ------- |
| UEFI/OVMF       | No       | No          | Yes        | Yes     |
| Secure Boot     | No       | No          | Yes        | Yes     |
| TPM (swtpm)     | No       | Yes         | Yes        | Yes     |
| Persistent Disk | Yes      | Yes         | No         | Yes     |
| Host Nix Store  | Yes (9P) | Yes         | Yes        | No      |
| CI Friendly     | Yes      | Yes         | Partial    | No      |

## Key Finding: microvm.nix Limitations

microvm.nix uses direct kernel boot only — **no UEFI**. Cannot test Secure Boot, lanzaboote, or TPM PCR 7. Can test: `/dev/tpm0` presence, `systemd-cryptenroll` on loopback, LUKS2 token handling, module config.

## IFD Workaround

NixOS VM tests cause Import-From-Derivation failures in `nix flake check`. Tests are placed in `packages` output instead of `checks`, run explicitly via `nix build .#test-name`.

## Test Coverage by FR

| FR                          | microvm        | libvirt         |
| --------------------------- | -------------- | --------------- |
| FR-002 Full Disk Encryption | LUKS2 loopback | Full ZFS + LUKS |
| FR-003 Automatic Unlock     | TPM enrollment | TPM auto-unlock |
| FR-004 Verified Boot        | No (no UEFI)   | Secure Boot     |
| FR-005 CoW Storage          | No             | ZFS pool        |

## Stale Path Reference

Line 22 of original referenced the legacy `_archive/001-keystone-os/requirements.md` — now `docs/specs/REQ-001-keystone-os.md`.
