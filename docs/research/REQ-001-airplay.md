# Research: AirPlay Receiver on NixOS

**Date**: 2025-12-30
**Relates to**: REQ-001 (keystone.os.services.airplay)

## Problem

`shairport-sync` runs as a system user but needs access to the desktop user's PipeWire audio session. The system service cannot access the user's audio socket by default.

## Approach Tested: PipeWire TCP Socket

Enabled TCP listener on PipeWire and pointed `shairport-sync` at it via `PULSE_SERVER=tcp:127.0.0.1:4713`.

**Result**: Service connected successfully but desktop audio broke — the TCP listener config overwrote the default unix socket address instead of appending to it.

## Decision: User Service

Run `shairport-sync` as a **systemd user service** instead of a system service.

- Natively shares the user's PipeWire session (no permission hacks)
- Auto-starts when desktop session launches (greetd auto-login)
- Only runs when user is logged in (acceptable for workstations)
- Firewall ports still configured at system level: TCP 3689/5000, UDP 5353/6000-6009, high ports 32768-60999

## Key Findings

- PipeWire `server.address` in `extraConfig` replaces defaults rather than appending — must list both `tcp:` and `unix:native` if modifying
- `shairport-sync` works fine with `--output pa` when run as the desktop user
- Use `--sessioncontrol-allow-session-interruption=yes` for multi-device handoff
