#!/usr/bin/env bash
# Usage:
#   podman-agent [--chrome] <agent> [agent-args...]
#   podman-agent claude -p "fix the failing tests"
#   podman-agent --chrome claude -p "debug the page"
#   podman-agent gemini "explain this codebase"
#   podman-agent codex "add unit tests"
#   podman-agent opencode
#
# Environment variables:
#   PODMAN_AGENT_INTERACTIVE=1  - Run with TTY (default: auto-detect)
#   PODMAN_AGENT_VOLUME=name    - Nix store volume name (default: nix-agent-store)
#   PODMAN_AGENT_MEMORY=8g      - Container memory limit (default: 4g)
#   PODMAN_AGENT_CPUS=8         - Container CPU limit (default: 4)
#   GH_TOKEN / GITHUB_TOKEN     - GitHub token forwarded to container
#
# Pre-resolved store paths (set by keystone.terminal.sandbox module):
#   PODMAN_AGENT_CLAUDE_CODE_PATH - Store path for claude-code
#   PODMAN_AGENT_GEMINI_CLI_PATH  - Store path for gemini-cli
#   PODMAN_AGENT_CODEX_PATH       - Store path for codex
#   PODMAN_AGENT_GH_PATH          - Store path for gh CLI
#   PODMAN_AGENT_RIPGREP_PATH     - Store path for ripgrep
#   PODMAN_AGENT_PROCPS_PATH      - Store path for procps
#
#   When set, these paths are used directly instead of running
#   `nix build` inside the container, eliminating GitHub flake
#   resolution on every launch.  Falls back to `nix build` when unset.

set -euo pipefail

# -- Parse optional flags ---------------------------------------------------
PODMAN_AGENT_CHROME=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --chrome) PODMAN_AGENT_CHROME=1; shift ;;
    *) break ;;
  esac
done

# -- Parse arguments ---------------------------------------------------------
AGENT="${1:?Usage: podman-agent [--chrome] <agent> [agent-args...]}"
shift

# Map agent name to llm-agents.nix package and CLI command
AGENT_PKG=""
AGENT_CMD=()
AGENT_PATH_VAR=""
case "$AGENT" in
  claude)
    AGENT_PKG="claude-code"
    AGENT_CMD=(claude --dangerously-skip-permissions)
    AGENT_PATH_VAR="PODMAN_AGENT_CLAUDE_CODE_PATH"
    ;;
  gemini)
    AGENT_PKG="gemini-cli"
    AGENT_CMD=(gemini --yolo)
    AGENT_PATH_VAR="PODMAN_AGENT_GEMINI_CLI_PATH"
    ;;
  codex)
    AGENT_PKG="codex"
    AGENT_CMD=(codex --full-auto)
    AGENT_PATH_VAR="PODMAN_AGENT_CODEX_PATH"
    ;;
  opencode)
    AGENT_PKG="opencode"
    AGENT_CMD=(opencode)
    AGENT_PATH_VAR="PODMAN_AGENT_OPENCODE_PATH"
    ;;
  *)
    echo "Unknown agent: $AGENT" >&2
    echo "Supported: claude, gemini, codex, opencode" >&2
    exit 1
    ;;
esac

WORKDIR="$(pwd)"

