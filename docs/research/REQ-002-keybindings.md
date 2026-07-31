# Research: Keybindings

**Relates to**: REQ-002 (Keystone Desktop)

## Documentation References

- Hyprland: https://wiki.hypr.land/Configuring/Binds/
- Ghostty: https://ghostty.org/docs/config/keybind
- Zellij: https://zellij.dev/documentation/keybindings.html
- Helix: https://docs.helix-editor.com/keymap.html

## Hardware Translation Table

| Action        | UHK (NixOS)             | Framework (NixOS) | QMK/ZMK (NixOS)           |
| ------------- | ----------------------- | ----------------- | ------------------------- |
| WM Focus Left | Fn2+J → Alt+J → Super+J | Alt+J → Super+J   | Lower+J → Alt+J → Super+J |
| WM Focus Down | Fn2+K → Alt+K → Super+K | Alt+K → Super+K   | Lower+K → Alt+K → Super+K |
| Previous Tab  | Mod+W → Ctrl+PgUp       | Ctrl+Shift+Tab    | Mod+W → Alt+W             |
| New Tab       | Mod+E → Ctrl+T          | Ctrl+T            | Mod+E → Alt+E             |
| Close Tab     | Mod+C → Ctrl+W          | Ctrl+W            | Mod+C → Alt+C             |

**Key mechanism**: `altwin:swap_alt_win` XKB option swaps Alt and Super at input level. Physical Alt → Super → Hyprland receives Super. All keyboards work identically with zero Nix config changes.

## UHK Layer Architecture

- **Fn2 layer** (right thumb): Sends Alt codes for Hyprland navigation
- **Mod layer**: Arrow keys via JKIL, tab navigation via WERC, browser nav via Super+J/L

## Design Principles

1. Mouse-free workflow for all development tasks
2. Home row optimization (J/K/I/L spatial, W/E/R/C tabs)
3. Modifier hierarchy: Super = window manager, Ctrl = application, Shift = modification
4. Adding a new keyboard requires only firmware config, zero Nix changes
