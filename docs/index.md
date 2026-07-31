---
title: Keystone Documentation
description: Getting started with Keystone OS, the Keystone terminal module, and keystone-config
---

# Keystone Documentation

Keystone can be adopted in two ways:

- **Keystone OS** for full-machine ownership, including encrypted storage, services, users, and optional desktop tooling
- **The Keystone terminal module** for a portable developer environment on an existing macOS, Linux, or NixOS system

Most users should think in terms of a **`keystone-config`** repository. That repo is where you declare machines, users, enabled modules, and deployment settings.

## Choose your path

### Keystone OS

Choose Keystone OS when you want Keystone to manage the machine itself.

Use this path for:

- Servers
- Workstations
- Laptops
- Fresh NixOS installs
- Existing NixOS systems you want to reconfigure around Keystone modules

What you get:

- Disk layout and installation flow
- Secure Boot and TPM support
- ZFS-based storage defaults
- User management
- Optional desktop environment
- The Keystone terminal environment included for users who enable it

Start here:

- [ISO Generation](os/iso-generation.md)
- [Installer cache warming](os/installer-cache.md)
- [Keystone OS install](os/installation.md)
- [OS module reference](os/server.md)

### Keystone terminal module

Choose the Keystone terminal module when you want the Keystone developer experience without replacing your operating system.

Use this path for:

- macOS
- Existing Linux distributions
- Existing NixOS machines
- Remote development boxes
- Thin clients

What you get:

- Zsh, Helix, Zellij, Git, and core CLI tooling
- Reproducible development environments
- A consistent terminal workflow across machines

Start here:

- [Install the terminal environment](terminal/tui-install.md)
- [Terminal module overview](terminal/terminal.md)
- [Navigation guide](navigation.md)

## Core concept: `keystone-config`

`keystone-config` is the repo that captures your Keystone setup. It is your flake, your machine definitions, and your configuration history.

Create a new config repo from the Keystone template:

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

This template gives you:

- `flake.nix` with Keystone and Home Manager wired in
- `configuration.nix` with the main Keystone options scaffolded
- `hardware.nix` for machine-specific hardware settings
- `README.md` with the post-scaffold checklist

Once created, edit the generated files, search for `TODO:`, and choose whether that repo will drive:

- A full Keystone OS machine
- A desktop-enabled Keystone OS machine
- A smaller terminal-first setup that still reuses Keystone modules

## Recommended decisions

### If you are new to Keystone

Start with **one machine** and **one admin user** in `keystone-config`.

Recommended first decision:

- Use **Keystone OS** if you are provisioning a new server, workstation, or laptop
- Use the **terminal module** if you want Keystone’s CLI environment on a machine you already manage another way

### If you want the fastest safe first deployment

Use the template, keep the default single-machine structure, and work through:

1. [ISO Generation](os/iso-generation.md)
2. [Keystone OS install](os/installation.md)
3. [Terminal module overview](terminal/terminal.md)
4. [Navigation guide](navigation.md)

### If you are iterating or contributing

Keep development workflows separate from initial setup:

- [Developer workflow](terminal/tui-developer-workflow.md)
- [Thin client workflow](terminal/tui-developer-workflow-thin-client.md)
- [Testing procedures](os/testing-procedure.md)
- [VM testing](os/testing-vm.md)
- [ISO and OS VM testing](testing/iso-os-virtual-machine.md)

## Quick Links

- **[Milestones](milestones/)** — current product deliverables, mirrored from GitHub milestones
- **[Specs](specs/)** — normative requirement specs (`REQ-NNN-slug.md`)
- **[Release notes](releasing.md)** - Release process and stable-release reference
- **[Past releases](releases/)** — release artifacts, summaries, and changelogs per tag
- **[Project posts](posts.md)** - Working-backwards and narrative project material
- **[Research notes](research/universal-deepwork-job-library.md)** - Long-form supporting research captured in the docs tree
- **[Experimental features](experimental.md)** - Stability tiers and the `keystone.experimental` flag
- **[GitHub Repository](https://github.com/ncrmro/keystone)** - Source code and issue tracking
- **[Create `keystone-config`](#core-concept-keystone-config)** - Scaffold a new Keystone configuration repo

## Contributing

We welcome contributions! Areas where help is particularly needed:

- Documentation improvements
- Testing and bug reports
- Security auditing
- Module development
- Platform support

Please see our [GitHub repository](https://github.com/ncrmro/keystone) for details on how to get involved.

## Community & Support

- **Issues** - [GitHub Issues](https://github.com/ncrmro/keystone/issues)
- **Discussions** - [GitHub Discussions](https://github.com/ncrmro/keystone/discussions)
- **Security** - Report security issues privately via GitHub Security Advisories

## License

Keystone is open source software licensed under the [MIT License](https://github.com/ncrmro/keystone/blob/main/LICENSE).

---

_This documentation is continuously updated. For the latest information, please check the [GitHub repository](https://github.com/ncrmro/keystone)._
