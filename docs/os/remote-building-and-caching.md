---
title: Remote Building and Caching
description: Share Nix builds across multiple NixOS machines to avoid redundant compilation
---

# Remote Building and Caching

## Overview

With multiple NixOS machines (workstations, laptops, NAS, VPS), each rebuilds many of the same derivations independently. A kernel update on one machine means every other machine rebuilds the same kernel from source. The goal: **build once, share everywhere**.

## Default Keystone Cache

Keystone systems trust the public `ks-systems` Cachix cache by default. No extra
host configuration is required to pull from it:

```nix
keystone.os.enable = true;
```

To disable that default on a specific host:

```nix
keystone.os.binaryCaches.ksSystems.enable = false;
```

The default `ks-systems` cache is additive. You can still layer a self-hosted Attic
cache on top for private or deployment-specific artifacts.

GitHub Actions can read from this public cache without credentials. If you want CI to
publish new paths, put `CACHIX_AUTH_TOKEN` on a protected environment such as
`release` and only assign that environment to the publishing workflow job.

For the separate release/installer path that warms starter-template host closures
into `ks-systems`, see [Installer cache warming](installer-cache.md).

## Approaches Considered

### Harmonia (current)

Harmonia serves the local Nix store as an HTTP binary cache. Any machine on the network can pull cached store paths from the Harmonia host.

**Limitations:**

- Only caches what was already built on the Harmonia host — it doesn't build anything itself
- Doesn't solve "who builds first" — if the NAS hasn't built a derivation yet, other machines can't pull it
- Single point of availability — the Harmonia host must be online and reachable
- Cache is ephemeral — tied to the host's local store, lost if the machine is rebuilt or garbage collected

### Nix Remote Builders (`nix.buildMachines`)

Nix can offload builds to a remote machine via SSH. The local daemon sends the derivation to the builder, which compiles it and sends back the result.

**Shortcomings:**

- **Root SSH access required** — the Nix daemon runs as root and connects to the builder over SSH. This means either root-to-root SSH or a dedicated builder user added to `nix.settings.trusted-users`
- **Passphrase-free SSH keys** — the Nix daemon can't use `ssh-agent`, so builder SSH keys must be unencrypted. This conflicts with the goal of requiring hardware key authentication for root access
- **Tight coupling** — if the builder is offline, builds fail. The local machine can't fall back to building locally without manual intervention
- **Results stay on the builder** — built paths land in the builder's store. Other machines still need a separate binary cache to access them, which brings us back to square one
- **Complex key management** — each builder needs its own signing key pair, and every client must trust every builder's public key

### Attic (chosen)

