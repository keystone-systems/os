# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.12.0] - 2026-04-03

### Added

- Desktop update and photos menus, including the Walker update menu, photos launcher, and preview flow
- Walker secrets and printer menus, including agenix secret actions, network printer discovery, default-printer persistence, and print-oriented desktop polish
- `ks print` follow-up improvements, including scripted doctor reports, improved docs browsing, and automatic PDF handoff to the default CUPS printer
- New project-oriented DeepWork workflows, including `project/doctor`, `project.wrap_up`, and a dedicated risk management job
- Service and package additions, including automatic Forgejo runner provisioning and the `lfs-s3` Git LFS transfer agent package
- Template improvements for new consumers, including an archetype configuration matrix and bundled Home Manager support in the Keystone OS template

### Changed

- Headscale ACL generation now derives more of its topology from Keystone service metadata, roles, identities, and ports
- Terminal agent integrations now publish more `ks` capabilities as skills and use the `~/repos` workspace convention consistently
- DeepWork project and executive assistant jobs were reorganized around presentation, wrap-up, note-writing, and issue-creation flows

### Fixed

- Photos, printer, journal-remote, notes, and perception integrations received follow-up fixes for path handling, TLS, menu responsiveness, and default notebook behavior
- Desktop context menus regained project submenu behavior, navigation, theme activation, and audio-device stability
- `ks` fixes resolved print CSS path issues, lock-sync parsing, lock repo export behavior, and docs-browser polish
- Immich and service fixes addressed remote ML binding, matplotlib cache placement, and ACL identity correctness

## [0.11.0] - 2026-03-28

### Added

- Unified observability stack across Grafana, Prometheus, Loki, and Alloy, with automated dashboard lifecycle support
- Walker/Elephant project launcher with project details, actions, icon caching, and project notes integration
- Hardware and account setup menus on desktop, plus linked monitor and audio-default flows
- FIDO2 enrollment, disk unlock status, and user capability options in the OS layer
- Agent metrics and logging improvements, including Loki-ready logfmt events and Prometheus metrics
- Account-aware terminal mail, calendar, and contacts modules, plus Grafana MCP exposure and related `ks` dashboard commands
- GitHub-based `Release` workflow and release-process documentation

### Changed

- Development mode and repo-linked scripts became more standardized through generated repo `AGENTS.md`, dev-mode linking helpers, and clearer keystone-developer conventions
- Executive assistant workflows absorbed portfolio-review functionality and added richer prioritization and project-statistics steps

### Fixed

- Desktop launcher and Walker fixes improved project loading, caching, keybindings, session selection, and menu performance
- Observability fixes removed conflicting node exporter flags and corrected dashboard provisioning details
- `ks` fixes improved Grafana API key discovery, URL resolution, warning behavior, and dev-mode dashboard sync
- Agent and notes fixes corrected zk permissions, textfile directory ownership, and default note repo behavior

## [0.10.0] - 2026-03-25

### Added

- `keystone.development` mode, with repo registry support and auto-discovery of managed repositories from flake inputs
- Smarter deployment workflows in `ks`, including `ks switch`, `ks update`, faster dev updates, and local Ollama diagnostics
- Zettelkasten note workflows for both humans and agents, including notebook scaffolding, note docs, and VCS-aware note handling
- Project discovery and session tooling improvements, including standardized repo and worktree paths, project discovery from zk hubs, and desktop context launchers
- Codex, DeepWork, and slash-command integrations across terminal tooling, including workflow skills and MCP wiring
- Demo and presentation tooling, including Slidev integration and optional OBS desktop support
- CalDAV-backed task and calendar support for users and agents

### Changed

- Terminal AI configuration moved toward centralized, repo-aware command generation and development-mode asset linking
- Repo layout conventions now treat `~/repos` and external worktrees as first-class paths across docs, tooling, and generated instructions
- The docs set was reorganized into category-driven structure with slimmer top-level agent instructions

### Fixed

- Dev-mode and pure-evaluation fixes corrected relative path handling, generated config materialization, home-manager bridging, and package list concatenation
- Agentctl and task-loop fixes improved codex execution flags, provider defaults, log rotation, bootstrap stability, and session environment handling
- `ks` and CLI fixes addressed recursion, detached submodule heads, repo discovery edge cases, and shellcheck issues
- DeepWork fixes improved issue drafting, screenshot evidence placement, notes handling, and external-runner behavior

## [0.9.0] - 2026-03-21

### Added

- Keystone TUI installer and ISO first-boot flow
- `ks agent` and `ks doctor`, including fleet and agent health checks
- Rootless agent execution improvements, including podman sandboxing, Grafana MCP support, built-in GitHub and Forgejo task sources, and agent archetype support
- Forgejo runner automation, native LFS support, host SSH key distribution, and SeaweedFS S3-compatible storage
- Shared conventions framework, generated agent instructions, DeepWork job library integration, and expanded DeepWork research workflows
- Centralized journal collection, external mail provider support, terminal notifications, and new cfait task-management support
- Initial perception-layer support for agents and terminal integrations

### Changed

- Keystone conventions and agent instructions moved into a repo-backed, tool-native structure instead of a single canonical generated file
- CLI build and lock flows were hardened around prompt-file handling, sudo timing, and argument-size limits
- OS and git-server modules moved closer to zero-config defaults for runners, journaling, and host-derived settings

### Fixed

- Agent, CLI, and git-server fixes resolved prompt quoting, `.git` URL parsing, rootless Podman setup, scheduler invocation, and runner package selection
- Immich and journal-remote follow-ups corrected remote ML behavior and host-derived journal configuration
- DeepWork research and milestone fixes addressed ingest quality, dependency wiring, and workflow guidance

