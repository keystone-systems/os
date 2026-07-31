# ks

Interactive terminal interface for generating, validating, and deploying
Keystone NixOS infrastructure configurations.

## Vision

Keystone users currently set up new infrastructure by running
`nix flake init -t github:ncrmro/keystone` and manually filling in TODO
markers. This is error-prone and requires reading code comments to
understand available options.

The ks replaces this manual process with an interactive wizard
that:

1. Collects hardware and user information via guided prompts
2. Generates a complete, buildable NixOS flake with no TODO markers
3. Commits the config to git and optionally publishes to GitHub
4. Connects to a Keystone ISO installer and deploys via nixos-anywhere

## Phased Delivery

### Phase 1: Config Contract (current)

Establishes the output contract before writing TUI code:

- **REQ-001**: What files the TUI must produce
- **REQ-002**: What inputs drive generation (the data model)
- **REQ-003**: Automated validation for generated configs, ISO builds, and
  installer/first-boot end-to-end testing

Deliverable: a layered validation contract that covers template evaluation,
generated config builds, base and pre-baked ISO generation, fast VM-backed
installer and first-boot validation, and slower on-demand real ISO boot
validation.

### Phase 2: Interactive TUI + Publishing

Builds the interactive interface and git/GitHub integration:

- **REQ-004**: TUI prompts with SSH key auto-detection, hardware key
  detection, non-interactive JSON mode
- **REQ-005**: Git init, GitHub repo creation, plaintext password warnings

### Phase 3: Remote Deployment

Connects to target hardware and deploys:

- **REQ-006**: mDNS installer detection, nixos-anywhere deployment,
  progress display

## User Stories

### Personal Server

> "I bought a used Dell Optiplex. I want a secure NixOS server with ZFS,
> Secure Boot, and SSH access — without reading 200 lines of Nix config."

The TUI asks for hostname, disk ID, and SSH key, then generates a complete
config and deploys it to the Keystone ISO installer.

### Project Kubernetes Cluster

> "I need 3 identical worker nodes for a K3s cluster. I want to generate
> configs from a JSON template and deploy them in a loop."

Non-interactive JSON mode (REQ-004.5) accepts a config file, generates the
flake, and deploys to each node sequentially.

### Multi-Cloud Infrastructure

> "I run a workstation at home and a VPS in the cloud. I want both managed
> from the same config repo with different storage backends."

The TUI generates separate NixOS configurations within a single flake,
using ZFS for the workstation and ext4 for the VPS.

## Requirements

See [requirements/REQUIREMENTS.md](requirements/REQUIREMENTS.md) for the
full requirements index.

## Current validation status

The current worktree already has strong local TUI test coverage:

- `155` crate unit tests
- `4` config-generation integration tests
- `6` multi-screen flow tests
- `10` render snapshot tests
- `9` ignored Nix-backed integration tests for generated config and ISO validation

The remaining documented gap is VM-backed end-to-end validation for
installer mode, reboot, and first-boot reconciliation.
