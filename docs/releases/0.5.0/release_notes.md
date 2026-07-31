# Keystone v0.5.0 — Photos

Immich photo management gets first-class Keystone integration, and the agent system stabilizes with host-based filtering, auto-provisioning, and the `hwrekey` workflow for managing YubiKey identities across machines.

## Highlights

- **Agent host filtering** — resources only instantiate on the correct machine
- **Agent auto-provisioning** for mail and git (Forgejo)
- **`hwrekey` script** — serial-based YubiKey identity management with commit message support
- **SSH key auto-load** via agenix passphrase
- **Remote agentctl dispatch** via ET over Tailscale
- **Agent task loop** and agentctl improvements
- **Comprehensive AGENTS.md documentation** rewrite
- **Convention-over-config**: auto-derive user email, mkDefault patterns

## What's New

### Agent Host Filtering

Agents now declare which host they belong to via `keystone.os.agents.<name>.host`. Resources (systemd services, user accounts, mail provisioning) only instantiate on the matching machine, preventing resource conflicts in multi-host configurations.

### Agent Auto-Provisioning

Mail accounts and Forgejo repositories are automatically provisioned when an agent is declared. The provisioning scripts use the Forgejo CLI for user creation and API tokens, then the HTTP API for SSH key registration and repository creation.

### YubiKey Identity Management (`hwrekey`)

The `hwrekey` script provides a complete workflow for managing YubiKey-based age identities: detect connected YubiKey by serial number, run `agenix --rekey`, commit and push the secrets submodule, then update the parent flake input. Supports commit message customization and retries for pcscd contention.

### SSH Key Auto-Load

A new systemd user service automatically loads SSH keys at login using agenix-managed passphrases. Private keys remain host-bound (never stored in agenix) — only passphrases are managed as secrets.

### Remote Agent Control

`agentctl` now supports remote dispatch via Eternal Terminal over Tailscale, enabling management of agents running on remote hosts from any machine in the tailnet.

### Documentation

Comprehensive rewrite of AGENTS.md documenting the full agent provisioning lifecycle, agentctl CLI, security model, and operational procedures.

## Breaking Changes

None.

## Full Changelog

[v0.4.0...v0.5.0](https://github.com/ncrmro/keystone/compare/v0.4.0...v0.5.0)
