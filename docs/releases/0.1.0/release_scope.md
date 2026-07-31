# Release Scope: Keystone v0.1.0

**Target Version**: v0.1.0
**Release Channel**: alpha
**Base**: Initial commit (`06fbb40`) through `59ffa5f`
**Scope Date**: 2026-03-03 (retroactive — release milestone was 2025-11-08)

## Included Changes

### Added

#### Infrastructure Foundation

- Disko single-disk module for declarative disk partitioning ([`8458ef2`](https://github.com/ncrmro/keystone/commit/8458ef2))
- Server, client, and observability NixOS modules ([`1f2aab2`](https://github.com/ncrmro/keystone/commit/1f2aab2))
- Nix formatting and CI tooling ([`69e1e67`](https://github.com/ncrmro/keystone/commit/69e1e67), [`d9f0623`](https://github.com/ncrmro/keystone/commit/d9f0623))
- Spec-kit integration for spec-driven development ([`acdc92b`](https://github.com/ncrmro/keystone/commit/acdc92b))

#### Installation & Deployment (PRs #9-#10)

- SSH-based ISO with VM testing framework ([PR #9](https://github.com/ncrmro/keystone/pull/9))
- Automated encrypted installation via nixos-anywhere ([PR #10](https://github.com/ncrmro/keystone/pull/10))
- Libvirt VM management script (`bin/virtual-machine`) for test deployments

#### Security (PRs #11-#14)

- Secure Boot setup mode for VMs and bare metal ([PR #11](https://github.com/ncrmro/keystone/pull/11))
- Secure Boot key enrollment on first install via Lanzaboote ([`f0d449a`](https://github.com/ncrmro/keystone/commit/f0d449a))
- TPM2 enrollment with PCR binding for automatic disk unlock ([PR #14](https://github.com/ncrmro/keystone/pull/14))
- LUKS encryption with credstore pattern for ZFS key management
- Initrd SSH for remote disk unlocking on headless servers ([`2dcf94f`](https://github.com/ncrmro/keystone/commit/2dcf94f))

#### User Management (PR #15)

- ZFS user module with per-user datasets and delegated permissions ([PR #15](https://github.com/ncrmro/keystone/pull/15))
- Optional per-user ZFS quotas
- Home-manager integration foundation

#### Terminal Environment (PR #16)

- Terminal development module: Helix, Zsh, Zellij, Git ([PR #16](https://github.com/ncrmro/keystone/pull/16))
- Starship prompt configuration
- Ghostty terminal emulator support

#### Hyprland Desktop (PR #19)

- Hyprland compositor with UWSM session management ([PR #19](https://github.com/ncrmro/keystone/pull/19))
- greetd login manager with tuigreet
- PipeWire audio with ALSA/Pulse/Jack compatibility
- Screen locking via Hyprlock/Hypridle
- Waybar status bar
- Desktop applications (Firefox, VS Code, VLC)

### Changed

- Deployment tooling refactored from QEMU scripts to Python libvirt ([`5c104f9`](https://github.com/ncrmro/keystone/commit/5c104f9))
- Test deployment updated to use SSH-based unlock ([`731e2f8`](https://github.com/ncrmro/keystone/commit/731e2f8))

### Fixed

- LUKS password entry simplified — removed manual step ([`43f19ef`](https://github.com/ncrmro/keystone/commit/43f19ef))
- sbctl key paths corrected for Secure Boot enrollment ([multiple commits in PR #11-#14 range](https://github.com/ncrmro/keystone/compare/f516c72...f0d449a))

## Breaking Changes

No breaking changes — this is the first release. No prior version exists.

## Work Backlog

All scoped items are implemented. This is a retroactive release documenting the state at commit `59ffa5f`.

- [x] SSH-based ISO testing — PR #9
- [x] Automated encrypted installation — PR #10
- [x] Secure Boot setup mode — PR #11
- [x] Secure Boot enrollment on first install — PR #13
- [x] TPM2 enrollment — PR #14
- [x] ZFS user module — PR #15
- [x] Terminal dev environment — PR #16
- [x] Hyprland desktop — PR #19

## Out of Scope

Per ROADMAP.md, the following are explicitly not in v0.1.0:

- **Installation documentation** — deferred (ROADMAP v0.1.0 "pending" item)
- **TPM error recovery procedures** — deferred (ROADMAP v0.1.0 "pending" item)
- **Multi-disk configurations** — deferred (ROADMAP v0.1.0 "pending" item)
- **Server-side home-manager integration** — deferred to v0.0.2
- **Remote desktop access (VNC/RDP/Sunshine)** — deferred to v0.0.3
- **Multi-monitor configuration** — deferred to v0.0.3
- **Portable home-manager (Codespaces, macOS)** — deferred to v0.0.4
- **Backups, monitoring, secrets management** — deferred to v0.1.0
- **OS agents (bitwarden, email, ssh, tailscale)** — post-v0.1.0 work (spec/007)
- **Server services module (nginx, ACME, DNS)** — post-v0.1.0 work
- **CHANGELOG.md creation** — will be established as part of this release process
- **Release automation (GitHub Actions)** — future work

## Dependencies

None — this is a retroactive release of already-implemented work.

## Summary

- **Total changes**: 21 (17 added, 2 changed, 2 fixed)
- **Breaking changes**: 0
- **Open work items**: 0
- **Ready to release**: Yes — all work is implemented at commit `59ffa5f`
