# Keystone v0.2.0 — Four-Pillar Architecture

A major architectural consolidation: Keystone's modules are reorganized into four clear pillars (`os`, `desktop`, `terminal`, `server`), exported as standalone flake modules for use in any NixOS configuration. The desktop environment is now fully portable — migrated from nixos-config into Keystone — and the terminal tooling gains new navigation and file viewing capabilities.

## Highlights

- **Four-pillar module architecture**: All modules consolidated into `modules/{os,desktop,terminal,server}` with clean separation of concerns
- **Exported flake modules**: `keystoneTerminal` and `keystoneDesktop` home-manager modules available as flake outputs for external consumption
- **Desktop portability**: Hyprland desktop configuration migrated from nixos-config into Keystone, making it reusable across any host
- **Fast VM testing**: `build-vm` script for rapid terminal and desktop config iteration without encryption overhead

## What's New

### Module Architecture Consolidation

The entire module tree has been reorganized from a flat layout into four pillars: `os`, `desktop`, `terminal`, and `server`. Each pillar is a self-contained NixOS or home-manager module exportable via the flake. Old module paths are removed — this is a clean break. ([#45](https://github.com/ncrmro/keystone/pull/45))

### Flake Module Exports

Terminal and desktop modules are now exported as `homeModules.keystoneTerminal` and `homeModules.keystoneDesktop`, allowing any flake to import Keystone's developer environment or Hyprland desktop without pulling the full OS module. ([`c9b5633`](https://github.com/ncrmro/keystone/commit/c9b5633), [`fd8a8d7`](https://github.com/ncrmro/keystone/commit/fd8a8d7))

### Desktop Environment

The Hyprland desktop configuration — previously maintained in nixos-config — is now part of Keystone. Includes Royal Green theme for Zellij, NetworkManager integration, drag-lock, Alt-as-modifier with CapsLock-as-Control remapping, and scroll tuning. ([`ff2f8a7`](https://github.com/ncrmro/keystone/commit/ff2f8a7), [`3568f95`](https://github.com/ncrmro/keystone/commit/3568f95))

### Build-VM Testing

A new `build-vm` workflow enables fast iteration on terminal and desktop configs using `nixos-rebuild build-vm`. Terminal mode auto-connects via SSH; desktop mode opens a graphical QEMU window. No encryption or Secure Boot overhead. ([#21](https://github.com/ncrmro/keystone/pull/21))

### Terminal Tooling

- **zesh**: Zoxide-powered shell navigation with aliases ([#24](https://github.com/ncrmro/keystone/pull/24))
- **yazi**: Terminal file manager integration
- **csview**: CSV viewer for quick data inspection ([#27](https://github.com/ncrmro/keystone/pull/27))
- **direnv**: Enabled by default for automatic dev shell activation
- **Git config**: TUI-based git credential setup ([`71446d9`](https://github.com/ncrmro/keystone/commit/71446d9))

### MicroVM Testing

Added microvm.nix integration for lightweight, reproducible testing of specific module configurations (e.g., TPM emulation). Faster feedback loop than full VM deployments. ([`1f21bb0`](https://github.com/ncrmro/keystone/commit/1f21bb0))

### CI Improvements

- All packages now tested in CI ([#37](https://github.com/ncrmro/keystone/pull/37))
- Nix action upgraded to v31
- Copilot setup steps and devcontainer support ([#36](https://github.com/ncrmro/keystone/pull/36))

### Documentation

- GitHub Pages documentation site with Jekyll ([`d850ab0`](https://github.com/ncrmro/keystone/commit/d850ab0))
- Simplified README
- Local dev workflow documentation

## Bug Fixes

- Fixed UTF-8 encoding errors in TPM enrollment docs ([`8f80775`](https://github.com/ncrmro/keystone/commit/8f80775))

## Breaking Changes

- Module import paths have changed. Update imports from the old flat layout to the new pillar structure:
  - `keystoneTerminal` → `keystone.homeModules.terminal`
  - `keystoneDesktop` → `keystone.homeModules.desktop`
  - `operating-system` → `keystone.nixosModules.operating-system`
  - `server` → `keystone.nixosModules.server`

## Full Changelog

[v0.1.0...v0.2.0](https://github.com/ncrmro/keystone/compare/v0.1.0...v0.2.0)
