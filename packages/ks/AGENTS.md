# ks — Agent Conventions

## Architecture

This crate is a **TUI + CLI + JSON** tool following the **ratatui Component
Architecture**. The same binary serves three modes:

- **TUI mode** (default): Full-screen ratatui terminal interface
- **CLI mode** (`ks <subcommand>`): Line-based interactive prompts
- **JSON mode** (`ks <subcommand> --json`): Structured stdin/stdout for
  scripting and desktop menu integration (Walker, Elephant)

### Component Architecture

Each feature is a **component** implementing the `Component` trait:

```rust
pub trait Component {
    fn init(&mut self) -> Result<()>;
    fn handle_events(&mut self, event: &Event) -> Result<Option<Action>>;
    fn update(&mut self, action: &Action) -> Result<Option<Action>>;
    fn draw(&mut self, frame: &mut Frame, area: Rect) -> Result<()>;
}
```

Components own their state and colocate event handling, state updates, and
rendering. Cross-component communication flows through a single global
`Action` enum in `action.rs`.

### File Layout

```
src/
├── main.rs              # Entry point: CLI dispatch or TUI event loop
├── app.rs               # App struct, component registry, transitions
├── action.rs            # Single global Action enum
├── component.rs         # Component trait definition
├── tui.rs               # Terminal setup/teardown/panic hook
├── cli.rs               # Clap subcommand definitions
│
├── components/          # Feature components
│   ├── welcome.rs       # Simple component (single file)
│   ├── template/        # Complex component (directory)
│   │   ├── mod.rs       # Component impl (state + draw + events)
│   │   ├── types.rs     # Shared serde types (JSON/CLI/TUI)
│   │   └── run.rs       # Execution logic (shared by all modes)
│   ├── hosts/           # Nested sub-components
│   │   ├── mod.rs
│   │   ├── detail.rs
│   │   ├── build.rs
│   │   └── ...
│   └── ...
│
├── widgets/             # Stateless rendering primitives
│   ├── text_input.rs
│   └── select_menu.rs
│
├── nix.rs               # Flake parsing, config version detection
├── template.rs          # Nix file generation (pure functions)
└── ...                  # github.rs, ssh_keys.rs, disk.rs, system.rs, etc.
```

**Rules:**
- Simple components are a single `.rs` file.
- Complex components with CLI/JSON shared logic get a directory with `types.rs`
  (serde params/result) and `run.rs` (execution logic).
- Internal component actions (scroll, select, toggle) stay inside
  `handle_events()` — only navigation and cross-component effects go in
  `Action`.
- `widgets/` holds stateless rendering primitives reused across components.

### Adding a New Component

1. Create `src/components/<name>.rs` (simple) or `src/components/<name>/mod.rs`
   (complex).
2. Implement `Component` trait.
3. Add the component's navigation variant to `Screen` in `action.rs`.
4. Register the component in `components/mod.rs`.
5. If the component has a CLI subcommand, add it to `cli.rs` and wire
   `types.rs` + `run.rs` in `main.rs`.

## CLI Subcommands

### `ks notification` — Unified notification fetch with source-level read tracking

Replaces shell-script fetchers (`fetch-email-source`, `fetch-github-sources`,
`fetch-forgejo-sources`) with a single Rust subcommand. Fetches only unseen/unread
items and supports marking them as read at the source after successful processing.

| Command | What |
|---------|------|
| `ks notification` | Human-readable list of unread notifications |
| `ks notification fetch` | Fetch unseen items, output JSON |
| `ks notification fetch --manifest` | Also write manifest for later ack |
| `ks notification ack <manifest>` | Mark items read at source |
| `ks notification sources` | Show configured sources and status |

Sources: email (himalaya), GitHub (gh API), Forgejo (curl + token).
GitHub/Forgejo return metadata only (1 API call each); email enriches with body.

### `ks task` — Unified task management for humans and agents

CRUD on `TASKS.yaml` with AI-powered ingest and prioritization.
Prioritization proposals include per-task rationale as JSON.

| Command | What |
|---------|------|
| `ks task` | List tasks grouped by status |
| `ks task add <desc>` | Create pending task (auto-slugify name) |
| `ks task start <name>` | Mark in-progress |
| `ks task done <name>` | Mark completed |
| `ks task block <name>` | Mark blocked with optional reason |
| `ks task ingest --file <json>` | Output AI prompt for notification→task conversion |
| `ks task ingest --apply` | Apply AI ingest result from stdin |
| `ks task prioritize` | Output AI prompt for task ranking |
| `ks task proposal` | Show current prioritization proposal |
| `ks task proposal --accept` | Apply proposed ordering |
| `ks task prune [--all]` | Remove old completed tasks |

### `ks project` — Project management with detection and provider overrides

Projects map repos to named entities with priority and per-project provider config.
Detection resolves notifications to projects deterministically or heuristically.

| Command | What |
|---------|------|
| `ks project` | List all projects |
| `ks project show <slug>` | Full project details |
| `ks project add <slug>` | Create project (`--name`, `--repo`, `--priority`) |
| `ks project remove <slug>` | Remove project |
| `ks project detect --repo <url>` | Exact repo→project lookup |
| `ks project detect --subject <text>` | Heuristic name/slug match |

Detection output: `{"slug": "keystone", "confidence": "exact|heuristic|none", "method": "..."}`

## Nix source handling

When Rust code reads or writes `.nix` source, it should use the installed
`rnix` parser (`rnix = "0.11"` in `Cargo.toml`) and operate on the AST.

**Rules:**
- Rust code must not parse Nix source with string matching, regexes, line
  filtering, or ad hoc text extraction.
- Rust code must not rewrite Nix source with string replacement, line-based
  filtering, or template reconstruction.
- New Nix source handling in `ks` should use `rnix` for both read paths and
  write paths.
- Existing non-AST Nix source handling is migration debt and must not be copied
  into new code paths.

Migration debt is tracked in #375. The `src/components/install.rs` functions
listed there were migrated to rnix in PR #378.

## Clippy Configuration

The crate enables strict clippy lint groups:

- `clippy::correctness`, `clippy::suspicious`, `clippy::complexity`,
  `clippy::perf`, `clippy::style`
- `clippy::cognitive_complexity` with threshold **15** (via `clippy.toml`)

## Pre-Push Checklist

Before pushing any changes, run **all** of the following locally. These mirror
the `Validate / ks-cli` CI job — if any fail locally they will fail in CI.

```bash
# 1. Formatting (must pass with zero diff)
cargo fmt --check

# 2. Clippy with ALL targets — warnings are errors
cargo clippy --all-targets --all-features -- -D warnings

# 3. Tests
cargo test
```

**Key detail**: Always use `--all-targets` with clippy. Plain `cargo clippy`
silently skips test files under `tests/`.