# -- Already inside a container? Run agent directly -------------------------
# IS_SANDBOX=1 is set by both wrapper scripts and podman-agent itself.
# Skip Podman wrapping -- isolation is already provided by the outer container.
if [[ "${IS_SANDBOX:-}" == "1" ]]; then
  # Use pre-resolved store path if available, fall back to nix build
  AGENT_PATH="${!AGENT_PATH_VAR:-}"
  if [[ -n "$AGENT_PATH" && -d "$AGENT_PATH" ]]; then
    AGENT_BIN="$AGENT_PATH"
  else
    AGENT_BIN=$(nix build --no-link --print-out-paths "github:numtide/llm-agents.nix#$AGENT_PKG")
  fi
  export PATH="$AGENT_BIN/bin:$PATH"

  # Ensure gh CLI and ripgrep are available (pre-resolved or nix build)
  if ! command -v gh &>/dev/null; then
    if [[ -n "${PODMAN_AGENT_GH_PATH:-}" && -d "${PODMAN_AGENT_GH_PATH}" ]]; then
      export PATH="${PODMAN_AGENT_GH_PATH}/bin:$PATH"
    else
      GH_BIN=$(nix build --no-link --print-out-paths "nixpkgs#gh")
      export PATH="$GH_BIN/bin:$PATH"
    fi
  fi
  if ! command -v rg &>/dev/null; then
    if [[ -n "${PODMAN_AGENT_RIPGREP_PATH:-}" && -d "${PODMAN_AGENT_RIPGREP_PATH}" ]]; then
      export PATH="${PODMAN_AGENT_RIPGREP_PATH}/bin:$PATH"
    else
      RG_BIN=$(nix build --no-link --print-out-paths "nixpkgs#ripgrep")
      export PATH="$RG_BIN/bin:$PATH"
    fi
  fi
  if ! command -v pgrep &>/dev/null; then
    if [[ -n "${PODMAN_AGENT_PROCPS_PATH:-}" && -d "${PODMAN_AGENT_PROCPS_PATH}" ]]; then
      export PATH="${PODMAN_AGENT_PROCPS_PATH}/bin:$PATH"
    else
      PROCPS_BIN=$(nix build --no-link --print-out-paths "nixpkgs#procps")
      export PATH="$PROCPS_BIN/bin:$PATH"
    fi
  fi

  # Optional: headless Chrome for chrome-devtools-mcp
  if [[ "${PODMAN_AGENT_CHROME:-}" == "1" ]]; then
    if ! command -v chromium &>/dev/null; then
      CHROMIUM_BIN=$(nix build --no-link --print-out-paths "nixpkgs#chromium")
      export PATH="$CHROMIUM_BIN/bin:$PATH"
    fi
    if ! command -v node &>/dev/null; then
      NODE_BIN=$(nix build --no-link --print-out-paths "nixpkgs#nodejs_22")
      export PATH="$NODE_BIN/bin:$PATH"
    fi

    # Fontconfig + fonts -- nixos/nix:latest has no fontconfig, Skia crashes without it
    FONTCONFIG_BIN=$(nix build --no-link --print-out-paths "nixpkgs#fontconfig")
    DEJAVU_FONTS=$(nix build --no-link --print-out-paths "nixpkgs#dejavu_fonts")
    export PATH="$FONTCONFIG_BIN/bin:$PATH"
    mkdir -p /root/.config/fontconfig /root/.cache/fontconfig
    cat > /root/.config/fontconfig/fonts.conf << FONTCONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$DEJAVU_FONTS/share/fonts</dir>
  <cachedir>/root/.cache/fontconfig</cachedir>
</fontconfig>
FONTCONF
    export FONTCONFIG_FILE=/root/.config/fontconfig/fonts.conf

    # Start headless Chrome if not already running
    if ! pgrep -f 'chromium.*--remote-debugging-port' >/dev/null 2>&1; then
      chromium --headless=new --remote-debugging-port=9222 \
        --user-data-dir=/tmp/chrome-debug-profile \
        --no-sandbox --disable-gpu --disable-dev-shm-usage 2>/dev/null &
      for i in $(seq 1 30); do
        curl -s http://localhost:9222/json/version >/dev/null 2>&1 && break
        sleep 0.5
      done
    fi
  fi

  # Enter project devshell if available, then run agent
  if [ -f "$WORKDIR/flake.nix" ]; then
    exec nix develop "$WORKDIR" \
      --no-update-lock-file \
      --accept-flake-config \
      --command "${AGENT_CMD[@]}" "$@"
  else
    exec "${AGENT_CMD[@]}" "$@"
  fi
