---
title: Fingerprint Unlock
description: Using fingerprint unlock with Keystone Desktop and hyprlock
---

# Fingerprint Unlock

Keystone Desktop enables fingerprint unlock through `hyprlock` when the
underlying hardware and system support it.

## How it works

The desktop lock screen is provided by `hyprlock`, and Keystone enables the
fingerprint path in the lock screen configuration.

At a high level:

- `hyprlock` provides the lock screen UI,
- fingerprint support is enabled in the lock screen settings, and
- the machine still needs working fingerprint hardware and user enrollment at
  the system level.

## What to expect

Fingerprint unlock is best treated as a convenience layer for unlock, not a
replacement for good account security.

You should still have:

- a normal account password,
- a working lock screen password path, and
- your fingerprint enrolled for the user you actually log in as.

## Keystone Desktop behavior

Keystone Desktop starts locked and uses `hyprlock` for unlock flows. If
fingerprint support is available on your machine, that unlock path is exposed
through the same lock screen.

If fingerprint support is unavailable or not enrolled, the password path still
works as normal.

## When to use it

Fingerprint unlock is most useful on laptops and workstations where:

- the hardware reader is supported on Linux,
- you unlock frequently during the day, and
- you still want a normal password-based fallback.

## Related docs

- [Desktop](../desktop.md)
- [Desktop Keybindings](keybindings.md)
- [Hardware Keys](../os/hardware-keys.md)
