# Scope Analysis: Projctl Terminal Session Management

## Source

- **Platform**: github
- **Repository**: ncrmro/keystone
- **Milestone Issue**: #102 — projctl Terminal Session Management: User Stories for Review
- **Milestone**: Projctl Terminal Session Management
- **Analysis Date**: 2026-03-18

## Story-to-System Map

### US-001: Create named terminal sessions per project

- **Type**: feat
- **Affected files/modules**:
  - `modules/terminal/projects.nix` — **new** home-manager module implementing `keystone.projects` options (REQ-010)
  - `modules/terminal/default.nix` — add import for `projects.nix`
  - `packages/pz/default.nix` — **new** shell script implementing the `pz` CLI command
  - `packages/pz/pz.sh` — **new** wrapper around Zellij session creation with project-scoped naming (`{prefix}-{slug}`)
  - `flake.nix` — add `pz` to overlay packages
  - `modules/notes/default.nix` — referenced by `keystone.projects` for `keystone.notes.path` discovery
- **Complexity**: medium
- **Notes**: REQ-010.1–010.8 already specify this behavior. Projects are directories at `{notes_path}/projects/{slug}/` containing `README.md`. Sessions are named `{prefix}-{slug}` using Zellij. The `pz` command creates or attaches to the Zellij session.

### US-002: Resume existing terminal sessions

- **Type**: feat
- **Affected files/modules**:
  - `packages/pz/pz.sh` — same script as US-001; Zellij natively persists sessions across disconnections
  - `modules/terminal/projects.nix` — session prefix configuration (`keystone.projects.sessionPrefix`)
- **Complexity**: small
- **Notes**: Zellij handles session persistence natively. Re-running `pz {slug}` attaches to the existing session (REQ-010.8). Error handling for non-existent sessions needs explicit implementation.

### US-003: List terminal sessions by project

- **Type**: feat
- **Affected files/modules**:
  - `packages/pz/pz.sh` — add `pz list [project]` subcommand that filters `zellij list-sessions` output by prefix
  - `modules/terminal/projects.nix` — expose session prefix for list filtering
- **Complexity**: small
- **Notes**: `zellij list-sessions` provides raw session data. Filtering by `{prefix}-` prefix and formatting with slug, status, and creation time is the main work.

### US-004: Launch sub-agent sessions in worktrees

- **Type**: feat
- **Affected files/modules**:
  - `packages/pclaude/default.nix` — **new** Nix package definition
  - `packages/pclaude/pclaude.sh` — **new** script launching Claude Code with project context in a worktree
  - `modules/terminal/projects.nix` — `pclaude` configuration options (REQ-010.13–010.15), environment variables (REQ-010.9), Claude config directory setup (REQ-010.10)
  - `modules/terminal/ai.nix` — may need coordination with existing Claude Code configuration
  - `bin/worktree` — existing worktree management; `pclaude` will invoke this or replicate its patterns
  - `packages/podman-agent/podman-agent.sh` — `pclaude` may delegate to this for sandboxed execution
  - `flake.nix` — add `pclaude` to overlay packages
- **Complexity**: large
- **Notes**: REQ-010.9 defines required environment variables (`PROJECT_NAME`, `PROJECT_PATH`, `CLAUDE_CONFIG_DIR`, `AGENTS_MD`, etc.). REQ-010.10 requires project-scoped Claude config at `{notes_path}/.claude-projects/{slug}/`. REQ-010.13–010.15 define the `pclaude` command with `--resume` flag and system prompt rendering via `envsubst`. Agent archetype/role configuration needs design.

### US-005: Manage multiple sub-agents in Podman containers

- **Type**: feat
- **Affected files/modules**:
  - `packages/podman-agent/podman-agent.sh` — extend with dynamic AGENT.md assembly from archetypes
  - `modules/os/containers.nix` — may need additional Podman configuration for multi-container orchestration
  - `modules/os/agents/` — agent archetype definitions and AGENT.md generation patterns already exist here (FR-009 in SPEC-007)
  - `modules/os/agents/scripts/agentctl.sh` — container lifecycle management (start/stop/remove) may be added here
- **Complexity**: large
- **Notes**: This is the lowest priority story. The existing `podman-agent` script already supports containerized agent execution with Nix store persistence. The delta is: (1) dynamic AGENT.md composition from archetype + role definitions, (2) multi-container lifecycle management via CLI, (3) concurrent container support per project. This story may be better split or deferred.

## System Boundaries

### Project Discovery Layer

- **Stories involved**: US-001, US-003, US-004
- **Shared concern**: All need to discover projects from `{notes_path}/projects/{slug}/README.md` (REQ-010.1, REQ-010.4)
- **Key files**: `modules/terminal/projects.nix`, `modules/notes/default.nix`
- **Coordination notes**: The discovery logic (scan `projects/*/README.md`, parse YAML frontmatter for `repos:`) must be implemented once in the home-manager module and exposed to all CLI tools via environment variables or a shared library. `keystone.notes.enable` must be true when `keystone.projects.enable` is true (REQ-010.5).

### Zellij Session Layer

- **Stories involved**: US-001, US-002, US-003
- **Shared concern**: All interact with Zellij sessions using the `{prefix}-{slug}` naming convention
- **Key files**: `packages/pz/pz.sh`, `modules/terminal/shell.nix` (Zellij config), `packages/zesh/default.nix` (upstream session manager)
- **Coordination notes**: The `pz` command wraps Zellij session operations. It should not conflict with the existing `zs` (zesh) alias. Session prefix (`obs` default per REQ-010.7) must be configurable. Zellij is already configured in `shell.nix` with custom keybindings.

### Home Manager Module (`keystone.projects`)