fi

# -- Host path: launch in Podman container -----------------------------------

if ! command -v podman &>/dev/null; then
  echo "Error: podman is not installed or not on PATH" >&2
  echo "Enable virtualisation.podman on NixOS or install Podman for your system." >&2
  exit 1
fi

NIX_VOLUME="${PODMAN_AGENT_VOLUME:-nix-agent-store}"
MEMORY_LIMIT="${PODMAN_AGENT_MEMORY:-4g}"
CPU_LIMIT="${PODMAN_AGENT_CPUS:-4}"

# -- Container name ----------------------------------------------------------
# Inside pyclaude: obs-PROJECT_NAME-SLUG (e.g., obs-nixos-config-fix-auth)
# From host: AGENT-DIRNAME (e.g., claude-catalyst)
if [[ -n "${SESSION_SLUG:-}" && -n "${PROJECT_NAME:-}" ]]; then
  CONTAINER_NAME="obs-${PROJECT_NAME}-${SESSION_SLUG}"
else
  CONTAINER_NAME="${AGENT}-$(basename "$WORKDIR")"
fi

# -- TTY detection -----------------------------------------------------------
# Use -it for interactive, -i for background/piped
TTY_FLAGS="-i"
if [[ "${PODMAN_AGENT_INTERACTIVE:-}" == "1" ]] || [[ -t 0 && -t 1 ]]; then
  TTY_FLAGS="-it"
fi

# -- Volume mounts -----------------------------------------------------------
MOUNTS=()
MOUNTS+=(--volume "$NIX_VOLUME:/nix")
MOUNTS+=(--volume "$WORKDIR:$WORKDIR")

# Git worktree support: mount parent .git directory
# In a worktree, .git is a file containing "gitdir: <path>"
if [ -f "$WORKDIR/.git" ]; then
  _gitdir_line=$(head -1 "$WORKDIR/.git")
  _gitdir_path="${_gitdir_line#gitdir: }"
  if [ "$_gitdir_path" != "$_gitdir_line" ] && [ -n "$_gitdir_path" ]; then
    # Resolve relative paths
    if [ "${_gitdir_path#/}" = "$_gitdir_path" ]; then
      _gitdir_path="$(cd "$WORKDIR" && cd "$_gitdir_path" && pwd)"
    fi
    # Find parent .git dir via commondir
    _parent_git=""
    if [ -f "$_gitdir_path/commondir" ]; then
      _commondir=$(cat "$_gitdir_path/commondir")
      _parent_git="$(cd "$_gitdir_path" && cd "$_commondir" && pwd)"
    else
      _parent_git="$(cd "$_gitdir_path/../.." && pwd)"
    fi
    # Verify it's a real .git directory and mount it
    if [ -f "$_parent_git/HEAD" ] && [ -d "$_parent_git/objects" ]; then
      MOUNTS+=(--volume "$_parent_git:$_parent_git")
    fi
  fi
fi

# SSH keys (read-only)
[[ -d "$HOME/.ssh" ]] && MOUNTS+=(--volume "$HOME/.ssh:/root/.ssh:ro")

# SSH agent socket forwarding
# Mount parent directory to avoid podman rootless socket hang
if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -e "$SSH_AUTH_SOCK" ]]; then
  _ssh_dir="$(dirname "$SSH_AUTH_SOCK")"
  MOUNTS+=(--volume "$_ssh_dir:$_ssh_dir")
fi

# Git config (read-only, resolve symlinks for NixOS/Home Manager)
[[ -f "$HOME/.gitconfig" ]] && MOUNTS+=(--volume "$HOME/.gitconfig:/root/.gitconfig:ro")
if [[ -f "$HOME/.config/git/config" ]]; then
  _resolved=$(readlink -f "$HOME/.config/git/config")
  MOUNTS+=(--volume "$_resolved:/root/.config/git/config:ro")
fi