[Attic](https://github.com/zhaofengli/attic) is a multi-tenant Nix binary cache backed by S3-compatible object storage. Builders push to Attic after building locally; all other machines pull from it as a substituter.

**Advantages:**

- **No machine-to-machine SSH** — builders push over HTTPS using API tokens, not SSH keys
- **Any machine can be a builder** — workstation, laptop, CI runner. Anything that builds and runs `attic watch-store` automatically contributes to the cache
- **Durable storage** — S3 backend means the cache survives host rebuilds, garbage collection, and hardware failures
- **`attic watch-store`** — runs as a systemd service, watches the local Nix store for new paths and pushes them in the background. Non-blocking, no post-build hooks needed
- **Managed signing** — the Attic server signs NARs on retrieval. Individual builders never need signing keys, simplifying key management to a single server key
- **Multi-tenant** — supports multiple caches (e.g., `nixos-config`, `project-specific`) with independent access controls

## Architecture

```
                          ┌──────────────┐
                          │ Attic Server │
                          │  (atticd)    │
                          │              │
                          │  PostgreSQL  │
                          │  + S3 Store  │
                          └──────┬───────┘
                                 │ HTTPS
                    ┌────────────┼────────────┐
                    │            │             │
              ┌─────┴─────┐ ┌───┴────┐  ┌─────┴─────┐
              │Workstation│ │ Laptop │  │    VPS    │
              │           │ │        │  │           │
              │ builds    │ │ builds │  │ pulls     │
              │ + pushes  │ │+ pushes│  │ only      │
              └───────────┘ └────────┘  └───────────┘

   Builder machines:      attic watch-store → pushes to Attic
   All machines:          nix.settings.substituters ← pulls from Attic
```

**Attic server placement options:**

- **NAS (self-hosted)** — `atticd` with PostgreSQL, using local storage or S3 (e.g., MinIO)
- **Cloud-hosted** — `atticd` on a VPS with S3-compatible backend (Cloudflare R2, Tigris, AWS S3)
- **Hybrid** — server anywhere, S3 storage elsewhere. The server is stateless aside from PostgreSQL metadata

## Setup Guide

### Server (Keystone module)

Enable the Attic server via keystone:

```nix
keystone.server.services.attic.enable = true;

# Token signing key (agenix secret)
age.secrets.attic-server-token-key = {
  file = "${inputs.agenix-secrets}/secrets/attic-server-token-key.age";
};
```

The `attic-server-token-key` secret must contain `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64-key>`.

### Post-Deployment: Manual Cache Creation

After the first deploy, the Attic server runs but has **no cache**. You must create one manually:

1. **Generate an admin token** on the server host:

   ```bash
   sudo atticd-atticadm make-token --sub "admin" --validity "10y" \
     --push "*" --pull "*" --create-cache "*" --delete-cache "*" \
     --configure-cache "*" --configure-cache-retention "*"
   ```

2. **Login and create the cache**:

   ```bash
   attic login cache https://cache.example.com <admin-token>
   attic cache create cache:main
   ```

3. **Retrieve the public signing key**:

   ```bash
   curl -s https://cache.example.com/main/nix-cache-info
   ```

   The `StoreDir` and `WantMassQuery` fields confirm the cache works. The signing public key is shown in the output.

4. **Set the public key** in your NixOS config so all machines trust the cache:

   ```nix
   keystone.binaryCache = {
     enable = true;
     url = "https://cache.example.com";
     publicKey = "main:AAAA...=";  # from nix-cache-info
   };
   ```

5. **Generate push tokens** for builder machines. Store these as agenix secrets (`attic-push-token`).

### Client (all machines)

1. **Login to the Attic server**:

   ```bash
   attic login server https://attic.example.com <token>
   ```

2. **Add the cache as a substituter**:
   ```bash
   attic use server:nixos-config
   ```
   This modifies `~/.config/nix/nix.conf` to add the cache URL and public key. For NixOS system-level configuration:
   ```nix
   nix.settings = {
     substituters = [ "https://attic.example.com/nixos-config" ];
     trusted-public-keys = [ "nixos-config:AAAA...=" ];
   };
   ```

### Designating a Builder

Any machine that runs `attic watch-store` automatically pushes everything it builds:

```bash
attic watch-store server:nixos-config
```

As a systemd service (recommended):

```nix
systemd.services.attic-watch-store = {
  description = "Attic watch-store";
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.attic-client}/bin/attic watch-store server:nixos-config";
    Restart = "on-failure";
    RestartSec = 10;
    # Credentials loaded from environment file or agenix
  };
};
```

### Why `watch-store` over `post-build-hook`

Nix supports a [`post-build-hook`](https://nixos.org/manual/nix/stable/advanced-topics/post-build-hook) that runs a script after each build. While this can push to a cache, it has drawbacks:

- **Blocking** — the hook runs synchronously, delaying the next build
- **Fragile** — if the push fails (network issue), the build is still marked as succeeded but the cache is incomplete
- **Per-build overhead** — each derivation triggers a separate push, no batching

`attic watch-store` monitors the store via inotify and pushes asynchronously in the background. Builds are never blocked, and transient failures are retried automatically.

## Migration from Harmonia

Attic and Harmonia can coexist during transition:

1. **Add Attic as a substituter** on all machines alongside the existing Harmonia URL
2. **Start `attic watch-store`** on builder machines — new builds start populating Attic
3. **Verify** that machines pull from Attic successfully (`nix path-info --store https://attic.example.com/nixos-config /nix/store/...`)
4. **Remove Harmonia** once the Attic cache is warm and all machines are configured:
   - Disable `keystone.server.binaryCache` on the NAS
   - Remove `keystone.binaryCacheClient` from all hosts
   - Remove the harmonia signing key from agenix secrets

The existing `keystone.binaryCacheClient` module pattern (URL + public key) maps directly to how Attic clients are configured, so the migration is straightforward.

## Future Work

- **`keystone.server.attic`** — NixOS module for the Attic server (`atticd` + PostgreSQL + S3 config + token management), following the pattern of `keystone.server.binaryCache`
- **`keystone.attic`** — Client module for cache substituter config + `attic watch-store` systemd service, replacing `keystone.binaryCacheClient`
- **CI integration** — GitHub Actions runners push to Attic, so CI-built paths are cached for all machines
- **Cache garbage collection** — Attic supports retention policies to manage S3 storage costs
- **Per-project caches** — Separate caches for different flakes (e.g., `nixos-config`, `keystone`, project-specific)

## References

- [Attic GitHub](https://github.com/zhaofengli/attic)
- [Attic Documentation](https://docs.attic.rs/)
- [Nix post-build-hook manual](https://nixos.org/manual/nix/stable/advanced-topics/post-build-hook)
- [NixOS Wiki: Binary Cache](https://nixos.wiki/wiki/Binary_Cache)
