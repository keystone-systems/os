# Agent Module Architecture

Split from the monolithic `agents.nix` into focused sub-modules for maintainability.

## Directory Structure

```
agents/
  AGENTS.md          -- this file
  default.nix        -- options declaration + barrel imports
  lib.nix            -- shared helpers, constants, filtered agent sets
  types.nix          -- agentSubmodule type definition
  base.nix           -- user creation, groups, tmpfiles, sudo, home dirs, activation
  agentctl.nix       -- agentctl CLI + alias wrappers + MCP config publishing
  desktop.nix        -- labwc + wayvnc services
  chrome.nix         -- Chromium remote debugging services
  dbus.nix           -- D-Bus socket race fix
  mail-client.nix    -- himalaya + mail assertions
  tailscale.nix      -- per-agent Tailscale (currently disabled)
  ssh.nix            -- ssh-agent + assertions
  notes.nix          -- notes-sync, task-loop, scheduler services + timers
  home-manager.nix   -- home-manager terminal integration
  scripts/
    agent-svc.sh     -- per-agent service helper
    task-loop.sh     -- task loop script
    scheduler.sh     -- scheduler script
    agentctl.sh      -- agentctl CLI
```

## How `lib.nix` Works

`lib.nix` is a plain function, not a NixOS module:

```nix
# Each sub-module imports it in its let block:
let agentsLib = import ./lib.nix { inherit lib config pkgs; };
```

It exports: `osCfg`, `cfg`, `keysCfg`, `topDomain`, `agentPublicKey`, `allKeysForAgent`, `agentsWithUids`, `localAgents`, `desktopAgents`, `chromeAgents`, `mailAgents`, `sshAgents`, `tailscaleAgents`, port resolution functions, `agentSvcHelper`, `labwcConfigScript`, `agentMcpConfig`, and all `has*` booleans.

This avoids circular imports. All sub-modules read from the same shared state.

## Shell Script Extraction

Scripts use `pkgs.replaceVars` with `@placeholder@` substitutions (same pattern as `tpm.nix` + `scripts/enroll-tpm.sh`):

- **Coreutils paths** (`@date@`, `@mkdir@`, etc.): Full Nix store paths to avoid PATH dependency
- **Dynamic Nix-computed values** (`@agentHelperCases@`, `@knownAgents@`): String-interpolated at build time
- **All path placeholders** are assigned in double-quoted strings at the script top for valid shell syntax

## Agent Filtering Model

- `cfg` (all agents): Used for user accounts, home dirs, agentctl, dbus fix
- `localAgents` (host-filtered): Used for desktop, chrome, mail, SSH
- `desktopAgents`, `chromeAgents`, `mailAgents`, `sshAgents`: Currently equal to `localAgents`
- `tailscaleAgents`: Currently `{}` (disabled)

## Adding a New Sub-Module

1. Create `new-feature.nix` as a NixOS module: `{ lib, config, pkgs, ... }: ...`
2. Import `lib.nix`: `let agentsLib = import ./lib.nix { inherit lib config pkgs; };`
3. Return `{ config = mkIf (osCfg.enable && cfg != { }) { ... }; }`
4. Add import to `default.nix`

## Agent Option Schema

```nix
keystone.os.agents.drago = {
  uid = null;                    # Auto-assign from 4000+ range
  host = "ncrmro-workstation";   # Where resources are created (feature filtering)
  archetype = "engineer";        # Convention archetype (engineer, product)
  fullName = "Drago";
  email = "agent-drago@example.com";
  terminal.enable = true;
  desktop = { enable = true; resolution = "1920x1080"; vncPort = null; };
  chrome = { enable = true; debugPort = null; mcp.port = null; };
  grafana.mcp = { enable = false; url = "https://grafana.example.com"; };
  mail = { provision = false; address = "agent-drago@example.com"; };
  github.username = "drago";
  forgejo.username = "drago";
  git = { provision = false; username = "drago"; repoName = "agent-space"; };
  passwordManager.provision = false;
  mcp.servers = {};
  # Perception layer: PDF parsing, voice transcription, photo search,
  # screenshot sync, contact linking, activity reconstruction (REQ-023.34).
  perception = {
    enable = false;           # Master switch; all sub-options default to enabled when true
    pdf = {
      enable = true;
      inputDir = null;        # Defaults to ~/documents/inbox
      outputDir = null;       # Defaults to ~/documents/parsed
    };
    voice = {
      enable = true;
      inputDir = null;        # Defaults to ~/voice/inbox
      outputDir = null;       # Defaults to ~/voice/transcripts
      model = "base";         # tiny | base | small | medium | large
    };
    screenshots = {
      enable = true;
      syncOnCalendar = "*:0/5";
    };
    search.enable = true;
    contacts.enable = true;
    processor = {
      enable = true;
      onCalendar = "*:0/30";
      useOllama = false;
    };
  };
  notes = {
    syncOnCalendar = "*:0/5";
    taskLoop = {
      onCalendar = "*:0/5";
      maxTasks = 5;
      defaults = { provider = "claude"; profile = "medium"; };
      ingest.profile = "fast";
      prioritize.profile = "fast";
      execute.profile = "medium";
    };
    scheduler.onCalendar = "*-*-* 05:00:00";
  };
};
```

**Required agenix secrets** (per agent):

- `agent-{name}-ssh-key` — SSH private key
- `agent-{name}-ssh-passphrase` — SSH key passphrase
- `agent-{name}-mail-password` — Stalwart mail password (if `mail.provision = true`)

**CRITICAL**: Mail password secrets MUST list BOTH the agent's `host` (himalaya client)
AND the mail server's host (Stalwart provisioning). Missing either breaks auth silently.

SSH keys are managed via `keystone.keys."agent-{name}"`.

## agentctl CLI (`agentctl.nix`)

`agentctl` dispatches to per-agent helper scripts via sudo:

```bash
agentctl <agent-name> <command> [args...]
```

| Command                              | Description                                             |
| ------------------------------------ | ------------------------------------------------------- |
| `status`, `start`, `stop`, `restart` | `systemctl --user` as the agent                         |
| `journalctl`                         | `journalctl --user` as the agent                        |
| `exec`                               | Run arbitrary command as the agent (diagnostics)        |
| `tasks`                              | Show agent tasks table (pending/in_progress first)      |
| `email`                              | Show agent inbox (recent envelopes)                     |
| `claude`                             | Interactive Claude session in agent notes dir           |
| `gemini`                             | Interactive Gemini session in agent notes dir           |
| `codex`                              | Interactive Codex session in agent notes dir            |
| `opencode`                           | Interactive OpenCode session in agent notes dir         |
| `mail`                               | Send structured email via `agent-mail`                  |
| `vnc`                                | Open remote-viewer to the agent's VNC desktop           |
| `provision`                          | Generate SSH keypair, mail password, and agenix secrets |

**SECURITY**: Per-agent helper scripts hardcode `XDG_RUNTIME_DIR` and allowlist safe
systemctl verbs to prevent LD_PRELOAD injection.

**Testing**: `agentctl` uses `replaceVars` and cannot be tested without a rebuild:

```bash
ks build && ks update --dev
```

## Security: Claude/Gemini Flag Separation

In agentctl's tool dispatch and task-loop:

- `claude` commands: `--dangerously-skip-permissions --mcp-config "$MCP_CONFIG"`
- `gemini` commands: `--yolo`
- `codex` commands: `--full-auto`

These are mutually exclusive per-tool case branches — never combined on a single tool invocation.
