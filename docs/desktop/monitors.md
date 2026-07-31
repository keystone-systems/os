---
title: Monitors
description: Configuring displays and monitor behavior in Keystone Desktop
---

# Monitors

Keystone Desktop configures displays through the `keystone.desktop.monitors`
options.

## Core options

```nix
keystone.desktop.monitors = {
  primaryDisplay = "eDP-1";
  autoMirror = true;
  settings = [
    ", preferred, auto, 1"
  ];
};
```

## What each option does

- `primaryDisplay` sets the display that unknown monitors should mirror from
- `autoMirror = true` mirrors new or unknown displays to the primary display
- `settings` is a list of static Hyprland monitor definitions

## Typical laptop setup

```nix
keystone.desktop.monitors = {
  primaryDisplay = "eDP-1";
  autoMirror = true;
  settings = [
    "eDP-1, preferred, auto, 1.6"
  ];
};
```

This gives you a stable built-in display configuration while still making
external displays usable immediately when attached.

## Typical desk setup

```nix
keystone.desktop.monitors = {
  primaryDisplay = "DP-1";
  autoMirror = false;
  settings = [
    "DP-1, preferred, 0x0, 1"
    "HDMI-A-1, preferred, 2560x0, 1"
  ];
};
```

This is the pattern to use when you want explicit multi-monitor layout instead
of automatic mirroring.

## When to use auto-mirror

Use `autoMirror = true` when:

- you are on a laptop,
- you move between docks or unknown displays, or
- you want new displays to work without per-monitor tuning.

Use `autoMirror = false` when:

- you have a stable desk setup, and
- you want fixed positions and scale for multiple displays.

## Related docs

- [Desktop](../desktop.md)
- [Desktop Keybindings](keybindings.md)
- [Waybar Configuration](waybar-configuration.md)
