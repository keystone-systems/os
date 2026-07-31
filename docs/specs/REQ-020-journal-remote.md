# REQ-020: Centralized Journal Collection

Adds native systemd journal forwarding across the keystone fleet. When one
host enables journal collection, all other hosts automatically forward their
journals to it via `systemd-journal-upload`. This gives operators a single
place to query logs from any host without SSH-ing into each machine,
complementing the existing Loki stack with raw journal access.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a keystone operator, I want all host journals forwarded to a central
server so that I can diagnose issues across the fleet from one machine
without SSH-ing into each host individually.

## Architecture

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  ncrmro-workstation│     │     maia         │     │    mercury       │
│                  │     │                  │     │                  │
│ journal-upload ──┼─┐   │ journal-upload ──┼─┐   │ journal-upload ──┼─┐
└──────────────────┘ │   └──────────────────┘ │   └──────────────────┘ │
                     │                        │                        │
                     │  HTTPS → journal.<domain>                      │
                     │                        │                        │
                     ▼                        ▼                        ▼
              ┌─────────────────────────────────────────────────┐
              │                   ocean                         │
              │                                                 │
              │  nginx (HTTPS :443) → 127.0.0.1:19532           │
              │  systemd-journal-remote (HTTP, localhost only)  │
              │  /var/log/journal/remote/                       │
              │    ├── remote-ncrmro-workstation.journal        │
              │    ├── remote-maia.journal                      │
              │    └── remote-mercury.journal                   │
              │                                                 │
              │  journalctl --directory /var/log/journal/remote │
              │  (query any host's logs locally)                │
              └─────────────────────────────────────────────────┘
```

## Affected Modules

- `modules/os/journal-remote.nix` — **new**: server-side receiver + client-side upload, auto-wired
- `modules/os/default.nix` — import the new module
- `modules/hosts.nix` — used to derive which host is the journal server

## Requirements

### Server (Journal Receiver)

**REQ-020.1** The module MUST expose a `keystone.os.journalRemote.server.enable`
option that activates `systemd-journal-remote` on the host.

**REQ-020.2** When `server.enable` is true, the module MUST configure
`services.journald.remote` with an HTTP listener on the configured port.

**REQ-020.3** The default listen port MUST be `19532` (the systemd-journal-remote
default).

**REQ-020.4** The listen address MUST default to `0.0.0.0` and SHOULD be
overridable via `keystone.os.journalRemote.server.listenAddress`.

**REQ-020.5** Remote journals MUST be stored under
`/var/log/journal/remote/` with per-host filenames.

**REQ-020.6** At most one host in the fleet MUST enable `server.enable`.
The module SHOULD emit an assertion if multiple hosts enable it within the
same nixos-config evaluation.

### Client (Journal Upload)

**REQ-020.7** When any host in the fleet has `server.enable = true`, all
OTHER hosts MUST automatically enable `systemd-journal-upload` pointing
to the server host.

**REQ-020.8** The upload URL MUST be derived from the server host's
Tailscale hostname or `sshTarget` from `keystone.hosts`, NOT hardcoded.

**REQ-020.9** The client MUST NOT enable journal-upload on the server
host itself (no self-forwarding loop).

**REQ-020.10** The client SHOULD retry on transient connection failures
using systemd's built-in retry logic.

**REQ-020.11** The client MAY be explicitly disabled per-host via
`keystone.os.journalRemote.upload.enable = false` for hosts that should
not forward (e.g., ephemeral VMs, test boxes).

### Configuration

**REQ-020.12** The module MUST expose options at `keystone.os.journalRemote`.

```nix
keystone.os.journalRemote = {
  server = {
    enable = false;          # Enable journal-remote receiver
    port = 19532;            # Listen port
    listenAddress = "0.0.0.0";
  };
  upload = {
    enable = true;           # Auto-forward to fleet's journal server
    # URL is auto-derived — no manual configuration needed
  };
};
```

**REQ-020.13** When `server.enable` is false on all hosts and
`upload.enable` is true, the upload service MUST NOT be activated
(graceful no-op when no server exists).

### Transport & Security

**REQ-020.14** Transport MUST use HTTPS via the nginx reverse proxy when
`keystone.domain` is set. The nginx vhost (`journal.<domain>`) terminates
TLS using the ACME wildcard certificate and proxies to the local
`systemd-journal-remote` HTTP listener. When no domain is configured,
the module falls back to plain HTTP over the Tailscale mesh.

**REQ-020.15** When using nginx proxy, access MUST be restricted to
Tailscale IP ranges (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`) via nginx
access controls. When using direct HTTP (no domain), the server SHOULD
restrict incoming connections to the Tailscale interface via firewall rules.

**REQ-020.16** The module MUST NOT use mTLS certificates — Tailscale
handles authentication and nginx provides HTTPS termination.

### Integration

**REQ-020.17** The module MUST coexist with the existing Loki log
pipeline. Journal-remote provides raw journal access; Loki provides
structured querying. They are complementary.

**REQ-020.18** The `ks doctor` workflow SHOULD check that
`systemd-journal-upload` is active on client hosts and that
`systemd-journal-remote` is active on the server host.

**REQ-020.19** The journal server host SHOULD be queryable from
`ks agent` / `ks doctor` sessions for cross-host log diagnosis without
SSH:

```bash
journalctl --directory /var/log/journal/remote/ \
  -u <service> --since '1 hour ago'
```

### Storage

**REQ-020.20** The server SHOULD support a configurable maximum disk
usage for remote journals via `keystone.os.journalRemote.server.maxDisk`.

**REQ-020.21** The default `maxDisk` SHOULD be `10G`.

**REQ-020.22** The module SHOULD configure `journald.conf` system
max usage on the server to enforce the limit.

## Edge Cases

- **Server host offline**: Upload clients buffer locally and retry when
  the server comes back. No data loss for the retry window (systemd
  journal-upload tracks cursor position).
- **New host added**: Automatically picks up the journal server from
  the shared `keystone.hosts` configuration — no manual wiring.
- **Server host changes**: Updating `server.enable` on a different host
  causes all clients to re-point automatically on next deploy.
- **Ephemeral VMs / test boxes**: Set `upload.enable = false` to exclude.
