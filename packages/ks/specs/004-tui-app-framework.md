# Spec: TUI App Framework

## Stories Covered

- US-004: Build interactive TUI with cross-platform support
- US-006: Implement git and GitHub publishing
- US-010: Document TUI installation and usage
- US-011: Define phased delivery plan

Note: US-005 and US-008 overlap with this boundary but are detailed in Spec 002 and Spec 003.

## Affected Modules

- `packages/ks/src/main.rs` — entry point, mode detection, CLI dispatch
- `packages/ks/src/app.rs` — `AppScreen` enum, component registry, screen transitions
- `packages/ks/src/action.rs` — app-level navigation and cross-component actions
- `packages/ks/src/components/template/mod.rs` — config creation form
- `packages/ks/src/components/template/types.rs` — shared CLI/JSON/TUI request and result types
- `packages/ks/src/components/template/run.rs` — shared template execution logic
- `packages/ks/src/github.rs` — SSH key fetching; needs repo creation
- `packages/ks/src/repo.rs` — git clone/discover; needs init + commit + push
- `packages/ks/Cargo.toml` — `clap` for CLI, `git2` for git ops

## Existing Framework State

The TUI is implemented in **Rust** using `ratatui` (v0.29) + `crossterm` (v0.28). This is
the implementation language going forward. The Bubbletea (Go) mention in issue #132 US-004
is stale — the architecture decision to use Rust was made when the existing `keystone-ha/tui`
was chosen as the reference implementation. No Go code exists in this package.

## Cross-Platform Support

The TUI already compiles and runs on both Linux and macOS. The `crossterm` backend handles
platform differences. No additional cross-platform work is needed for the core TUI loop.

macOS-specific considerations:

- `/dev/disk*` paths differ; disk detection uses `sysinfo` which is cross-platform.
- `tailscale status --json` may not be available; the TUI already handles missing tailscale.
- SSH key paths and `~/.ssh/` layout are consistent across platforms.

## Data Models

### `AppScreen` (current — `src/app.rs`)

Current variants:

- `Welcome`, `CreateConfig`, `Hosts`, `HostDetail`, `Build`, `Iso`, `Deploy`, `Install`,
  `Installer`, `FirstBoot`, `Secrets`, `Security`, `Services`

Reserved navigation targets already present in `src/action.rs` but not yet fully wired into
`AppScreen`:

- `Update`
- `Doctor`

### `TemplateParams` (existing — `src/components/template/types.rs`)

For subcommand-scoped JSON mode. The canonical current JSON entrypoint is
`ks template --json`, which reads `TemplateParams` from stdin.
Other user-facing commands SHOULD expose their own `--json` mode using
command-specific request/response types rather than a single global
top-level switch.

```json
{
  "hostname": "my-server",
  "kind": "server",
  "username": "admin",
  "password": "changeme",
  "disk_device": "/dev/disk/by-id/nvme-abc123",
  "github_username": "ncrmro",
  "owner_name": "Admin User",
  "owner_email": "admin@example.com",
  "time_zone": "America/Chicago",
  "state_version": "25.05",
  "output": "/tmp/my-config"
}
```

## Behavioral Requirements

### TUI Interaction (US-004)

1. The TUI MUST use `ratatui` with `crossterm` as the terminal backend (not Bubbletea/Go).
2. The TUI MUST restore terminal state on exit via the existing panic hook.
3. The TUI MUST handle terminal resize events without crashing.
4. The TUI SHOULD support mouse events for clicking list items.
5. The TUI MUST auto-detect SSH public keys from `~/.ssh/*.pub` during the user configuration
   form step (create-config flow) and offer them for selection.
6. The TUI MUST detect connected hardware security keys:
   - YubiKey: detected via `lsusb` output or `/dev/hidraw*` on Linux
   - SoloKey: same detection path
   - On macOS: detected via `system_profiler SPUSBDataType`
   - When detected, offer to configure `keystone.os.hardwareKey` (FIDO2 SSH key enrollment
     via `ssh-keygen -t ed25519-sk`)
7. Input validation MUST reject:
   - Blank hostname
   - Hostname longer than 63 characters or containing invalid characters (`[^a-z0-9-]`)
   - Zero storage devices
   - Zero users
   - Blank username
8. The TUI MUST display inline validation errors next to the offending field, not on a
   separate error screen.

### Subcommand JSON Mode (US-004)

9. Most user-facing CLI subcommands SHOULD expose a `--json` flag for structured stdin/stdout.
   `template --json` is the canonical current entrypoint, and future commands SHOULD follow
   the same per-subcommand pattern.
10. Structured JSON mode MUST be bound to the subcommand being invoked
    (`ks <subcommand> --json`), not a new top-level command surface.
11. In `template --json` mode, the command MUST validate `TemplateParams` against the same
    rules as the interactive form (Behavioral Requirements §7 above).
12. In `template --json` mode, the command MUST print machine-readable success or error output
    to stdout and exit with code 0 (success) or 1 (failure). No TUI rendering MUST occur.
