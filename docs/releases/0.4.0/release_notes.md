# Keystone v0.4.0 — Observability & Efficiency

The server pillar matures with unified service management and real observability. Grafana arrives with declarative alert rules. Attic replaces Harmonia as the binary cache with convention-over-configuration defaults. The agent system begins taking shape with SPEC-007 landing per-agent Tailscale, Bitwarden, SSH, mail, and Chromium — but agents are still early.

## Highlights

- **Unified `keystone.server.services.*` pattern** — enable a service, get nginx + ACME + DNS automatically
- **`mkServiceOptions` + `accessPresets`** (tailscale, public, local, tailscaleAndLocal)
- **Port conflict detection** across enabled services
- **Grafana service module** with declarative alert rule provisioning
- **Attic binary cache** (replaces Harmonia) with auto-derived URL from `keystone.domain`
- **SPEC-007 agent foundations**: per-agent Bitwarden, Tailscale, SSH, mail, Chromium
- **Hypervisor module** (libvirt/KVM, OVMF, swtpm, SPICE, bridge networking)
- **`nh clean`** replaces `nix.gc` for store optimisation
- **Hyprland v0.54.0**, **lanzaboote v1.0.0**

## What's New

### Unified Service Management

The new `keystone.server.services.*` pattern is the centerpiece of this release. Enable a service like `keystone.server.services.immich.enable = true` and Keystone automatically configures nginx reverse proxy, ACME certificates, and DNS records. The `mkServiceOptions` helper standardizes service declarations, and `accessPresets` (tailscale, public, local, tailscaleAndLocal) control network access with a single option. Automatic port conflict detection prevents two services from accidentally binding to the same port.

### Observability

Grafana joins Keystone's server module with declarative alert rule provisioning. Default disk usage alerts are included out of the box — define thresholds in Nix and they're deployed alongside the service.

### Binary Cache

Attic replaces Harmonia as the binary cache, bringing garbage collection, automatic store initialization, and a URL auto-derived from `keystone.domain` (e.g., `cache.example.com`).

### Agent Foundations

SPEC-007 lands the first iteration of OS agents: per-agent Bitwarden (rbw), Tailscale, SSH, mail, and Chromium configurations. Each agent begins to receive its own identity, though the provisioning and autonomy features are still early.

### Hypervisor

The new hypervisor module provides libvirt/KVM with OVMF firmware (Secure Boot support), swtpm (TPM 2.0 emulation), SPICE display, and bridge networking. All `keystone.os.users` are automatically added to the `libvirtd` group.

### Dependency Updates

- Hyprland upgraded to v0.54.0
- Lanzaboote upgraded to v1.0.0

## Breaking Changes

- **Harmonia removed** — binary cache users must migrate to Attic (`keystone.server.services.attic`)

## Full Changelog

[v0.3.0...v0.4.0](https://github.com/ncrmro/keystone/compare/v0.3.0...v0.4.0)
