# Spec: Nix Flake Parsing and Modification

## Stories Covered

- US-005: Display all keystone hosts
- US-009: Create new keystone host configurations

## Affected Modules

- `packages/ks/src/nix.rs` — flake.nix AST parser (read-only today; needs write support)
- `packages/ks/src/components/hosts.rs` — hosts dashboard
- `packages/ks/src/components/template/mod.rs` — config creation form
- `packages/ks/src/system.rs` — `HostStatus` struct
- `modules/hosts.nix` — `keystone.hosts` NixOS option (already implemented)

## Data Models

### `HostInfo` (extended — `src/nix.rs`)

Current fields:
| Field | Type | Notes |
|-------|------|-------|
| name | `String` | Attribute key in `nixosConfigurations` |
| system | `Option<String>` | Architecture, e.g. `"x86_64-linux"` |
| keystone_modules | `Vec<String>` | Imported keystone modules |
| config_files | `Vec<String>` | Local config file paths |

Fields to add (from `keystone.hosts` evaluation):
| Field | Type | Notes |
|-------|------|-------|
| hostname | `Option<String>` | From `keystone.hosts.<name>.hostname` |
| ssh_target | `Option<String>` | Tailscale hostname or IP for deploys |
| fallback_ip | `Option<String>` | LAN IP fallback |
| build_on_remote | `bool` | Whether to use `--build-host` for deploys |
| role | `Option<String>` | `"client"` \| `"server"` \| `"agent"` |
| host_public_key | `Option<String>` | SSH host public key |

### `HostsEvalResult` (new — `src/nix.rs`)

JSON output of `nix eval --json .#nixosConfigurations` for `keystone.hosts`:

```json
{
  "ocean": {
    "hostname": "ocean",
    "sshTarget": "ocean.mercury",
    "fallbackIP": "192.168.1.10",
    "buildOnRemote": true,
    "role": "server",
    "hostPublicKey": "ssh-ed25519 AAAAC3..."
  }
}
```

## Behavioral Requirements

### Host Display (US-005)

1. The hosts screen MUST display hostname, sshTarget, fallbackIP, and buildOnRemote for each
   host defined in `keystone.hosts`.
2. The TUI MUST read `keystone.hosts` by running:
   `nix eval --json .#nixosConfigurations.<hostname>.config.keystone.hosts`
   or by parsing `nix eval --json` output from the flake's hosts attribute.
3. The hosts list MUST be navigable via arrow keys; pressing Enter on a host MUST open the
   host detail screen.
4. The host detail screen MUST display a summary of the selected host's configuration
   including all `keystone.hosts` fields.
5. The TUI MUST handle the case where `keystone.hosts` is empty (show an empty list with a
   hint to add hosts).
6. The TUI MUST handle flakes that do not import `keystone.nixosModules.hosts` gracefully
   (fall back to displaying names from `nixosConfigurations` only, without metadata).
7. The `HostsScreen` MUST NOT block the event loop during `nix eval` — evaluation MUST run
   on a background tokio task and results MUST be delivered via channel.

### New Host Creation (US-009)

8. The TUI MUST support two distinct host creation modes:
   - **New repo mode**: Creates a fresh directory with `flake.nix`, `configuration.nix`,
     `hardware.nix` (existing `CreateConfigScreen` flow).
   - **Add-to-existing mode**: Adds a new host to an already-open nixos-config flake.
9. In add-to-existing mode, the TUI MUST modify `flake.nix` to add a new entry under
   `nixosConfigurations.<hostname>`.
10. In add-to-existing mode, the TUI MUST create a `hosts/<hostname>/` directory containing
    `configuration.nix` and `hardware.nix`.
11. In add-to-existing mode, the TUI MUST add the new host to `keystone.hosts` in the
    existing `configuration.nix` (or a shared `hosts.nix` if present).
12. `flake.nix` modification MUST use `rnix` AST manipulation — NOT string replacement.
13. Before writing to `flake.nix`, the TUI MUST validate the modified AST parses without
    errors via `rnix`.
14. The TUI MUST create a git commit for the new host files before returning to the hosts
    screen (leveraging the git operations in Spec 004).
15. If `rnix` AST modification fails (unparseable flake), the TUI MUST display an error and
    MUST NOT write partial changes to disk.

## `rnix` Modification Contract

The `nix.rs` module MUST expose a `add_nixos_configuration` function:

```rust
/// Add a new NixOS configuration entry to an existing flake.nix.
/// Returns the modified flake.nix content as a String.
pub fn add_nixos_configuration(
    flake_content: &str,
    hostname: &str,
    config_path: &str,  // e.g., "./hosts/my-host/configuration.nix"
) -> Result<String>
```

The function MUST:

- Parse `flake_content` with `rnix`
- Locate the `nixosConfigurations` attrset
- Insert a new entry: `"<hostname>" = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ <config_path> ]; };`
- Return the serialized (formatted) modified content
- Return `Err` if the flake cannot be parsed or `nixosConfigurations` cannot be located

## Edge Cases

- **Quoted hostnames**: Hostnames with hyphens (e.g., `my-server`) MUST be quoted as
  `"my-server"` in the Nix attrset. The `add_nixos_configuration` function MUST handle this.
- **Duplicate hostname**: If `nixosConfigurations` already contains the target hostname, the
  TUI MUST show an error ("Host already exists") and MUST NOT overwrite the existing entry.
- **Nix eval timeout**: `nix eval` for `keystone.hosts` MUST time out after 30 seconds and
  fall back to displaying `nixosConfigurations` names only (without metadata).
- **Uncommitted changes**: When adding a host, if `flake.nix` has unstaged changes, the TUI
  SHOULD warn the user before proceeding.
- **Missing `hosts/` directory**: If `hosts/<hostname>/` already exists (prior partial run),
  the TUI MUST NOT overwrite existing files — it MUST show an error.

## UI Mockups

### Hosts Screen

```
┌─ ks ─── my-infra ─────────────────────────────────────────────┐
│                                                                          │
│  Hosts                                         System (local)            │
│ ┌──────────────────────────────────┐  ┌───────────────────────────────┐  │
│ │ > ocean         server   online  │  │ CPU  ████████░░░░  42%        │  │
│ │   mercury       client  offline  │  │ MEM  █████░░░░░░  51%        │  │
│ │   titan         agent    online  │  │ DISK ██░░░░░░░░░  21%        │  │
│ │                                  │  │ TEMP 61°C                     │  │
│ │                                  │  └───────────────────────────────┘  │
│ │                                  │                                      │
│ │  [n] New Host  [Enter] Details   │  Tailscale: 2/3 online              │
│ └──────────────────────────────────┘                                      │
│                                                                          │
│  [q] Quit  [b] Build  [i] ISO  [?] Help                                  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Host Detail Screen

```
┌─ Host Detail: ocean ─────────────────────────────────────────────────────┐
│                                                                          │
│  Identity                          Connection                            │
│  Hostname:   ocean                 SSH Target:    ocean.mercury           │
│  Role:       server                Fallback IP:   192.168.1.10           │
│  Build mode: remote                                                      │
│                                                                          │
│  Modules: operating-system, hosts, secrets                               │
│                                                                          │
│  [b] Build  [d] Deploy  [Esc] Back                                       │
└──────────────────────────────────────────────────────────────────────────┘
```

## Cross-References

- Spec 001 (Config Generation): `GenerateConfig` is used to generate files for the new host.
- Spec 003 (ISO Pipeline): Deployment from host detail screen (US-008) references this spec.
- Spec 004 (TUI App Framework): Screen routing and git commit integration.