13. In `template --json` mode, the command MUST write `flake.nix`, `configuration.nix`, and
    `hardware.nix` to the requested output directory, creating it if it doesn't exist.

### Git Operations (US-006)

14. After generating a new config (both interactive and JSON modes), the TUI MUST offer to:
    - Initialize a git repository in the output directory
    - Create an initial commit with message `"chore: initial keystone config for <hostname>"`
15. The TUI MUST NOT auto-commit without user confirmation ("Initialize git repo? [y/N]").
16. The TUI MUST warn if any generated file appears to contain a plaintext password (heuristic:
    `initialPassword` value is present in the file and is not a bcrypt/yescrypt hash).
17. The TUI MUST offer to create a private GitHub repository via `gh repo create`:
    - Requires `gh` to be available in PATH and authenticated
    - Uses SSH URL format for the remote: `git@github.com:<user>/<repo>.git`
    - If `gh` is unavailable, display instructions for manual setup
18. The TUI MUST NOT commit any of the following (MUST warn and exclude):
    - Files matching `*.pem`, `*.key`, `*.age`, `id_rsa`, `id_ecdsa` (private keys)
    - Files matching `.env`, `*.secret`
    - Age-encrypted secrets (`.age` extension) ARE allowed in commits
19. The `GitScreen` MUST show a diff preview (using `git2::Diff`) before the user confirms
    a commit.
20. The TUI MUST NOT push to a remote without explicit user confirmation ("Push to origin/main?").

### GitHub Repo Creation (US-006)

21. The TUI MUST shell out to `gh repo create <name> --private --source=. --remote=origin`
    rather than using the GitHub API directly.
22. If `gh` is not authenticated (`gh auth status` fails), the TUI MUST display a message:
    "Run `gh auth login` to enable GitHub integration."
23. The repo name MUST default to the hostname value from the generated config.

## Edge Cases

- **SSH key detection on macOS**: `~/.ssh/` may contain `.pub` files with whitespace in
  names (unlikely but MUST not crash). The TUI MUST skip non-standard filenames gracefully.
- **Hardware key detection**: If USB probing fails (permission denied on `/dev/hidraw*`), the
  TUI MUST skip detection silently — do not display an error for missing hardware keys.
- **JSON mode invalid path**: If the requested output directory already contains a `flake.nix`,
  the command MUST
  error ("Output directory already contains a flake.nix; use --force to overwrite") and
  exit with code 1.
- **git2 init on existing repo**: If `output_dir` already contains `.git/`, the TUI MUST
  skip `git init` and proceed to the commit step.
- **`gh` invocation failure**: If `gh repo create` fails (e.g., name conflict), the TUI MUST
  display the error and allow the user to retry with a different name or skip.

## Phased Delivery Plan (US-011)

The implementation MUST follow these phases:

### Phase 1 — Config Contract (prerequisite, no TUI code)

- **Deliverables**: Spec 001 implemented — `disko` in generated flake.nix, data model
  complete, Nix check at `checks.x86_64-linux.template-evaluation` with 4 variants.
- **Exit criteria**: `nix flake check` passes; all 4 test configs evaluate.

### Phase 2 — Interactive TUI + Publishing

- **Deliverables**: SSH key auto-detection (US-004), hardware key detection (US-004),
  per-subcommand JSON mode (US-004), host display with `keystone.hosts` metadata (US-005), new host
  creation into existing flake (US-009), git init + commit (US-006), GitHub repo creation (US-006).
- **Entry criteria**: Phase 1 complete.
- **Exit criteria**: Interactive config creation + publishing flow works end-to-end on macOS
  and Linux.

### Phase 3 — ISO Build + Deployment

- **Deliverables**: Agenix secrets baking into ISO (US-007), mDNS ISO discovery (US-008),
  nixos-anywhere deployment (US-008).
- **Entry criteria**: Phase 2 complete; user has a functioning nixos-config repo.
- **Exit criteria**: Full flow from `ks` launch to deployed NixOS system works
  without manual Nix commands.

### Documentation

- **Deliverables**: README covers install, quick-start, all screens, per-subcommand JSON mode,
  and ISO workflow.
- **Timing**: Updated alongside Phase 2 and Phase 3 feature work; finalized before milestone close.

## PLAN.md Alignment

The existing `packages/ks/PLAN.md` defines 7 implementation phases. These MUST be
reconciled with the 3-phase delivery plan above before Phase 2 work begins. The recommended
approach: replace the 7-phase plan in `PLAN.md` with the 3-phase structure from this spec,
keeping the module structure section unchanged.

## Cross-References

- Spec 001 (Config Generation): `template --json` populates `GenerateConfig` from
  `TemplateParams`.
- Spec 002 (Nix Flake): New host creation and hosts screen are driven from the app framework.
- Spec 003 (ISO Pipeline): `AppScreen::Iso` and `AppScreen::Deploy` are routed through this
  framework.