# Agent config directories (API keys, auth tokens, settings)
# Claude config: pyclaude sets CLAUDE_CONFIG_DIR for per-project workspace.
# When called directly (no pyclaude), home config is mounted as fallback below.
[[ -d "$HOME/.gemini" ]] && MOUNTS+=(--volume "$HOME/.gemini:/root/.gemini")
[[ -d "$HOME/.codex" ]] && MOUNTS+=(--volume "$HOME/.codex:/root/.codex")
[[ -d "$HOME/.opencode" ]] && MOUNTS+=(--volume "$HOME/.opencode:/root/.opencode")

# Mount agent config directories set by callers (pyclaude uses CLAUDE_CONFIG_DIR)
[[ -n "${CLAUDE_CONFIG_DIR:-}" && -d "${CLAUDE_CONFIG_DIR}" ]] && \
  MOUNTS+=(--volume "$CLAUDE_CONFIG_DIR:$CLAUDE_CONFIG_DIR")

# Fallback: mount home claude config when CLAUDE_CONFIG_DIR is not set (direct usage)
if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
  [[ -f "$HOME/.claude.json" ]] && MOUNTS+=(--volume "$HOME/.claude.json:/root/.claude.json")
  [[ -d "$HOME/.claude" ]] && MOUNTS+=(--volume "$HOME/.claude:/root/.claude")
fi

# Keystone conventions directory (read-only) for on-demand convention reading.
# Only mount the conventions dir, NOT the full nixos-config or keystone repo —
# agents should use ks agent/doctor for infrastructure work.
[[ -d "$HOME/.config/keystone/conventions" ]] && \
  MOUNTS+=(--volume "$HOME/.config/keystone/conventions:/root/.config/keystone/conventions:ro")

# -- Package manager cache volumes ------------------------------------------
# Named volumes persist across container runs, slashing build times and
# avoiding redundant network downloads. Without these, every `npm install`
# or `cargo build` re-fetches the entire dependency tree from scratch.
# Nix store is already persisted via $NIX_VOLUME above.
#
# Python -- uv is the primary resolver; pip fallback for legacy projects.
MOUNTS+=(--volume "podman-agent-cache-uv:/root/.cache/uv")
MOUNTS+=(--volume "podman-agent-cache-pip:/root/.cache/pip")
#
# Node.js -- npm stores tarballs in ~/.npm; bun uses its own binary cache;
# pnpm uses a content-addressable store with hardlinks.
MOUNTS+=(--volume "podman-agent-cache-npm:/root/.npm")
MOUNTS+=(--volume "podman-agent-cache-bun:/root/.bun/install/cache")
MOUNTS+=(--volume "podman-agent-cache-pnpm:/root/.local/share/pnpm/store")
#
# Rust -- cargo needs both the crate registry and git checkout cache.
MOUNTS+=(--volume "podman-agent-cache-cargo-registry:/usr/local/cargo/registry")
MOUNTS+=(--volume "podman-agent-cache-cargo-git:/usr/local/cargo/git")
#
# Go -- separates compiled build artifacts from downloaded module source.
MOUNTS+=(--volume "podman-agent-cache-go-build:/root/.cache/go-build")
MOUNTS+=(--volume "podman-agent-cache-go-mod:/go/pkg/mod")
#
# Nix -- flake eval cache + fetcher cache. Without this, nix re-resolves
# github: flake refs from the network on every container launch despite
# store paths already being present in the /nix volume.
MOUNTS+=(--volume "podman-agent-cache-nix:/root/.cache/nix")

# -- Environment variables ---------------------------------------------------
ENVS=()
ENVS+=(--env IS_SANDBOX=1)
[[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -e "$SSH_AUTH_SOCK" ]] && ENVS+=(--env SSH_AUTH_SOCK="$SSH_AUTH_SOCK")
[[ -n "${GH_TOKEN:-}" ]] && ENVS+=(--env GH_TOKEN="$GH_TOKEN")
[[ -n "${GITHUB_TOKEN:-}" ]] && ENVS+=(--env GITHUB_TOKEN="$GITHUB_TOKEN")

