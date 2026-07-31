---
title: Desktop Keybindings
description: Core Keystone Desktop keybindings for launching apps, switching projects, and managing windows
---

# Desktop Keybindings

Keystone Desktop is designed around keyboard-first navigation.

For combined desktop and terminal movement, session switching, and Zellij tab navigation, see [Navigation](../navigation.md).

The launcher and desktop workflow center on a small set of bindings:

## Launchers and menus

- `$mod+Return` opens Ghostty
- `$mod+Space` opens Walker
- `$mod+Escape` opens the Keystone menu
- `$mod+K` opens the keybindings menu

## Walker prefixes

Once Walker is open, these prefixes switch directly to useful providers:

- `.` for files
- `=` for calculator
- `$` for clipboard history
- `/` for the provider list

Walker and Elephant together provide the backend for these desktop menus. See
[Walker](walker.md) for the launcher architecture and project navigation model.

## Window and workspace control

- `$mod+H` and `$mod+L` move focus horizontally
- `$mod+left/right/up/down` move focus between windows
- `$mod+Shift+left/right/up/down` swap windows
- `$mod+1` through `$mod+0` switch workspaces
- `$mod+Shift+1` through `$mod+Shift+0` move the current window to a workspace
- `$mod+Tab` and `$mod+Shift+Tab` move between workspaces
- `Alt+Tab` cycles through windows

## Utilities

- `$mod+Ctrl+V` opens the clipboard manager
- `$mod+Ctrl+E` opens the emoji and symbols picker
- `Print` starts a screenshot
- `Shift+Print` captures a smart screenshot to the clipboard
- `$mod+Print` opens the color picker

## Related docs

- [Navigation](../navigation.md)
- [Screenshots](screenshots.md)
- [Walker](walker.md)
- [Notes](../notes.md)
