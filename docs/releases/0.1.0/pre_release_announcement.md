# Keystone v0.1.0 — First Working Desktop

**Release Date**: 2025-11-08
**Release Channel**: alpha
**Tag**: v0.1.0

## Headline

Keystone v0.1.0 delivers a fully encrypted, secure-booted NixOS workstation with Hyprland desktop — installable on bare metal in under 30 minutes.

## What's New

Keystone is a NixOS-based platform for deploying self-sovereign infrastructure on any hardware. With v0.1.0, you can boot from a Keystone ISO, run a single `nixos-anywhere` command, and have a fully encrypted workstation with TPM2 auto-unlock, Secure Boot, and a Hyprland desktop — ready to use.

This release represents the culmination of the foundational work from PRs #9 through #19: SSH-based ISO testing, automated encrypted installation via nixos-anywhere, Secure Boot with automatic key enrollment, TPM2-based disk unlock, ZFS user management, a terminal development environment, and the Hyprland desktop. Every layer builds on the one before it — from encrypted storage through to the graphical session you log into.

The result is that you can sit down at a Keystone machine and start working. ZFS encryption protects your data at rest, TPM2 unlocks your disks automatically on trusted boots, Secure Boot prevents unauthorized code from running, and the Hyprland desktop provides a modern tiling window manager with audio, screen locking, and a polished login experience via greetd.

## Key Highlights

- **One-command encrypted install**: Boot the ISO, run `nixos-anywhere --flake .#your-config root@<ip>`, and get a fully encrypted NixOS system with ZFS, LUKS, and credstore-based key management
- **TPM2 auto-unlock**: Disks unlock automatically on trusted boots. If the boot chain is tampered with, TPM refuses to release keys and falls back to password entry
- **Secure Boot from first install**: Lanzaboote enrolls custom Secure Boot keys during initial installation — no manual BIOS setup required
- **Hyprland desktop**: Complete tiling desktop with UWSM session management, greetd login, PipeWire audio, screen locking via Hyprlock/Hypridle, and waybar
- **Terminal dev environment**: Helix editor, Zsh with starship prompt, Zellij multiplexer, and Git — all configured and ready
- **ZFS user management**: Per-user ZFS datasets with delegated permissions and optional quotas
- **Remote unlock via SSH**: Unlock encrypted disks remotely through SSH in the initrd for headless server deployments

## Who This Is For

- **NixOS power users** who want a security-hardened, reproducible system without manually wiring up disko, lanzaboote, and TPM enrollment
- **Self-hosters** who need encrypted, secure-booted servers with remote unlock capability
- **Developers** who want a complete, reproducible workstation environment they can deploy to any x86_64 hardware

## Breaking Changes

None — this is the first release. No prior version to break compatibility with.

## Upgrade Path

Fresh install via the Keystone ISO and `nixos-anywhere`. There is no upgrade path from plain NixOS — Keystone manages the full disk layout, encryption, and boot chain.

```bash
# Build the installer ISO
make build-iso

# Install to target machine
nixos-anywhere --flake .#your-config root@<installer-ip>
```

## What's Next

- **v0.0.2**: Developer environment polish — server-side home-manager integration and remote development workflows
- **v0.0.3**: Desktop polish — remote desktop access (VNC/RDP/Sunshine) and multi-monitor support
- **v0.0.4**: Universal development — portable home-manager config for Codespaces, macOS, and any Nix platform
- **v0.1.0**: Production readiness — backups, monitoring, secrets management, and disaster recovery