## [0.8.0] - 2026-03-17

### Added

- Agent sub-module architecture: base, agentctl, desktop, chrome, dbus, mail-client, tailscale, ssh, notes, home-manager
- Each agent is a real Linux user (UID 4000+) with isolated userspace
- Password manager (rbw/Bitwarden) per agent with provisioning assertions
- Real email (himalaya) + structured task dispatch (agent-mail)
- Headless desktop (labwc + wayvnc) with Chromium remote debugging
- agentctl CLI: status, tasks, email, claude, vnc, provision, shell
- MCP server config with absolute Nix store paths
- Task loop integrity validation (TASKS.yaml)
- fetch-github-sources, fetch-forgejo-sources packages
- Desktop + Chrome enabled by default for all agents

### Changed

- Refactored monolithic `agents.nix` (2k+ lines) into focused sub-modules under `modules/os/agents/`

## [0.7.0] - 2026-03-16

### Added

- `keystone.keys` — SSH public key registry, declare once, reference everywhere
- Immich remote machine learning with auto-role detection (server vs worker)
- Git server SSH commit signing with pre-start key generation
- Terminal PIM tools: calendar (Calendula), contacts (cardamum), timer (comodoro), tea + fj for Forgejo
- Ollama service module + terminal AI integration
- TUI: dashboard, hosts, installer, ISO build

### Changed

- `ks` CLI defaults to `--lock`, supports multiple hosts, sequential deploy
- Agenix moved into keystone (no longer a separate flake input)

## [0.6.0] - 2026-03-14

### Added

- `ks` CLI — build, deploy, and manage NixOS configs across multiple hosts
- `keystone.hosts` — host identity with sshTarget, fallbackIP, buildOnRemote
- `keystone.services` — shared option namespace for cross-module service discovery
- Standardized Tailscale roles per host
- ISO installer refactored with `keystone.installer` option and `mkInstallerIso`
- Git server: adminUsers option, user-level API endpoints

### Changed

- `keystone.deploy.hosts` renamed to `keystone.hosts` (breaking)
- `_module.args.keystoneInputs` replaced with dedicated option
- Agent systemd service names standardized to `agent-NAME-JOB` pattern

## [0.5.0] - 2026-03-12

### Added

- Agent host filtering — resources only instantiate on the correct machine
- Agent auto-provisioning for mail and git (Forgejo)
- `hwrekey` script — serial-based YubiKey identity management with commit message support
- SSH key auto-load via agenix passphrase
- Remote agentctl dispatch via ET over Tailscale
- Agent task loop and agentctl improvements
- Comprehensive AGENTS.md documentation rewrite

### Changed

- Convention-over-config: auto-derive user email, mkDefault patterns

## [0.4.0] - 2026-03-06

### Added

- Unified `keystone.server.services.*` pattern — enable a service, get nginx + ACME + DNS automatically
- `mkServiceOptions` + `accessPresets` (tailscale, public, local, tailscaleAndLocal)
- Port conflict detection across enabled services
- Grafana service module with declarative alert rule provisioning
- Attic binary cache with auto-derived URL from `keystone.domain`
- SPEC-007 agent foundations: per-agent Bitwarden, Tailscale, SSH, mail, Chromium
- Hypervisor module (libvirt/KVM, OVMF, swtpm, SPICE, bridge networking)

### Changed

- `nh clean` replaces `nix.gc` for store optimisation
- Hyprland upgraded to v0.54.0
- Lanzaboote upgraded to v1.0.0

### Removed

- Harmonia binary cache (replaced by Attic)

## [0.3.0] - 2026-02-26

### Added

- `keystone.hardwareKey` module — YubiKey/FIDO2 with SSH public key material and age identities
- age-plugin-yubikey identity management for agenix secrets encryption
- SSH agent as systemd user service with 1h key expiry
- `keystone.domain` — shared TLD option (used by mail server + git server)
- Ext4 + LUKS + hibernation for laptops (PR #63) — enables thin-client paradigm
- Desktop: monitors module, printing, OOM killer, media players, ergonomic keybindings
- Terminal: mail TUI (himalaya), Helix markdown preview, ghostty terminfo, LLM agents
- OS: git server module, eternal terminal, airplay

### Added (docs)

- ZFS kernel compatibility documentation

## [0.2.0] - 2025-12-25

### Added

- Four-pillar module architecture: `modules/{os,desktop,terminal,server}` with clean separation
- Exported flake modules: `keystoneTerminal` and `keystoneDesktop` home-manager modules
- Desktop portability: Hyprland desktop migrated from nixos-config into Keystone
- Fast VM testing: `build-vm` script for rapid config iteration
- Terminal: zesh, yazi, csview, direnv
- MicroVM testing with microvm.nix integration
- GitHub Pages documentation site
- CI: all packages tested, Nix action v31, Copilot/devcontainer support

### Changed

- Module tree reorganized from flat layout to four-pillar structure

### Fixed

- UTF-8 encoding errors in TPM enrollment docs

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

[Unreleased]: https://github.com/ncrmro/keystone/compare/v0.12.0...HEAD
[0.12.0]: https://github.com/ncrmro/keystone/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/ncrmro/keystone/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/ncrmro/keystone/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/ncrmro/keystone/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/ncrmro/keystone/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/ncrmro/keystone/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/ncrmro/keystone/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ncrmro/keystone/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ncrmro/keystone/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ncrmro/keystone/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ncrmro/keystone/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ncrmro/keystone/compare/06fbb40...v0.1.0
