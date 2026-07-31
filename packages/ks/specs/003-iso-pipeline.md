# Spec: ISO Pipeline

## Stories Covered

- US-007: Build ISO installers with baked-in agenix secrets
- US-008: Detect and deploy to Keystone ISO instances

## Affected Modules

- `packages/ks/src/components/iso.rs` — ISO build + write to USB
- `packages/ks/src/components/deploy.rs` — ISO discovery + nixos-anywhere deployment
- `packages/ks/src/template.rs` — `generate_iso_flake_nix` (already implemented)
- `packages/ks/src/app.rs` — `AppScreen::Iso` and `AppScreen::Deploy` routing
- `modules/iso-installer.nix` — `keystone.nixosModules.isoInstaller` (already implemented)
- `packages/ks/Cargo.toml` — needs mDNS crate for ISO discovery

## Existing State

The `IsoScreen` already supports:

- **Phase SelectTarget**: listing USB devices + ~/Downloads
- **Phase Building**: runs `nix build .#iso` in the active repo
- **Phase Writing**: `dd` to USB or `cp` to ~/Downloads
- **Phase Done/Failed**

The `generate_iso_flake_nix` function already produces a flake that:

- Uses `keystone.nixosModules.isoInstaller`
- Embeds target config files at `/etc/keystone/install-config/`
- Accepts SSH keys via `keystone.installer.sshKeys`

The deploy flow already exists in `src/components/deploy.rs`. This spec
remains the normative contract for discovery, manual fallback, and
`nixos-anywhere` execution behavior.

## Gaps to Implement

### US-007: Agenix Secrets Baking

The current ISO build does not include agenix secrets. The agenix-secrets integration requires:

1. Determining the path to the user's secrets repo
2. Copying or symlinking the secrets into the ISO build directory as `agenix-secrets/`
3. Wiring the secrets path into the generated ISO flake

### US-008: ISO Instance Discovery and Deployment

The current implementation already includes a `Deploy` screen. Remaining
work in this area MUST follow the contract below rather than introducing
an alternate deployment surface.

## Data Models

### `IsoTarget` (existing — `src/components/iso.rs`)

| Field  | Type     | Notes                    |
| ------ | -------- | ------------------------ |
| label  | `String` | Display name             |
| path   | `String` | Device path or file path |
| is_usb | `bool`   | USB vs file destination  |
| size   | `String` | Human-readable size      |

### `AgenixSecretsConfig` (new — `src/template.rs` or new module)

| Field             | Type             | Notes                                                  |
| ----------------- | ---------------- | ------------------------------------------------------ |
| secrets_repo_path | `PathBuf`        | Absolute path to the user's agenix-secrets repo        |
| secrets_subdir    | `Option<String>` | Subdirectory within the secrets repo; defaults to root |

### `IsoInstanceDiscovery` (new — `src/components/deploy.rs`)

| Field          | Type              | Notes                             |
| -------------- | ----------------- | --------------------------------- |
| hostname       | `String`          | mDNS hostname or user-provided    |
| ip_address     | `String`          | Discovered or manually entered IP |
| discovered_via | `DiscoveryMethod` | `Mdns` \| `Manual`                |

### `DeployTarget` (new — `src/components/deploy.rs`)

| Field           | Type                   | Notes                          |
| --------------- | ---------------------- | ------------------------------ |
| instance        | `IsoInstanceDiscovery` | The discovered ISO instance    |
| config_hostname | `String`               | Target nixosConfigurations key |
| ssh_key_path    | `Option<PathBuf>`      | SSH key to use for deployment  |

## Behavioral Requirements

### ISO Build with Agenix Secrets (US-007)

1. The ISO screen MUST offer a "secrets integration" option before building.
2. When secrets integration is enabled, the TUI MUST prompt for the path to the agenix-secrets
   repository (defaulting to `~/.keystone/secrets/` if it exists).
3. The TUI MUST copy the secrets repository into the ISO build directory at `agenix-secrets/`
   before triggering `nix build`.
4. The generated ISO flake MUST reference the `agenix-secrets/` directory so the installer
   can access secrets during installation.
5. The TUI MUST verify that the secrets repo contains an `agenix.nix` or `secrets.nix` file
   before proceeding — if absent, MUST warn the user but allow building without secrets.
6. The built ISO MUST boot and install without requiring manual secret entry (end-to-end
   requirement — verified via manual test during development).
