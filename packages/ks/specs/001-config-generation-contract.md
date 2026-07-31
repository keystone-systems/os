# Spec: Config Generation Contract

## Stories Covered

- US-001: Define config generation output contract
- US-002: Define template data model
- US-003: Implement build validation test suite

Derived from: REQ-001 (Config Generation), REQ-002 (Template Data Model), REQ-003 (Build Validation)

## Affected Modules

- `packages/ks/src/template.rs` — `GenerateConfig`, all generator functions
- `packages/ks/tests/nix_build.rs` — `#[ignore]`d eval/build tests
- `packages/ks/flake.nix` — must expose `checks.x86_64-linux.template-evaluation`
- `packages/ks/checks/template-evaluation.nix` — new Nix derivation (to create)

## Data Model

### `GenerateConfig` (Rust struct — `src/template.rs`)

| Field           | Type              | Required | Notes                                                              |
| --------------- | ----------------- | -------- | ------------------------------------------------------------------ |
| hostname        | `String`          | yes      | Maps to `networking.hostName`                                      |
| host_id         | `String`          | yes      | 8-char hex; generated randomly by TUI; maps to `networking.hostId` |
| state_version   | `String`          | yes      | Defaults to `"25.05"`; maps to `system.stateVersion`               |
| time_zone       | `String`          | yes      | Defaults to `"UTC"`; maps to `time.timeZone`                       |
| machine_type    | `MachineType`     | yes      | Server \| Workstation \| Laptop                                    |
| storage         | `StorageConfig`   | yes      | See below                                                          |
| security        | `SecurityConfig`  | yes      | See below                                                          |
| users           | `Vec<UserConfig>` | yes      | At least one entry required                                        |
| github_username | `Option<String>`  | no       | For fetching SSH keys via GitHub API                               |

### `StorageConfig`

| Field        | Type                        | Required | Notes                                                                      |
| ------------ | --------------------------- | -------- | -------------------------------------------------------------------------- |
| storage_type | `StorageType` (Zfs \| Ext4) | yes      | Maps to `keystone.os.storage.type`                                         |
| devices      | `Vec<String>`               | yes      | ≥1 entry; SHOULD be `/dev/disk/by-id/` paths                               |
| mode         | `StorageMode`               | no       | Single \| Mirror \| Stripe \| Raidz1 \| Raidz2 \| Raidz3; default `Single` |
| swap_size    | `Option<String>`            | no       | E.g. `"16G"`; defaults to `"16G"`                                          |
| hibernate    | `bool`                      | no       | Only valid when `storage_type = Ext4`; default `false`                     |

### `SecurityConfig`

| Field         | Type                 | Required | Notes                                                   |
| ------------- | -------------------- | -------- | ------------------------------------------------------- |
| secure_boot   | `bool`               | no       | Maps to `keystone.os.secureBoot.enable`; default `true` |
| tpm           | `bool`               | no       | Maps to `keystone.os.tpm.enable`; default `true`        |
| remote_unlock | `RemoteUnlockConfig` | no       | See below                                               |

### `RemoteUnlockConfig`

| Field           | Type          | Required | Notes                                     |
| --------------- | ------------- | -------- | ----------------------------------------- |
| enable          | `bool`        | yes      | Maps to `keystone.os.remoteUnlock.enable` |
| authorized_keys | `Vec<String>` | no       | SSH public keys for initrd unlock         |

### `UserConfig`

| Field            | Type             | Required | Notes                                                                                            |
| ---------------- | ---------------- | -------- | ------------------------------------------------------------------------------------------------ |
| username         | `String`         | yes      | Maps to `keystone.os.users.<name>` key                                                           |
| full_name        | `String`         | yes      | Maps to `fullName`                                                                               |
| email            | `Option<String>` | no       | Maps to `email`; defaults to `{username}@localhost`                                              |
| initial_password | `String`         | yes      | Maps to `initialPassword`; SHOULD warn user to change post-install                               |
| authorized_keys  | `Vec<String>`    | no       | SSH public keys                                                                                  |
| extra_groups     | `Vec<String>`    | no       | Default: `["wheel"]` for first user, `["wheel", "networkmanager", "video", "audio"]` for desktop |
| terminal_enable  | `bool`           | no       | Default `true`                                                                                   |
| desktop_enable   | `bool`           | no       | Default based on `MachineType` (false for Server, true for Workstation/Laptop)                   |

## Generated File Contracts

### `flake.nix`

The generated flake.nix MUST:

