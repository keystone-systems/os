---
title: Installer cache warming
description: How Keystone populates the public installer cache for starter ISO installs
---

# Installer cache warming

This document covers the **public installer cache warming path** for Keystone's
starter ISO and generated-template installs.

It is intentionally separate from the host-level binary cache services that a
user can enable on their own machines.

## What this cache is

Keystone starter installs pull from the public `ks-systems` Cachix cache by
default.

The release path warms that cache from CI by building the same generated
template host closures that `nixos-install` later realizes from the installer:

- generate the default template fixture with admin user `keystone`
- resolve the fixture's Linux installer targets
- build each `nixosConfigurations.<target>.config.system.build.toplevel`
- push the realized outputs to `ks-systems.cachix.org`

This keeps three things aligned:

- the generated template used in validation
- the published starter ISO
- the host closures the installer needs at install time

## What this cache is not

This is **not** the same thing as Keystone's host-level binary cache service
story.

It does not describe:

- the `binary-cache-client` module
- a self-hosted Attic service
- Harmonia
- machine-to-machine remote builders

Those are user- or fleet-level deployment choices. See
[Remote building and caching](remote-building-and-caching.md) for that surface.

## Why this exists

Building the ISO itself is not enough to guarantee a fast or low-memory install.

The live ISO contains the installer environment, but `nixos-install` still has
to realize the selected target host closure. If that closure is not already
available from substituters, the installer falls back to local builds.

That matters for the starter template because the target host closure includes
more than the live ISO closure, including:

- Home Manager outputs
- desktop/session packages
- generated Keystone assets
- AI tool packages such as `codex`, `claude-code`, `gemini-cli`, and `opencode`

Warming the target closure in CI is what keeps those paths out of the local
build set during install.

## Runtime behavior

The live installer environment trusts `ks-systems.cachix.org` by default, so it
can pull the warmed target closure during `nixos-install`.

Cache misses can still happen, so the live ISO also enables zram-backed swap to
make installer runs more resilient when a target path has to build locally.

## Related docs

- [ISO generation](iso-generation.md)
- [Remote building and caching](remote-building-and-caching.md)
- [Build platforms](build-platforms.md)
