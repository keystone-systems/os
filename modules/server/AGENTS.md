# Server Module — Editing Guide (`modules/server/`)

This guide covers conventions for editing the server module. For the full user-facing
reference, see `docs/server.md`.

## Service Pattern

All services use `mkServiceOptions` from `lib.nix`:

```nix
keystone.server.services.<name> = mkServiceOptions {
  description = "Service description";
  subdomain = "<name>";
  port = 8080;
  access = "tailscale";  # tailscale | tailscaleAndLocal | public | local
  websockets = true;
};
```

When enabled, the service auto-registers in `_enabledServices` and nginx/dns modules
generate `virtualHosts` and DNS records automatically.

## Access Presets

| Preset | Networks |
|--------|----------|
| `tailscale` | 100.64.0.0/10, fd7a:115c:a1e0::/48 |
| `tailscaleAndLocal` | Tailscale + 192.168.1.0/24 |
| `public` | No restrictions |
| `local` | 192.168.1.0/24 only |

## Available Services

| Service | Subdomain | Port | Access |
|---------|-----------|------|--------|
| attic | cache | 8199 | tailscale |
| immich | photos | 2283 | tailscale |
| vaultwarden | vaultwarden | 8222 | tailscale |
| forgejo | git | 3001 | tailscale |
| grafana | grafana | 3002 | tailscale |
| prometheus | prometheus | 9090 | tailscale |
| loki | loki | 3100 | tailscale |
| headscale | mercury | 8080 | **public** |
| miniflux | miniflux | 8070 | tailscale |
| mail | mail | 8082 | tailscale |
| adguard | adguard.home | 3000 | tailscaleAndLocal |
| seaweedfs | s3 | 8333 | tailscale |
| journal-remote | journal | dynamic† | tailscale |

†`journal-remote` auto-activates when `services.journald.remote.enable = true`. It has no
`keystone.server.services.*` option; its port is read directly from
`services.journald.remote.port` (NixOS default: 19532).

## Adding a New Service

1. Create `modules/server/services/<name>.nix` using `mkServiceOptions`
2. Register in `_enabledServices` when enabled
3. Import in `modules/server/default.nix`

## DNS Pipeline

```
service enabled
  → registers in keystone.server._enabledServices
  → dns.nix generates records to keystone.server.generatedDNSRecords
  → headscale host imports via keystone.headscale.dnsRecords
  → headscale distributes to all tailnet clients via MagicDNS
```

## Domain Architecture

`keystone.domain` is the shared TLD for both server services and OS agents:

```nix
keystone.domain = "example.com";
keystone.server.services.immich.enable = true;  # → photos.example.com
keystone.os.agents.drago = {};                   # → agent-drago@example.com
```

Each service has a `subdomain` option (defaults to service name, can be overridden).

## Important Patterns

**Port conflict detection**: An assertion fails automatically if two enabled services
share a port — no manual check needed.

**Warning vs assertion**: Server modules emit `warnings` (not `assertions`) for missing
recommended config (e.g., `keystone.domain == null`). Evaluation always succeeds;
only deploy warns.

**Legacy modules**: `vpn`, `mail`, `headscale` use the old
pattern (configure service only; consumer handles nginx/TLS/access). Migration to
`services.*` pattern is pending.