7. ISO build MUST work when initiated from macOS by delegating to a configured remote builder
   (the TUI MUST detect if Nix remote build is available; if not, display a helpful message).

### ISO Instance Discovery (US-008)

8. The deploy screen MUST attempt mDNS discovery for Keystone ISO instances on the local
   network by querying for `_keystone-iso._tcp.local` service records.
9. mDNS discovery MUST run for a configurable timeout (default 10 seconds) before showing
   results (discovered + manual entry option).
10. If mDNS discovery finds no instances, the TUI MUST offer a manual IP address entry field.
11. The TUI MUST support both discovered and manually entered targets simultaneously in the
    same list.
12. The TUI MUST display each discovered instance with: hostname, IP address, and discovery
    method (mDNS \| Manual).

### Deployment (US-008)

13. The TUI MUST invoke `nixos-anywhere --flake .#<hostname> root@<ip>` to deploy to a
    discovered ISO instance.
14. Before invoking nixos-anywhere, the TUI MUST:
    - Verify that `nixos-anywhere` is available in PATH.
    - Verify SSH connectivity to the target IP (port 22).
    - Confirm the selected nixos-config hostname matches the intended target.
15. The TUI MUST display deployment progress by streaming nixos-anywhere stdout/stderr to a
    scrollable output pane.
16. The TUI MUST display a clear success or failure status after deployment completes.
17. The TUI MUST auto-detect local SSH keys from `~/.ssh/*.pub` and offer them for deployment.
18. Deployment MUST NOT proceed without explicit user confirmation ("Deploy to 192.168.1.42?").

### Error Handling

19. If `nix build` fails during ISO creation, the TUI MUST show the last 20 lines of stderr
    and transition to `IsoPhase::Failed`.
20. If nixos-anywhere exits non-zero, the TUI MUST show the error output and allow the user
    to retry.
21. If mDNS discovery crashes (e.g., no network interface), the TUI MUST fall back to manual
    entry silently (no panic).

## Edge Cases

- **macOS build path**: `nixos-anywhere` is Linux-only. When running on macOS, the TUI MUST
  detect this and use the nixos-anywhere `--build-on-remote` flag, delegating the build to
  the target machine or a configured remote builder.
- **Secrets repo not found**: If the provided secrets path doesn't exist, the TUI MUST show
  an error before touching any build files.
- **USB write permission**: `dd` requires root on Linux. The TUI MUST check `/dev/<device>`
  write permissions before starting the write phase and advise `sudo` if needed.
- **ISO instance behind firewall**: If mDNS is blocked, manual IP is the only path. The TUI
  MUST make manual entry the prominent fallback, not a buried option.
- **Multiple ISO instances**: If mDNS discovers multiple instances, the TUI MUST allow
  selecting which one to deploy to.

## UI Mockups

### ISO Screen (SelectTarget phase, with secrets option)

```
┌─ Build ISO Installer ────────────────────────────────────────────────────┐
│                                                                          │
│  Configuration: ocean (x86_64-linux)                                     │
│                                                                          │
│  Secrets Integration                                                     │
│  ○ No secrets — install without agenix secrets                           │
│  ● Include secrets from: ~/.keystone/secrets/  [Browse...]               │
│                                                                          │
│  Write Destination                                                       │
│  ○ /dev/sdb  USB3 Flash Drive  (32 GB)                                   │
│  ● ~/Downloads/keystone-ocean.iso  (save to file)                        │
│                                                                          │
│  [Enter] Build ISO    [Esc] Back                                         │
└──────────────────────────────────────────────────────────────────────────┘
```

### Deploy Screen

```
┌─ Deploy to ISO Instance ─────────────────────────────────────────────────┐
│                                                                          │
│  Discovered Instances (mDNS)                                             │
│ ┌──────────────────────────────────────────────────────────────────────┐ │
│ │ > keystone-installer.local   192.168.1.42   mDNS                    │ │
│ │   [+ Enter IP manually...]                                           │ │
│ └──────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  Configuration:  ocean                                                   │
│  SSH Key:        ~/.ssh/id_ed25519.pub  [Change]                         │
│                                                                          │
│  [Enter] Deploy   [r] Refresh   [Esc] Back                               │
└──────────────────────────────────────────────────────────────────────────┘
```

## Cross-References

- Spec 001 (Config Generation): `generate_iso_flake_nix` produces the ISO flake.
- Spec 004 (TUI App Framework): `AppScreen::Iso` and `AppScreen::Deploy`
  routing live in the current component architecture.
