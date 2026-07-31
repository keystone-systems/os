# REQ-012: agentctl Project Sessions

Extend agentctl with project context, worktree isolation, sandboxed execution,
and local model support across all AI tools.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Stories Covered

- US-004: Launch sub-agent sessions in worktrees

## Affected Modules

- `modules/os/agents/scripts/agentctl.sh` — main CLI script
- `modules/os/agents/agentctl.nix` — Nix module with replaceVars
- `packages/podman-agent/podman-agent.sh` — sandbox backend

## Requirements

### Generalized Flags

**REQ-012.1** The `--project <slug>` flag MUST work for all AI tool
subcommands (claude, gemini, codex, opencode), not only claude.

**REQ-012.2** The `--role <mode>` flag MUST work for all AI tool
subcommands, composing role-specific context via `.agents/compose.sh`.

**REQ-012.3** When `--project` is set, agentctl MUST create a Zellij
session, set the working directory to the project path, and export
environment variables (PROJECT_NAME, PROJECT_PATH, PROJECT_README,
VAULT_ROOT) for all tools.

> **Breaking changes from current implementation**: The current `agentctl.sh`
> already wires `--project` and Zellij session wrapping for `claude|gemini|codex|opencode`,
> and requires an additional positional `<session-slug>` argument with a specific
> session naming/prefix convention. REQ-012.1/REQ-012.3 standardize this behavior across
> all AI tools, change the session naming/prefix contract (and `<session-slug>` handling),
> and switch project metadata discovery to `README.md` frontmatter (REQ-010) rather than
> `PROJECTS.yaml`. These are intentional breaking changes; migration is out of scope for
> this spec.

### Worktree Support

**REQ-012.4** agentctl MUST support a `--worktree <branch>` flag that
creates a git worktree at `$HOME/repos/{owner}/{repo}/worktrees/{branch}/` if it does not
already exist.

**REQ-012.5** After creating a worktree, agentctl MUST run `direnv allow`
in the worktree directory.

**REQ-012.6** When `--worktree` is set, the working directory for the
AI tool MUST be the worktree path, not the main checkout.

**REQ-012.7** Worktree creation MUST reuse the logic and conventions
from `process.git-repos` (branch naming, external worktree root,
repo-root anchored creation flow).

**REQ-012.7a** When project repo metadata comes from a hub note `repos:` list,
agentctl MUST resolve the selected repo from the normalized `owner/repo`
identity used by Keystone project metadata.

**REQ-012.7b** If a project declares multiple repos, agentctl MUST require an
explicit repo selection before creating or entering a worktree.

### Sandbox by Default

**REQ-012.8** AI tool subcommands (claude, gemini, codex, opencode)
MUST launch inside a Podman container by default.

**REQ-012.9** The sandbox container MUST mount the working directory
(or worktree) as read-write.

**REQ-012.10** The sandbox container MUST mount the parent `.git/`
directory as read-only to support git operations from within the
worktree.

**REQ-012.11** The sandbox container MUST mount project context files
(AGENTS.md, CLAUDE.md, GEMINI.md) read-only at `~/` inside the
container, so AI tools discover them natively from the home directory.

**REQ-012.12** agentctl MUST support a `--nosandbox` flag that disables
Podman containerization and runs the AI tool directly (current behavior).

**REQ-012.13** Non-AI subcommands (shell, tasks, email, vnc, logs, etc.)
MUST NOT be sandboxed.

**REQ-012.14** The sandbox MUST use the existing `podman-agent`
infrastructure (Nix store volume, SSH forwarding, cache volumes).

### Sandbox Port Exposure

**REQ-012.15** The sandbox container MUST expose a default port for
the agent to use when starting development servers. This port MUST be
auto-assigned from a non-conflicting range to avoid collisions with
other sandbox instances or host services.

**REQ-012.16** The default port MUST be communicated to the AI tool
via an environment variable (e.g., `SANDBOX_PORT`) so the system
prompt can instruct the agent to bind servers to it.

**REQ-012.17** The system prompt MUST instruct the agent to use
`$SANDBOX_PORT` when starting servers, unless the project already
exposes a specific port in its configuration.

**REQ-012.18** agentctl MUST support a `--port <host:container>` flag
that can be specified multiple times to expose additional ports from
the sandbox container to the host.

**REQ-012.19** When `--port` is specified, the ports MUST be forwarded
from the host to the container using Podman's `-p` flag.

**REQ-012.20** The `--port` flag MUST be ignored when `--nosandbox`
is set (no container to forward to).

### Local Model Support

**REQ-012.21** agentctl MUST support a `--local [model]` flag that uses
Ollama instead of a cloud API.

**REQ-012.22** When `--local` is set, agentctl MUST run
`ollama run <model>` with the same system prompt and project context
that would be passed to the cloud tool.

**REQ-012.23** The `--local` flag MAY accept an optional model name.
If omitted, a configurable default model SHOULD be used.

**REQ-012.24** The `--local` flag MUST be compatible with `--project`,
`--role`, `--worktree`, and `--nosandbox` flags.

### Interactive defaults and machine-readable state

**REQ-012.28** `agentctl` MUST expose machine-readable agent state for desktop launch surfaces.

**REQ-012.29** Machine-readable agent state MUST include effective preferred host, pause state, and interactive provider or model defaults.

**REQ-012.30** `agentctl` MUST support editing interactive preferred host, provider, model, and fallback model defaults without editing task-loop config.

### System Prompt Composition

**REQ-012.25** System prompt composition (loading AGENTS.md, project
context, role prompt) MUST be computed for all AI tools.

**REQ-012.26** Per-tool prompt injection MUST use each tool's native
mechanism:

- Claude: `--append-system-prompt`
- Gemini: reads GEMINI.md from `~/` (mounted by sandbox)
- Codex: reads AGENTS.md from `~/` (mounted by sandbox)
- OpenCode: reads config from `~/` (mounted by sandbox)
- Ollama (--local): system prompt passed via stdin or `--system`

**REQ-012.27** When running in sandbox mode (default), context files
mounted at `~/` provide the system prompt. The `--append-system-prompt`
mechanism is OPTIONAL for sandboxed tools since they read `~/AGENTS.md`
natively.

## Edge Cases

- **No worktree repo**: If `--worktree` is used but the working directory
  is not inside a git repo, agentctl MUST error with a descriptive message.
- **Sandbox fallback**: If Podman is not installed, `--nosandbox` behavior
  SHOULD be used with a warning.
- **Ollama not installed**: If `--local` is used but `ollama` is not on
  PATH, agentctl MUST error.
