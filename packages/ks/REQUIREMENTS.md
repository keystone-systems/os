# ks — Functional Requirements

This document defines the functional requirements for `ks`, the primary configuration management tool for Keystone NixOS infrastructure. The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", and "MAY" are used per [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119).

## 1. Persistent Configuration

- The TUI MUST store its configuration under XDG paths (`$XDG_CONFIG_HOME/keystone/` or `~/.config/keystone/`).
- The TUI MUST support managing multiple Keystone infrastructure configurations (repos) simultaneously.
- Configuration MUST be serialized as TOML.

## 2. First Run

- On first run, the TUI MUST present a choice: import an existing Keystone repo (git clone) OR create a new one from the flake template.
- When importing, the TUI MUST validate that the repo contains a valid `flake.nix` with Keystone inputs.
- When creating new, the TUI MUST scaffold using `nix flake init -t github:ncrmro/keystone` and guide the user through initial configuration.

## 3. Secrets Repository

- The TUI MUST ask whether the user wants a separate secrets repository (private encrypted repo for agenix secrets) or a single combined repo.
- When using a separate secrets repo, the TUI MUST support self-hosted git (e.g., Forgejo on Headscale VPN) as the remote.
- Secrets MUST be encrypted using age (agenix-compatible format).

## 4. Key Management

### SSH Keys

- The TUI MUST detect existing SSH keys in `~/.ssh/`.
- The TUI MUST warn if detected keys use legacy algorithms (RSA < 4096, DSA, ECDSA).
- The TUI SHOULD offer to generate a new ed25519 key if none exists.

### FIDO2 Keys

- The TUI MUST support FIDO2 key enrollment for SSH (`ssh-keygen -t ed25519-sk`).
- The TUI MUST support generating new FIDO2-backed SSH keys.
- The TUI MUST track FIDO2 key metadata (serial number, attestation certificate, enrollment date).
- The TUI MAY support macOS Secure Enclave as a key backend (future).

## 5. Nix Generation

- The TUI MUST generate a valid `flake.nix` if one does not exist, using `rnix` for AST manipulation.
- The TUI MUST guide the user through adding a new host configuration (hostname, disk selection, storage type, user setup).
- Generated Nix code MUST follow the patterns in the Keystone flake template.

## 6. Multi-Host Management

- The TUI MUST support managing multiple NixOS host configurations within a single flake.
- The TUI MUST support building any configured host (`nixos-rebuild build --flake .#hostname`).
- The TUI MUST display build output in a scrollable pane.

## 7. Git Operations

- The TUI MUST handle git commit and push for configuration changes.
- The TUI MUST NOT push to a remote without explicit user confirmation.
- The TUI MUST show a diff preview before committing.
- The TUI SHOULD support creating branches for experimental changes.

## 8. TUI Framework

- The TUI MUST use `ratatui` with `crossterm` as the terminal backend.
- The TUI MUST handle terminal resize events gracefully.
- The TUI MUST restore terminal state on panic (panic hook).
- The TUI MUST clean up terminal state on normal exit.
- The TUI SHOULD support mouse events for navigation.

## 9. ISO Installer Mode

- When running on a pre-baked Keystone ISO that embeds `/etc/keystone/install-config/`, the TUI MUST enter installer mode automatically.
- Installer mode MUST treat `/etc/keystone/install-config/` as immutable input and stage a writable per-run copy before mutating deferred values such as `__KEYSTONE_DISK__`.
- Installer mode MUST complete hardware detection and create the initial installed-system git commit after `disko` mounts `/mnt` and before `nixos-install`; first boot is for security enrollment and later push/secrets work, not baseline hardware capture.
- The detailed install and first-boot journey contract lives in `requirements/REQ-008-onboarding-journey.md`; this section is only a summary.
- This mode replaces the previous React Ink installer TUI.
