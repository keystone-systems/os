# Keystone v0.6.0 — Keystone System

A single user's Keystone system is now understood as many machines — bare-metal workstations, laptops, and VPS instances — working together. The `ks` CLI becomes the single tool for building and deploying across all of them. `keystone.hosts` provides host identity and connection metadata. `keystone.services` creates a shared namespace so modules can discover each other across machines.

## Highlights

- **`ks` CLI** — build, deploy, and manage NixOS configs across multiple hosts (`ks build`, `ks update`, `ks update --dev`)
- **`keystone.hosts`** — host identity with sshTarget, fallbackIP, buildOnRemote
- **`keystone.services`** — shared option namespace for cross-module service discovery
- **`keystone.deploy.hosts` renamed to `keystone.hosts`** (breaking change)
- **`_module.args.keystoneInputs` replaced** with dedicated option
- **Agent systemd service names** standardized to `agent-NAME-JOB` pattern
- **Standardized Tailscale roles** per host
- **ISO installer refactored** with `keystone.installer` option and `mkInstallerIso`
- **Git server**: adminUsers option, user-level API endpoints

## What's New

### `ks` CLI

The `ks` command becomes the single entry point for managing a multi-host Keystone system. `ks build` evaluates NixOS configurations, `ks update` performs `nixos-rebuild switch`, and `ks update --dev` overrides flake inputs with local checkouts for rapid development without commits.

### Host Identity

`keystone.hosts` provides structured metadata for each machine in the system: hostname, SSH target, fallback IP, and whether to build on the remote. This replaces the previous `keystone.deploy.hosts` option with a cleaner interface that other modules can reference.

### Cross-Module Service Discovery

`keystone.services` creates a shared namespace where modules can register themselves and discover each other. A mail server on one host can be discovered by agent modules on another, enabling configuration to flow between machines without hardcoded values.

### Agent Standardization

Agent systemd service names are standardized to the `agent-NAME-JOB` pattern (e.g., `agent-drago-task-loop`), making log inspection and service management consistent across all agents.

### Tailscale Roles

Each host now declares its Tailscale role (exit-node, subnet-router, or client), enabling role-based access control and network topology decisions.

### ISO Installer

The installer is refactored with a `keystone.installer` option and `mkInstallerIso` helper, making it easier to build custom installer ISOs with pre-configured SSH keys and network settings.

## Breaking Changes

- **`keystone.deploy.hosts`** renamed to **`keystone.hosts`** — update all references
- **`_module.args.keystoneInputs`** replaced with a dedicated option

## Full Changelog

[v0.5.0...v0.6.0](https://github.com/ncrmro/keystone/compare/v0.5.0...v0.6.0)
