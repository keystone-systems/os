# Research: Monitor Management During Presentations

**Relates to**: REQ-002 (Keystone Desktop, dt-monitor-001)

## Problem

No automated procedure for configuring monitors during presentations. Users must know `hyprctl` commands or hardware identifiers.

## Solution: Interactive Monitor Menu

The "Setup → Monitors" menu dynamically queries `hyprctl monitors -j` and provides:

1. List of connected displays with names/descriptions
2. Global "Mirror All" toggle
3. Per-monitor mirror selection
4. Resolution presets (e.g., 1080p for projector compatibility)

## Hyprland Mirroring

```bash
hyprctl keyword monitor "HDMI-A-1,preferred,auto,1,mirror,eDP-1"
```

## Auto-Mirror Configuration

When `keystone.desktop.monitors.autoMirror = true`, unknown monitors default to mirroring the primary display:

```
monitor = , preferred, auto, 1, mirror, [PRIMARY_MONITOR]
```

## Default Behavior (No Config)

Hyprland uses `monitor=,preferred,auto,1` — auto-detects all displays with preferred resolution. If detection fails, user may land on a secondary screen.