1. Declare `nixpkgs`, `keystone`, `home-manager`, and `disko` as inputs, with
   `nixpkgs.follows = "nixpkgs"` on all derived inputs.
2. Import `keystone.nixosModules.operating-system` in the modules list.
3. Import `home-manager.nixosModules.home-manager` for any user with `terminal.enable` or `desktop.enable`.
4. Import `keystone.nixosModules.desktop` when any user has `desktop.enable = true`.
5. Expose exactly one `nixosConfigurations.<hostname>` output using the user-provided hostname.
6. NOT contain any `TODO:` markers.

### `configuration.nix`

The generated configuration.nix MUST:

1. Set `networking.hostName`, `networking.hostId`, `system.stateVersion`.
2. Set `time.timeZone`.
3. Set `keystone.os.enable = true`.
4. Set `keystone.os.storage` with type, devices, mode, and swap.size.
5. Set at least one `keystone.os.users.<username>` entry with fullName, email, extraGroups,
   initialPassword, authorizedKeys, terminal.enable, and desktop.enable.
6. NOT contain any `TODO:` markers.
7. Use `__KEYSTONE_DISK__` as the disk placeholder when no device is provided (deferred selection).

### `hardware.nix`

The generated hardware.nix MUST:

1. Be a minimal valid NixOS module: `{ ... }: { }` with an imports list pointing to
   `(modulesPath + "/installer/scan/not-detected.nix")`.
2. NOT configure any hardware — hardware.nix is populated post-installation by
   `nixos-generate-config` or `nixos-anywhere`.

## Behavioral Requirements

### Config Generation

1. The generator MUST produce `flake.nix`, `configuration.nix`, and `hardware.nix` from a
   single `GenerateConfig` input.
2. Generated files MUST pass `nix-instantiate --parse` without errors.
3. Generated files SHOULD pass `nixfmt-rfc-style` formatting (no diff on re-format).
4. The `hostId` field MUST be generated from `/dev/urandom` (8 hex chars); it MUST fall back
   to a time-based seed if `/dev/urandom` is unavailable.
5. String values embedded in Nix files MUST be escaped: `\` → `\\`, `"` → `\"`, `${` → `\${`,
   `\n` → `\\n`.

### Build Validation (Nix Check)

6. A Nix derivation MUST be importable as `checks.x86_64-linux.template-evaluation` from the
   ks `flake.nix`.
7. The check MUST evaluate at least 4 configuration variants:
   - Single-disk ZFS (Server)
   - Multi-disk ZFS mirror (Server, 2 devices)
   - Single-disk ext4 (Laptop)
   - ZFS with desktop module (Workstation)
8. Each variant MUST evaluate successfully via `nixpkgs.lib.nixosSystem` without errors.
9. Each variant MUST force deep evaluation by serializing `users.users`, `users.groups`, and
   `systemd.services` via `builtins.toJSON`.
10. The derivation MUST write `$out/<config-name>.json` for each variant, containing at
    minimum `users`, `groups`, and `services` keys.
11. The check MUST be runnable via `nix build .#checks.x86_64-linux.template-evaluation`.

### Data Model Validation

12. The system MUST reject a `GenerateConfig` with zero storage devices.
13. The system MUST reject a `GenerateConfig` with zero users.
14. The system MUST reject a `hostId` that is not exactly 8 hexadecimal characters.
15. The system MUST reject `storage.mode = Mirror` with fewer than 2 devices.
16. The system MUST reject `storage.hibernate = true` when `storage_type = Zfs`.

## Edge Cases

- **Special characters in hostnames**: Hostnames containing `"`, `\`, or `${` MUST be escaped
  in all generated files. The `escape_nix_string` function already handles this.
- **Empty authorized_keys**: An empty `authorized_keys` list MUST produce `authorizedKeys = []`
  (not a missing field).
- **Deferred disk selection**: When `disk_device` is `None`, the placeholder `__KEYSTONE_DISK__`
  MUST appear in generated config. The ISO installer MUST copy the embedded install config into
  a writable staging directory and replace the placeholder there; it MUST NOT mutate
  `/etc/keystone/install-config/` in place.
- **Multiple users**: All users MUST appear in `keystone.os.users`. The first user gets
  `extraGroups = ["wheel"]`; desktop users get networking/video/audio groups.
- **nixfmt unavailability**: If `nixfmt-rfc-style` is not in PATH, formatting validation MUST
  be skipped (not a build failure), but a warning SHOULD be logged.

## Cross-References

- Spec 004 (TUI App Framework): the `GenerateConfig` model is populated by the interactive form
  in `create_config.rs` and by the JSON mode parser.
