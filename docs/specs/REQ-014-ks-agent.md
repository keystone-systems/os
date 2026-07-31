# REQ-014: ks agent / ks doctor

New subcommands for the `ks` infrastructure CLI that launch an AI agent
with full keystone OS context. Uses agentctl under the hood.

Part of the agent terminal session management milestone (alongside
REQ-012 and REQ-013).

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules

- `packages/ks/ks.sh` — ks CLI script
- `conventions/ks-agent.md` — keystone OS archetype definition (new)
- `modules/os/agents/scripts/agentctl.sh` — invoked by ks

## Requirements

### ks agent

**REQ-014.1** `ks agent [args...]` MUST launch Claude Code via agentctl
with the keystone OS archetype/role loaded into its system prompt.

**REQ-014.2** The system prompt MUST include a table of all hosts in the
keystone system, enumerated from `hosts.nix`. The table MUST include the
fields specified in REQ-014.18: name, hostname, role, sshTarget, fallbackIP,
and buildOnRemote status.

**REQ-014.3** The system prompt MUST include all users configured in the
keystone flake (from `keystone.os.users` or the nixos-config).

**REQ-014.4** The system prompt MUST include the current host's identity
(hostname, NixOS generation, host entry from hosts.nix).

**REQ-014.5** The system prompt MUST document the `ks update` workflow:
pull repos → verify clean → lock flake inputs → build all targets →
push flake.lock → deploy sequentially.

**REQ-014.6** The system prompt MUST document conventions for submitting
pull requests to keystone (conventional commits, branch naming, worktree
workflow per `conventions/`).

**REQ-014.7** The system prompt MUST document working with modified
flakes locally: `--override-input` with local `.repos/` clones, `--dev`
mode for skipping pull/lock/push, and the local override auto-detection
in ks.

**REQ-014.8** The system prompt MUST include relevant keystone conventions
from the `conventions/` directory in the keystone repo.

**REQ-014.9** `ks agent` MUST pass through any additional arguments to
the underlying agentctl/claude invocation.

### ks doctor

**REQ-014.10** `ks doctor` MUST launch the same agent as `ks agent` but
with a diagnostic-focused prompt that emphasizes checking host health,
identifying configuration issues, and suggesting fixes.

**REQ-014.11** `ks doctor` SHOULD gather current system state (NixOS
generation, systemd failed units, disk usage, flake lock age) and include
it in the prompt context.

### Local Model Support

**REQ-014.12** `ks agent` and `ks doctor` MUST support a `--local [model]`
flag that uses Ollama instead of Claude via agentctl's `--local` flag.

**REQ-014.13** When `--local` is used, the same system prompt and
conventions MUST be passed to the Ollama model.

### Archetype Definition

**REQ-014.14** The keystone OS archetype MUST be stored at a discoverable
path in the keystone repo (e.g., `conventions/ks-agent.md`).

**REQ-014.15** The archetype MUST be loadable by ks at runtime (not baked
into the Nix package at build time) so it stays up to date with the repo.

**REQ-014.16** The archetype MAY be composed from multiple convention
files in `conventions/`.

### Host Enumeration

**REQ-014.17** `ks agent` MUST enumerate hosts by evaluating `hosts.nix`
using `nix eval` at launch time.

**REQ-014.18** The host table in the system prompt MUST include for each
host: name, hostname, role, sshTarget, fallbackIP, buildOnRemote status.

**REQ-014.19** The current host MUST be highlighted or marked in the
host table.

## Edge Cases

- **No hosts.nix**: If `hosts.nix` cannot be found via repo discovery,
  `ks agent` MUST error with the same message as other `ks` commands.
- **Offline hosts**: Host enumeration reads `hosts.nix` statically, not
  via SSH. Actual host reachability is NOT checked at launch time.
- **No agentctl**: If agentctl is not available (non-NixOS system), `ks agent`
  MUST fall back to launching claude directly with the system prompt
  via `--append-system-prompt`.
