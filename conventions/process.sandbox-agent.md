# Convention: Sandbox Agent Environment (process.sandbox-agent)

## Overview

When an OS agent runs inside a Podman container via `agentctl` / `podman-agent`,
the environment differs from bare-metal execution. This convention documents
what is and isn't available inside the sandbox.

## What's Available

- **CLI coding tools**: Claude Code, Gemini CLI, Codex, OpenCode (pre-resolved from Nix store)
- **Tool instruction files**: `~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md` (mounted from host)
- **MCP configs**: `~/.claude.json`, `~/.gemini/settings.json`, `~/.config/opencode/opencode.json` (mounted from host)
- **Conventions directory**: `~/.config/keystone/conventions/` (mounted read-only from host)
- **SSH keys**: `~/.ssh/` mounted read-only, SSH agent socket forwarded
- **Git config**: `~/.gitconfig` and `~/.config/git/config` mounted read-only
- **GitHub token**: `GH_TOKEN` / `GITHUB_TOKEN` forwarded if set
- **Package manager caches**: npm, pip, uv, cargo, go, pnpm, bun (persistent named volumes)
- **Nix store**: persistent named volume (`nix-agent-store`)
- **Project devshell**: `nix develop` auto-entered if `flake.nix` exists in working directory
- **Utilities**: `gh`, `ripgrep`, `procps`, `process-compose` (pre-resolved or nix-built)
- **Process Compose**: `PC_SOCKET_PATH` (Unix Domain Socket) and `PC_API_TOKEN` forwarded if set. See `tool.process-compose-agent` for interaction standards.
- **MCP Servers**: `process-compose-mcp`, `chrome-devtools-mcp` (via `--chrome` flag)
- **Optional Chrome**: headless Chromium (via `--chrome` flag)

## What's NOT Available

- **systemctl / systemd**: no init system inside the container
- **sudo**: containers run as root but have no host-level privilege
- **Host filesystem**: only the working directory and explicitly mounted paths are visible
- **ks-config / keystone repo**: MUST NOT be mounted — use `ks agent` or `ks doctor` for infrastructure work
- **D-Bus**: no session or system bus
- **Desktop / display**: no Wayland compositor (VNC is host-side only)
- **agenix secrets**: `/run/agenix/` is not mounted — secrets are passed via env vars or CLI args

## MCP Servers Inside Containers

MCP server configs reference absolute Nix store paths. These resolve correctly only
if the store closure is present in the container's persistent Nix volume. On first
launch, `podman-agent` builds or copies the required closures. Subsequent launches
reuse the cached store.

MCP servers that connect to host services (e.g., chrome-devtools connecting to the
agent's Chromium on the host) use `127.0.0.1` which maps to the container's loopback.
For host-bound services, use `--chrome` flag to run Chromium inside the container instead.

## When to Use Sandbox vs Bare-Metal

| Use Case                           | Path                                                |
| ---------------------------------- | --------------------------------------------------- |
| Agent coding tasks (default)       | `agentctl <agent> claude` (sandbox)                 |
| Infrastructure work (ks-config) | `ks agent` or `ks doctor` (bare-metal, full repo)   |
| Debugging sandbox issues           | `agentctl <agent> claude --nosandbox` (bare-metal)  |
| Interactive diagnostics            | `agentctl <agent> shell` (bare-metal as agent user) |
