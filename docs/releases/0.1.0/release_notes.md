# Keystone v0.1.0 — First Working Desktop

The first alpha release of Keystone: a fully encrypted, secure-booted NixOS workstation with Hyprland desktop, installable on bare metal with a single command.

## Highlights

- **One-command encrypted install**: Boot the ISO, run `nixos-anywhere`, get a fully encrypted NixOS system
- **Hardware-backed security**: TPM2 auto-unlock, Secure Boot with automatic key enrollment, LUKS + ZFS encryption
- **Complete desktop**: Hyprland tiling compositor with PipeWire audio, screen locking, and greetd login
- **Developer-ready**: Helix editor, Zsh + Starship, Zellij multiplexer, Git — all pre-configured

## What's New

### Encrypted Installation

Keystone uses disko for declarative disk partitioning with ZFS and LUKS encryption. The credstore pattern manages encryption keys so that ZFS datasets are automatically unlocked during boot. Install to any machine by booting the Keystone ISO and running:

```bash
nixos-anywhere --flake .#your-config root@<installer-ip>
```

The entire disk layout, encryption, and boot chain are configured declaratively in your flake. ([PR #9](https://github.com/ncrmro/keystone/pull/9), [PR #10](https://github.com/ncrmro/keystone/pull/10))

### Secure Boot & TPM2

Secure Boot keys are enrolled automatically during first installation via Lanzaboote — no manual BIOS configuration required. TPM2 enrollment binds disk unlock to the boot chain: if the boot environment is tampered with, the TPM refuses to release keys and falls back to password entry. ([PR #11](https://github.com/ncrmro/keystone/pull/11), [PR #14](https://github.com/ncrmro/keystone/pull/14))

### Remote Disk Unlock

For headless servers, SSH is available in the initrd so you can unlock encrypted disks remotely without physical access. Configure authorized keys and unlock over the network.

### ZFS User Management

Each user gets a dedicated ZFS dataset with delegated permissions and optional quotas. Home directories are automatically created as ZFS datasets, giving each user snapshot and quota capabilities. ([PR #15](https://github.com/ncrmro/keystone/pull/15))

### Terminal Development Environment

A complete terminal development setup is included: Helix editor with language server support, Zsh with Starship prompt, Zellij terminal multiplexer, Ghostty terminal, and Git with pre-configured credentials. ([PR #16](https://github.com/ncrmro/keystone/pull/16))

### Hyprland Desktop

A full Hyprland tiling desktop environment with UWSM session management, greetd login manager, PipeWire audio (ALSA/Pulse/Jack), screen locking via Hyprlock/Hypridle, and Waybar. Includes Firefox, VS Code, and VLC. ([PR #19](https://github.com/ncrmro/keystone/pull/19))

## Bug Fixes

- Simplified LUKS password entry by removing a redundant manual step
- Corrected sbctl key paths for Secure Boot enrollment

## Breaking Changes

None — this is the first release.

## Getting Started

```bash
# Clone and build the installer ISO
git clone git@github.com:ncrmro/keystone.git
cd keystone
make build-iso

# Boot target machine from ISO, then deploy
nixos-anywhere --flake .#your-config root@<installer-ip>
```

See the [flake template](https://github.com/ncrmro/keystone#flake-template-recommended-for-new-users) for a quick-start configuration.

## VM Testing

Test without hardware using the built-in VM tooling:

```bash
# Quick terminal config test
./bin/build-vm terminal

# Full desktop test
./bin/build-vm desktop

# Full-stack test with TPM + Secure Boot
./bin/virtual-machine --name keystone-test-vm --start
```

## Full Changelog

[Initial commit...v0.1.0](https://github.com/ncrmro/keystone/compare/06fbb40...59ffa5f)

## What's Next

- **v0.0.2**: Server-side home-manager integration and remote development workflows
- **v0.0.3**: Remote desktop access and multi-monitor support
- **v0.0.4**: Portable home-manager for Codespaces, macOS, and other Nix platforms
