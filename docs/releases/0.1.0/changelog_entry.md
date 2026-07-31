## [0.1.0] - 2025-11-08

### Added

- Disko single-disk module for declarative ZFS + LUKS partitioning ([`8458ef2`](https://github.com/ncrmro/keystone/commit/8458ef2))
- Server, client, and observability NixOS modules ([`1f2aab2`](https://github.com/ncrmro/keystone/commit/1f2aab2))
- SSH-based ISO with automated VM testing framework ([#9](https://github.com/ncrmro/keystone/pull/9))
- Automated encrypted installation via nixos-anywhere ([#10](https://github.com/ncrmro/keystone/pull/10))
- Secure Boot setup mode for VMs and bare metal ([#11](https://github.com/ncrmro/keystone/pull/11))
- Secure Boot key enrollment on first install via Lanzaboote ([`f0d449a`](https://github.com/ncrmro/keystone/commit/f0d449a))
- TPM2 enrollment with PCR binding for automatic disk unlock ([#14](https://github.com/ncrmro/keystone/pull/14))
- LUKS encryption with credstore pattern for ZFS key management
- Initrd SSH for remote disk unlocking on headless servers ([`2dcf94f`](https://github.com/ncrmro/keystone/commit/2dcf94f))
- ZFS user module with per-user datasets and delegated permissions ([#15](https://github.com/ncrmro/keystone/pull/15))
- Terminal development module: Helix, Zsh, Zellij, Starship, Git ([#16](https://github.com/ncrmro/keystone/pull/16))
- Hyprland desktop with UWSM, greetd, PipeWire, Hyprlock/Hypridle ([#19](https://github.com/ncrmro/keystone/pull/19))
- Libvirt VM management script for test deployments (`bin/virtual-machine`)
- Nix formatting and CI tooling (`make ci`, `make fmt`)
- Spec-kit integration for spec-driven development ([`acdc92b`](https://github.com/ncrmro/keystone/commit/acdc92b))

### Changed

- Deployment tooling refactored from QEMU scripts to Python libvirt ([`5c104f9`](https://github.com/ncrmro/keystone/commit/5c104f9))
- Test deployment updated to use SSH-based unlock ([`731e2f8`](https://github.com/ncrmro/keystone/commit/731e2f8))

### Fixed

- Simplified LUKS password entry — removed redundant manual step ([`43f19ef`](https://github.com/ncrmro/keystone/commit/43f19ef))
- Corrected sbctl key paths for Secure Boot enrollment (multiple commits)
