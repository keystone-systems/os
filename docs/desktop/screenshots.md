---
title: Screenshots
description: Capture screenshots on Keystone Desktop, sync them to ocean, and search them through Immich OCR
---

# Screenshots

Keystone Desktop includes a screenshot workflow built on `grim`, `slurp`, and
`satty`.

By default, screenshots are written to `KEYSTONE_SCREENSHOT_DIR`, then
`XDG_PICTURES_DIR`, then `~/Pictures`.

## Capture

The default screenshot command is `keystone-screenshot`.

Common ways to use it:

- `Print` starts a screenshot capture flow.
- `Shift+Print` captures a smart screenshot to the clipboard.
- `keystone-screenshot` runs the default smart mode.
- `keystone-screenshot region` captures a selected region.
- `keystone-screenshot windows` captures a window rectangle.
- `keystone-screenshot fullscreen` captures the focused monitor.

In the save flow, Keystone writes PNG files with names like:

```text
screenshot-2026-04-03_06-23-00.png
```

## Local storage

Keystone resolves the screenshot output directory in this order:

1. `KEYSTONE_SCREENSHOT_DIR`
2. `XDG_PICTURES_DIR`
3. `~/Pictures`

To inspect the current effective location:

```bash
[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
printf '%s\n' "${KEYSTONE_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
```

## Immich sync

Keystone now syncs screenshots through the Rust `ks` CLI:

```bash
ks screenshots sync
```

This command:

- reads screenshots from `KEYSTONE_SCREENSHOT_DIR`, `XDG_PICTURES_DIR`, or `~/Pictures`
- uploads PNG screenshots to Immich
- adds them to a Screenshots album for the current account
- tags each uploaded screenshot with source, host, and account metadata

Common usage:

```bash
ks screenshots sync
ks screenshots sync --directory ~/Pictures
ks screenshots sync --album-name "Screenshots - alice"
```

## Immich OCR search

After screenshots are uploaded to Immich, they are searchable through the same
photo index as the rest of the library.

Current manual flow:

1. Run `ks screenshots sync`.
2. Wait for Immich to finish indexing OCR and metadata.
3. Search locally with `ks photos search`.

Example:

```bash
export IMMICH_URL="https://photos.ncrmro.com"
export IMMICH_API_KEY="..."
ks photos search --text "known text from screenshot" --type screenshot
```

## Current caveats

- Screenshot OCR search depends on Immich library attachment and indexing, not
  only on the upload step.

## Related docs

- [Desktop](../desktop.md)
- [Desktop Keybindings](keybindings.md)
- [Screen Recording](screen-recording.md)
