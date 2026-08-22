---
title: Remote building and signed binary caches
description: Reuse Nix build results across a Keystone fleet
---

# Remote building and signed binary caches

Keystone supports two complementary ways to reuse build work: direct SSH
closure transfer during deployment and HTTP signed binary caches.

## Shared Keystone cache

Keystone systems trust the public `ks-systems` Cachix cache by default:

```nix
keystone.os.binaryCaches.ksSystems.enable = true;
```

Disable it explicitly when a fleet does not want the shared cache:

```nix
keystone.os.binaryCaches.ksSystems.enable = false;
```

The `ksSystems` interface remains separate so existing consumers keep their
current defaults.

## Fleet caches

Add any HTTPS Nix binary cache with its signing public key:

```nix
keystone.os.binaryCaches.extra.ocean = {
  enable = true;
  url = "https://s3.example.com/nix-cache";
  publicKey = "example-cache-1:AAAA...=";
};
```

Enabled fleet entries are prepended to `nix.settings.substituters` and
`nix.settings.trusted-public-keys`, ahead of values declared elsewhere.
`cache.nixos.org` remains available through the NixOS default. Disabled entries
have no effect. An enabled entry MUST set both `url` and `publicKey`, and its URL
MUST use credential-free HTTPS. URI user-info and credential-bearing query
parameters are rejected.

The same enabled caches are passed into Keystone's Podman agent sandbox so
containerized builds use the system's trust policy.

Keystone holds only cache-reader configuration. Cache writer credentials and
private signing keys MUST remain in the publishing system, such as a trusted CI
runner or the fleet's secret store.

## Publishing with native Nix

Nix can publish recursively to an S3-compatible store after all desired
closures build successfully:

```bash
nix copy --to \
  "s3://nix-cache?endpoint=s3.example.com&scheme=https&region=us-east-1&addressing-style=path&secret-key=$signing_key" \
  /nix/store/…
```

The `secret-key` store parameter points at the publisher's temporary signing
key. Keep that file mode `0600` and remove it after publication. Clients need
only the corresponding public key.

## Deployment fallback

`ks-dev` builds the selected host closure and transfers it directly over SSH
when the target does not already have its paths. A binary-cache miss or outage
therefore does not remove the normal deployment path; it only removes the
substitution optimization.

## Related documentation

- [Installer cache warming](installer-cache.md)
- [Build platforms](build-platforms.md)
- [Nix binary cache manual](https://nix.dev/manual/nix/latest/package-management/binary-cache-substituter)
