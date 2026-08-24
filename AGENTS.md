# Keystone

@CONTRIBUTOR.md — development workflow, verification commands, and deployment flow

Keystone is a NixOS-based self-sovereign infrastructure platform for deploying secure,
encrypted infrastructure on any hardware. It provides declarative modules for OS
configuration and server services. `ks.systems/terminal` owns terminal tooling.
`ks.systems/desktop` owns desktop environments and depends on the terminal
product.

## Fleet model

A keystone system is a **fleet of hosts configured as a whole** in a single
git-committed consumer flake (e.g., `nixos-config` or `keystone-config`).
Enabling a service wires up both the server and its clients across the fleet.
A typical deployment:

- **Workstation** — primary desktop, GPU, agents, full development environment
- **Laptop** — thin client, remotes into workstation via SSH or Eternal Terminal
- **Server/NAS** — headless services (Forgejo, Grafana, Immich, mail, DNS, monitoring)
- **Offsite/VPS** — backup target, public-facing reverse proxy, or Headscale coordinator

`ks update --lock` deploys the current host by default. Pass a comma-separated
list to deploy multiple: `ks update --lock ocean,mercury`.

## Modules

- `modules/os/` — Core OS: storage, Secure Boot, TPM, users, SSH, agents, containers, Tailscale
- `modules/os/agents/` — Autonomous agent service accounts: task loop, scheduler, desktop, mail
- `ks.systems/terminal` input — Home Manager terminal product for headless, desktop, Linux, and macOS users
- `modules/desktop/` — keystone glue only (`keystone-glue.nix`); the desktop implementation lives in the ks.systems/desktop flake (the `desktop` input)
- `modules/server/` — Server services: DNS, mail, monitoring, Forgejo, Grafana, Immich, Vaultwarden
- `modules/notes/` — Zettelkasten notebook management via zk

## Docs

- `docs/index.md` — entry point for users
- `docs/milestones/` — product deliverables, one dir per GitHub milestone (`M<N>-<slug>/`)
- `docs/specs/` — normative requirement specs (`REQ-NNN-<slug>.md`, flat files)
- `docs/releases/` — release artifacts and per-tag release notes
- `docs/{os,desktop,agents,cluster,research,posts}/` — topical guides and supporting material
- `conventions/` — project-level conventions (process, code style, archetypes)

## Packages

- `packages/ks/` — Keystone CLI (shell): build, deploy, approve, secrets, hardware-key, kube
- `ks.systems/terminal` input — Terminal packages and editable starter templates
- `packages/keystone-ha/` — Home-assistant integration

## Flake Exports

### NixOS Modules (`keystone.nixosModules.*`)

| Module | Description |
|---|---|
| `operating-system` | Core OS — storage, Secure Boot, TPM, users, agents (includes disko + lanzaboote) |
| `server` | Server services (includes domain) |
| `desktop` | Desktop environments — re-export of ks.systems/desktop plus keystone glue |
| `hardwareKey` | YubiKey/FIDO2 support |
| `isoInstaller` | Bootable installer |
| `experimental` | Experimental feature flag (`keystone.experimental`) |
| `domain`, `hosts`, `repos`, `services`, `keys` | Shared options modules |
| `headscale-dns` | Consume server DNS records on headscale host |

### Home Manager modules

This repository exports `desktop` and `notes`. Consumers MUST import
`terminal.homeModules.default` directly from the `ks.systems/terminal` input.
The OS wrapper imports it for managed NixOS users.

### Overlay (`pkgs.keystone.*`)

Terminal packages use `pkgs.keystone-terminal.*`. OS packages use
`pkgs.keystone.*`. Desktop packages use `pkgs.keystone-desktop.*`.

## Important Notes

- ZFS pool is **always** named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- The terminal product is a Home Manager product. It MUST support headless hosts.
- The desktop product MUST depend on the terminal product.
- `keystone.repos` auto-populates from flake inputs; `keystone.development` enables local checkout paths
- `keystone.experimental` (default `false`) gates experimental features. Its shared declaration is obtained from the already-required `ks.systems/terminal` input.

## Keystone Config Repo

The **keystone config repo** is `ks-config` — the consumer flake that imports keystone
modules and declares per-host/per-user configuration. Keystone-managed repos live
under `~/repos/OWNER/REPO/`; `~/.keystone/repos/OWNER/REPO/` is legacy fallback only.

## Pull request workflow

PR mechanics — draft → Copilot review → merge queue, plus issue and
milestone linkage — live in
[`CONTRIBUTOR.md` § Pull request workflow](CONTRIBUTOR.md#pull-request-workflow).
Agents follow that section for every PR; the canonical source is the
`process.pr-shepherding` skill convention.
