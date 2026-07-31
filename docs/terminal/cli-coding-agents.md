---
title: CLI coding agents
description: How Keystone configures AI coding CLIs with unified skills, MCP, and progressive knowledge loading
---

# CLI coding agents

Keystone manages four AI coding CLIs — Claude Code, Gemini CLI, Codex, and
OpenCode — through a shared Nix module stack. Each CLI receives identical
skills, MCP server definitions, and a slim instruction file adapted to the
tool's native format.

## Architecture

### Progressive knowledge loading

The system host instruction file (CLAUDE.md, GEMINI.md, etc.) is a concise
routing guide — not a convention dump. It lists available skills, universal
rules (commit format, privileged ops, shared surfaces), and reference links.

Domain knowledge loads on demand when a skill is activated:

- `/ks-engineer` — implementation, code review, architecture, CI
- `/ks-product` — press releases, milestones, stakeholder communication
- `/ks-project-manager` — task decomposition, tracking, boards
- `/ks-notes` — durable notebook capture and repair
- `/ks-projects` — project lifecycle workflows

Each skill folder colocates its conventions, role definitions, and DeepWork
routing so all relevant context arrives together.

### Module responsibilities

| Module | Responsibility |
|--------|---------------|
| `agents/ai.nix` | Installs CLI packages and the DeepWork binary |
| `agents/mcp-configs.nix` | Generates MCP server configs at each tool's expected path |
| `agents/extensions.nix` | Defines capabilities, published commands, and skill metadata |
| `keystone-sync-agent-assets.sh` | Generates skills, instruction files, and colocated conventions |

## Skill composition

Skills are defined in the `skills:` section of `conventions/archetypes.yaml`.
Each skill declares which conventions and roles to colocate:

```yaml
skills:
  engineer:
    description: "Engineering — implementation, code review, architecture, and CI"
    template: engineer-skill.template.md
    colocated_conventions:
      - process.feature-delivery
      - process.pull-request
      - process.version-control
      # ...
    colocated_roles:
      - software-engineer
      - code-reviewer
      - architect
```

At generation time, the sync script reads these lists and copies convention
files into each skill directory alongside `SKILL.md`. This means when
`/ks-engineer` is activated, the LLM receives all engineering conventions
without them being pre-loaded in the instruction file.

### All four CLIs use skills

| CLI | Skill path | Colocation | Extra files |
|-----|-----------|-----------|-------------|
| Claude Code | `~/.claude/skills/{name}/SKILL.md` | yes | — |
| Gemini CLI | `~/.gemini/skills/{name}/SKILL.md` | yes | — |
| OpenCode | `~/.config/opencode/skills/{name}/SKILL.md` | yes | — |
| Codex | `~/.codex/skills/{name}/SKILL.md` | yes | `agents/openai.yaml` |

Skills are the canonical format. Claude Code and Gemini CLI automatically
register skills as slash commands. Separate command files are not generated.

### Adding conventions to a skill

To add a convention to an existing skill, add it to `colocated_conventions`
in `archetypes.yaml`:

```yaml
skills:
  engineer:
    colocated_conventions:
      - process.feature-delivery
      - my-company.code-style    # your custom convention
```

The convention file must exist at `conventions/my-company.code-style.md`.

## MCP server configuration

All CLIs share a single `keystone.terminal.cliCodingAgents.mcpServers` option.
The DeepWork MCP server is appended automatically when
`keystone.terminal.deepwork.enable = true`.

| CLI | Config path | Merge strategy |
|-----|------------|----------------|
| Claude Code | `~/.claude.json` | jq — merges `mcpServers` key, preserves runtime state |
| Gemini CLI | `~/.gemini/settings.json` | jq — merges `mcpServers` + `context`, preserves runtime state |
| Codex | `~/.codex/config.toml` | Python TOML rewriter — replaces `[mcp_servers]` section |
| OpenCode | `~/.config/opencode/opencode.json` | jq — merges `.mcp` key, preserves runtime state |

Each activation script follows the same safety pattern:

1. Remove stale Nix store symlink if present.
2. Merge managed keys into existing file (preserving runtime state).
3. Create from scratch on first run.

### Adding an MCP server

```nix
keystone.terminal.cliCodingAgents.mcpServers.my-server = {
  command = "${pkgs.my-mcp-server}/bin/my-server";
  args = [ "--flag" "value" ];
  env = { MY_VAR = "value"; };  # WARNING: stored in Nix store, world-readable
};
```

This definition propagates to all four CLIs automatically.

## Capability-driven generation

The set of published skills depends on resolved capabilities:

| Capability | Skills enabled |
|-----------|---------------|
| (always — no capability gate) | `/ks-system` |
| `assistant` (default) | `/ks-assistant` |
| `project` (default) | `/ks-projects` |
| `notes` (explicit) | `/ks-notes` |
| `engineer` (archetype) | `/ks-engineer` |
| `product` (archetype) | `/ks-product` |
| `project-manager` (explicit) | `/ks-project-manager` |
| `executive-assistant` (explicit) | `/ks-ea` |
| `ks-dev` (dev mode only) | `/ks-dev` |

Defaults come from `baseCapabilities` in `modules/terminal/agents/extensions.nix`
(currently `[ "ks" "assistant" "project" ]`); the `"ks"` tag is internal
plumbing and doesn't add a slash command directly. `notes` is explicit per
host — declare it in `keystone.terminal.aiExtensions.capabilities` or pull
it in via the OS-agent capability list to enable `/ks-notes`.

Capabilities merge from base defaults, archetype defaults (e.g., `engineer`
archetype auto-enables the `engineer` capability), explicit
`aiExtensions.capabilities`, and dev-mode gating.

## Instruction files

The sync script generates a slim instruction file for each CLI:

| CLI | Path |
|-----|------|
| Claude Code | `~/.claude/CLAUDE.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| Codex | `~/.codex/AGENTS.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` |
| Keystone | `~/.keystone/AGENTS.md` (canonical) |

These files contain session metadata, available skill descriptions, brief
universal rules, and reference convention links. They do NOT inline full
convention content — that lives in skills.

## Development mode

When `keystone.development = true`:

- `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` points at local repo checkouts instead of
  Nix store derivations, so job edits take effect immediately.
- Skills and instruction files are written to the live repo checkout (appearing
  as git diffs) rather than via `home.file` symlinks.
- `ks-dev` capability is automatically enabled.

## DeepWork integration

The DeepWork MCP server binary (`pkgs.keystone.deepwork`) is installed by
`agents/ai.nix`. The server discovers jobs from up to three roots via
`DEEPWORK_ADDITIONAL_JOBS_FOLDERS`:

1. **Shared library jobs** — from the `Unsupervisedcom/deepwork` repo's
   `library/jobs/` directory.
2. **Keystone-native jobs (published)** — from
   `ncrmro/keystone/.deepwork/jobs/`. Shipped to adopters via
   `pkgs.keystone.keystone-deepwork-jobs`.
3. **Keystone-native jobs (internal)** — from
   `ncrmro/keystone/.deepwork/jobs-internal/`. Holds keystone-development-only
   plumbing (contributor authoring tools, in-progress stubs); appended to the
   discovery path only in dev mode and intentionally absent from the published
   package, so it never reaches adopter hosts.

In locked mode the first two roots resolve to Nix store copies
(`pkgs.keystone.deepwork-library-jobs` and `pkgs.keystone.keystone-deepwork-jobs`)
and the internal root is absent. In dev mode all three resolve to local
checkouts.