# Forward agent-specific config env vars set by callers (pyclaude, pygemini)
[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && ENVS+=(--env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR")
[[ -n "${CLAUDE_APPEND_PROMPT:-}" ]] && ENVS+=(--env CLAUDE_APPEND_PROMPT="$CLAUDE_APPEND_PROMPT")
[[ -n "${PROJECT_NAME:-}" ]] && ENVS+=(--env PROJECT_NAME="$PROJECT_NAME")
[[ -n "${SESSION_SLUG:-}" ]] && ENVS+=(--env SESSION_SLUG="$SESSION_SLUG")

# Optional: headless Chrome for chrome-devtools-mcp
[[ "$PODMAN_AGENT_CHROME" == "1" ]] && ENVS+=(--env PODMAN_AGENT_CHROME=1)

# Pre-resolved store paths (set by keystone.terminal.sandbox module)
# Forward the selected agent's path and all tool paths into the container
AGENT_RESOLVED_PATH="${!AGENT_PATH_VAR:-}"
[[ -n "$AGENT_RESOLVED_PATH" ]] && ENVS+=(--env PODMAN_AGENT_RESOLVED_PATH="$AGENT_RESOLVED_PATH")
for _var in PODMAN_AGENT_GH_PATH PODMAN_AGENT_RIPGREP_PATH PODMAN_AGENT_PROCPS_PATH; do
  [[ -n "${!_var:-}" ]] && ENVS+=(--env "$_var=${!_var}")
done

# Binary cache substituters (set by keystone.terminal.sandbox module)
[[ -n "${PODMAN_AGENT_EXTRA_SUBSTITUTERS:-}" ]] && \
  ENVS+=(--env PODMAN_AGENT_EXTRA_SUBSTITUTERS="$PODMAN_AGENT_EXTRA_SUBSTITUTERS")
[[ -n "${PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS:-}" ]] && \
  ENVS+=(--env PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS="$PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS")

# Per-project .env file (pyclaude/pygemini set this for GH_TOKEN, etc.)
[[ -n "${PODMAN_AGENT_ENV_FILE:-}" && -f "$PODMAN_AGENT_ENV_FILE" ]] && \
  ENVS+=(--env-file "$PODMAN_AGENT_ENV_FILE")

# -- Build container command -------------------------------------------------
# The command inside the container:
# 1. Configure nix with flakes support
# 2. Build the agent binary (cached in persistent /nix volume)
# 3. If project has flake.nix, enter devshell with agent on PATH
# 4. Otherwise, just run the agent directly
AGENT_CMD_STR="${AGENT_CMD[*]}"
CONTAINER_SCRIPT='
  # Configure nix
  mkdir -p /etc/nix
  cat > /etc/nix/nix.conf << NIXCONF
experimental-features = nix-command flakes
accept-flake-config = true
sandbox = false
NIXCONF

  # Append extra binary cache substituters if configured
  if [ -n "${PODMAN_AGENT_EXTRA_SUBSTITUTERS:-}" ]; then
    echo "extra-substituters = $PODMAN_AGENT_EXTRA_SUBSTITUTERS" >> /etc/nix/nix.conf
  fi
  if [ -n "${PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS:-}" ]; then
    echo "extra-trusted-public-keys = $PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS" >> /etc/nix/nix.conf
  fi

  # Use pre-resolved store path if available, fall back to nix build
  if [ -n "${PODMAN_AGENT_RESOLVED_PATH:-}" ] && [ -d "$PODMAN_AGENT_RESOLVED_PATH" ]; then
    AGENT_BIN="$PODMAN_AGENT_RESOLVED_PATH"
  else
    AGENT_BIN=$(nix build --no-link --print-out-paths "github:numtide/llm-agents.nix#'"$AGENT_PKG"'")
  fi
  export PATH="$AGENT_BIN/bin:$PATH"

  # gh CLI, ripgrep, procps — pre-resolved or nix build fallback
  if [ -n "${PODMAN_AGENT_GH_PATH:-}" ] && [ -d "$PODMAN_AGENT_GH_PATH" ]; then
    GH_BIN="$PODMAN_AGENT_GH_PATH"
  else
    GH_BIN=$(nix build --no-link --print-out-paths "nixpkgs#gh")
  fi
  if [ -n "${PODMAN_AGENT_RIPGREP_PATH:-}" ] && [ -d "$PODMAN_AGENT_RIPGREP_PATH" ]; then
    RG_BIN="$PODMAN_AGENT_RIPGREP_PATH"
  else
    RG_BIN=$(nix build --no-link --print-out-paths "nixpkgs#ripgrep")
  fi
  if [ -n "${PODMAN_AGENT_PROCPS_PATH:-}" ] && [ -d "$PODMAN_AGENT_PROCPS_PATH" ]; then
    PROCPS_BIN="$PODMAN_AGENT_PROCPS_PATH"
  else
    PROCPS_BIN=$(nix build --no-link --print-out-paths "nixpkgs#procps")
  fi
  export PATH="$GH_BIN/bin:$RG_BIN/bin:$PROCPS_BIN/bin:$PATH"

  # Optional: headless Chrome for chrome-devtools-mcp
  if [ "${PODMAN_AGENT_CHROME:-}" = "1" ]; then
    CHROMIUM_BIN=$(nix build --no-link --print-out-paths "nixpkgs#chromium")
    NODE_BIN=$(nix build --no-link --print-out-paths "nixpkgs#nodejs_22")
    export PATH="$CHROMIUM_BIN/bin:$NODE_BIN/bin:$PATH"

    # Fontconfig + fonts -- nixos/nix:latest has no fontconfig, Skia crashes without it
    FONTCONFIG_BIN=$(nix build --no-link --print-out-paths "nixpkgs#fontconfig")
    DEJAVU_FONTS=$(nix build --no-link --print-out-paths "nixpkgs#dejavu_fonts")
    export PATH="$FONTCONFIG_BIN/bin:$PATH"
    mkdir -p /root/.config/fontconfig /root/.cache/fontconfig
    cat > /root/.config/fontconfig/fonts.conf << FONTCONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$DEJAVU_FONTS/share/fonts</dir>
  <cachedir>/root/.cache/fontconfig</cachedir>
</fontconfig>
FONTCONF
    export FONTCONFIG_FILE=/root/.config/fontconfig/fonts.conf

    chromium --headless=new --remote-debugging-port=9222 \
      --user-data-dir=/tmp/chrome-debug-profile \
      --no-sandbox --disable-gpu --disable-dev-shm-usage 2>/dev/null &

    # Wait for Chrome to be ready (up to 15s)
    for i in $(seq 1 30); do
      if curl -s http://localhost:9222/json/version >/dev/null 2>&1; then
        break
      fi
      sleep 0.5
    done
  fi

  # Enter project devshell if available, then run agent
  if [ -f "$PWD/flake.nix" ]; then
    exec nix develop "$PWD" \
      --no-update-lock-file \
      --accept-flake-config \
      --command '"$AGENT_CMD_STR"' "$@"
  else
    exec '"$AGENT_CMD_STR"' "$@"
  fi
'

# -- Launch ------------------------------------------------------------------
exec podman run --rm $TTY_FLAGS --init \
  --name "$CONTAINER_NAME" \
  --memory "$MEMORY_LIMIT" \
  --cpus "$CPU_LIMIT" \
  "${MOUNTS[@]}" \
  "${ENVS[@]}" \
  --workdir "$WORKDIR" \
  nixos/nix:latest \
  sh -c "$CONTAINER_SCRIPT" -- "$@"
