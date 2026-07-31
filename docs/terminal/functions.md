---
title: Functions
description: Keystone shell entrypoints and helper commands for terminal workflows
---

# Functions

Keystone Terminal includes a small set of shell-facing commands and helper
entrypoints that make the environment more usable than a plain package bundle.

## Key commands

- `ks` for Keystone repo-oriented workflows
- `zs` for connecting to Zellij sessions through `zesh`
- `hwrekey` for age/YubiKey rekeying workflows

## What these commands do

- `ks` is the Keystone command entrypoint used for common repo and environment tasks
- `zs` provides fast Zellij session access
- `hwrekey` wraps the YubiKey-based agenix rekey workflow

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
