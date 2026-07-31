# Keystone v0.7.0 — Keys

Building on the hardware key foundation from v0.3.0, `keystone.keys` introduces a platform-wide SSH public key registry. Keys declared once are referenced everywhere — user accounts, agent provisioning, git server signing, host identity. Immich gains distributed ML worker support for offloading photo processing across machines.

## Highlights

- **`keystone.keys`** — SSH public key registry, declare once, reference everywhere
- **Immich remote machine learning** with auto-role detection (server vs worker)
- **Git server SSH commit signing** with pre-start key generation
- **`ks` CLI**: default to `--lock`, support multiple hosts, sequential deploy
- **Terminal**: calendar (Calendula), contacts (cardamum), timer (comodoro), tea + fj for Forgejo
- **Agenix moved into keystone**
- **Ollama service module** + terminal AI integration
- **TUI**: dashboard, hosts, installer, ISO build

## What's New

### SSH Public Key Registry

`keystone.keys` provides a centralized registry for SSH public keys. Declare a key once with a name and public key material, then reference it by name in user accounts, agent configurations, git server admin lists, and host identity. No more duplicating public keys across multiple configuration files.

### Immich Distributed ML

Immich's machine learning can now be offloaded to dedicated worker machines. The module auto-detects whether a host should run as a server (with web UI and API) or as a worker (ML processing only), based on host configuration.

### Git Server Signing

The Forgejo git server now generates SSH signing keys at pre-start and configures commit signing, enabling verified commits for agent-authored code.

### `ks` CLI Improvements

The `ks` CLI defaults to `--lock` for reproducible builds, supports targeting multiple hosts in a single invocation, and deploys sequentially to prevent resource contention.

### Terminal Productivity

New terminal tools expand the PIM (Personal Information Management) suite:

- **Calendula** — calendar management
- **cardamum** — contact management
- **comodoro** — Pomodoro timer
- **tea** + **fj** — Forgejo CLI clients for issue and PR management

### Agenix Integration

Agenix (age-encrypted secrets for NixOS) is now bundled into Keystone, simplifying the secrets management story for users who previously needed to add it as a separate flake input.

### Ollama

A new Ollama service module enables local LLM inference, with terminal AI integration for using local models alongside cloud providers.

### TUI

The Keystone TUI gains a dashboard view, host management, an installer wizard, and ISO build capabilities.

## Breaking Changes

None.

## Full Changelog

[v0.6.0...v0.7.0](https://github.com/ncrmro/keystone/compare/v0.6.0...v0.7.0)
