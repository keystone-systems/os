---
title: Functions
description: Keystone shell entrypoints and helper commands for terminal workflows
---

# Functions

Keystone Terminal includes a small set of shell-facing commands and helper
entrypoints that make the environment more usable than a plain package bundle.

## Key commands

- `ks` for Keystone repo-oriented workflows (including `ks secrets edit|sync|rekey`)
- `zs` for connecting to Zellij sessions through `zesh`

## What these commands do

- `ks` is the Keystone command entrypoint used for common repo and environment tasks; `ks secrets` covers sops editing and YubiKey-based rekeying (see `conventions/secrets.md`)
- `zs` provides fast Zellij session access

## Why these matter

The terminal module is not just a package set. It also installs the commands
that connect:

- notes,
- repos,
- sessions,
- secrets, and
- managed development workflows.

## Related docs

- [Terminal Module](terminal.md)
- [Shell Tools](shell-tools.md)
