# Keystone v0.3.0 — Hardware Keys

In the age of AI, hardware-backed identity is more important than ever. Keystone gains first-class YubiKey/FIDO2 support — your physical key becomes your root of trust for SSH, age encryption, and Secure Boot. This release also introduces `keystone.domain`, the shared TLD that two services (mail, git-server) already derive their configuration from, planting the seed for convention-over-configuration.

## Highlights

- **`keystone.hardwareKey` module** — declare YubiKeys with SSH public key material and age identities
- **age-plugin-yubikey** identity management for agenix secrets encryption
- **SSH agent** as systemd user service with 1h key expiry
- **`keystone.domain`** — shared TLD option (used by mail server + git server)
- **Ext4 + LUKS + hibernation** for laptops (PR #63) — enables the thin-client paradigm
- **Desktop**: monitors module, printing, OOM killer, media players, ergonomic keybindings
- **Terminal**: mail TUI (himalaya), Helix markdown preview, ghostty terminfo, LLM agents
- **OS**: git server module, eternal terminal, airplay, ZFS kernel compatibility docs

## What's New

### Hardware Key Infrastructure

The new `keystone.hardwareKey` module provides first-class YubiKey/FIDO2 support. Declare your hardware keys once and reference them throughout your configuration — SSH authentication, age encryption for agenix secrets, and root access control are all derived from the same key declarations. The SSH agent runs as a systemd user service with 1-hour key expiry for security.

### Shared Domain Convention

`keystone.domain` introduces a shared top-level domain option that services can derive their configuration from. The mail server and git server are the first consumers, automatically constructing their FQDNs from this shared TLD — the beginning of Keystone's convention-over-configuration approach.

### Ext4 + Hibernation (Thin Client)

Laptops can now use ext4 + LUKS with hibernation support (PR #63), enabling the thin-client paradigm where laptops hibernate to disk and reconnect to workstations over VPN. ZFS cannot support hibernation because dirty writes after freeze corrupt pools.

### Desktop Improvements

- Monitors module for multi-display configuration
- CUPS printing support
- OOM killer configuration (Docker/Podman containers killed first)
- Media players (VLC, mpv)
- Ergonomic keybindings with Alt-as-modifier

### Terminal Enhancements

- Himalaya mail TUI for email from the terminal
- Helix markdown preview (F6 keybind)
- Ghostty terminfo for proper terminal rendering
- LLM agent tooling (Claude Code, Gemini CLI)

### OS Services

- Forgejo git server module with `keystone.domain` integration
- Eternal Terminal for persistent shell sessions
- Shairport Sync AirPlay receiver
- ZFS kernel compatibility documentation

## Breaking Changes

None.

## Full Changelog

[v0.2.0...v0.3.0](https://github.com/ncrmro/keystone/compare/v0.2.0...v0.3.0)