- **Stories involved**: US-001, US-002, US-003, US-004
- **Shared concern**: All require the `keystone.projects` home-manager module for configuration, environment variables, and shell integration
- **Key files**: `modules/terminal/projects.nix`, `modules/terminal/default.nix`
- **Coordination notes**: This is the central integration point. It must: (1) depend on `keystone.notes`, (2) provide `pz` and `pclaude` as `home.packages`, (3) export environment variables per REQ-010.9, (4) set up Claude config directories per REQ-010.10, (5) provide shell completions per REQ-010.17. The module follows existing patterns in `modules/terminal/` (see `shell.nix`, `ai.nix`).

### Agent + Worktree Integration

- **Stories involved**: US-004, US-005
- **Shared concern**: Both involve launching agent processes in isolated working environments (worktrees or containers)
- **Key files**: `bin/worktree`, `packages/podman-agent/podman-agent.sh`, `modules/os/agents/`, `packages/pclaude/pclaude.sh`
- **Coordination notes**: US-004 (`pclaude`) creates worktrees and launches Claude Code within them. US-005 extends this to Podman containers with dynamic AGENT.md. The `podman-agent` script already handles worktree volume mounts (`.git` file detection and parent mount). These stories share the concept of "isolated workspace + agent launch" but differ in isolation mechanism (worktree vs container). US-004 should be implemented first as it's higher priority and simpler.

### Nix Overlay / Package Registry

- **Stories involved**: US-001, US-004
- **Shared concern**: Both introduce new packages (`pz`, `pclaude`) that must be added to the keystone overlay
- **Key files**: `flake.nix` (overlay definition), `packages/pz/`, `packages/pclaude/`
- **Coordination notes**: New packages follow the existing pattern in `packages/` (see `packages/zesh/`, `packages/ks/`). Shell scripts use `pkgs.writeShellScriptBin` or `pkgs.writeShellApplication`. Packages must be added to the overlay in `flake.nix` and included in `home.packages` by the `projects.nix` module.

## Implied Prerequisites

| #   | Prerequisite                               | Required By            | Type  | Notes                                                                                                                                                                         |
| --- | ------------------------------------------ | ---------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `keystone.notes` module must be functional | US-001, US-003, US-004 | chore | REQ-010.5 requires `keystone.notes.enable = true`. The module exists at `modules/notes/default.nix` and provides `keystone.notes.path`. Verify it works as expected.          |
| 2   | Project directory structure convention     | US-001, US-003, US-004 | chore | At least one project directory at `{notes_path}/projects/{slug}/README.md` must exist for testing. The convention (REQ-010.1–010.3) must be documented.                       |
| 3   | Shell completion infrastructure            | US-001                 | chore | REQ-010.17 requires Bash and Zsh completions for `pz`. This is a separate concern from the core CLI and should be its own commit.                                             |
| 4   | AGENTS.md aggregation for repos            | US-004                 | chore | REQ-010.12 requires aggregating `AGENTS.md` from declared repos. This needs a script or build step to concatenate files from repo paths listed in README.md YAML frontmatter. |
| 5   | System prompt template for pclaude         | US-004                 | chore | REQ-010.15 requires a project-specific system prompt rendered via `envsubst`. The template must be created and stored in a discoverable location.                             |

## Ambiguities and Clarification Needed

| #   | Story  | Question                                                                                                                                                                                                                          | Impact                                                                                                                                                              |
| --- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | US-004 | What agent "archetype/role" definitions exist and where are they stored? The story references "ncrmro/agent archetype/role" but no archetype registry exists in the codebase.                                                     | Determines whether archetypes are simple string labels, Nix option sets, or full configuration files. Blocks dynamic AGENT.md generation in US-005.                 |
| 2   | US-004 | Should `pclaude` run Claude Code directly or via `podman-agent` (sandboxed)? The acceptance criteria says "reference the pyclaude/pclaude implementation for design inspiration" — is there an external reference implementation? | Determines whether US-004 depends on container infrastructure or is a lightweight wrapper.                                                                          |
| 3   | US-005 | What is the relationship between OS-level agents (`keystone.os.agents` in SPEC-007) and project-level sub-agents? OS agents are NixOS users with full provisioning; project sub-agents seem to be ephemeral containers.           | Affects whether US-005 extends `agentctl` or creates a separate tool. Also determines if AGENT.md composition reuses SPEC-007's FR-009 scaffold or needs new logic. |
| 4   | US-005 | Should container lifecycle be managed per-project (tied to `pz` sessions) or globally?                                                                                                                                            | Determines CLI design: `pz agent start <slug>` vs standalone `projctl agent start`.                                                                                 |
| 5   | US-001 | The story mentions "projctl" as the CLI name, but REQ-010 specifies `pz` (project Zellij). Which name should be used?                                                                                                             | Naming affects package names, shell aliases, completion scripts, and documentation.                                                                                 |

## Stories Recommended for Splitting

| Story  | Reason                                                                                                                         | Suggested Split                                                                                                                                                                                                                                                                                                            |
| ------ | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| US-004 | Covers both worktree creation + agent launch + environment setup + system prompt rendering — too many concerns for a single PR | **US-004a**: `pclaude` basic command — launch Claude Code with project environment variables and config directory (REQ-010.9, 010.10, 010.13). **US-004b**: Worktree integration — `pclaude` creates/uses worktrees for isolated agent work. **US-004c**: System prompt template and `--resume` flag (REQ-010.14, 010.15). |
| US-005 | Combines dynamic AGENT.md generation, container lifecycle, and multi-container orchestration — each is independently valuable  | **US-005a**: Dynamic AGENT.md composition from archetype definitions. **US-005b**: Container lifecycle management CLI (`start`, `stop`, `remove`). **US-005c**: Multi-container concurrent execution per project.                                                                                                          |
