# The `.agents/skills/` Convention

A short reference for which CLI agents read which skill directories, and why a single canonical path is starting to win.

## What this is

The **Agent Skills** specification is an open standard for packaging procedural knowledge — a directory containing a `SKILL.md` (YAML frontmatter plus instructions) and optional scripts, references, and assets that an agent loads on demand. Treat it as the convergent phenotype that emerged once every vendor independently reinvented "markdown file with frontmatter the model reads when relevant."

The interesting part is the path. Each agent ships with a vendor-specific home (`.claude/skills/`, `.gemini/skills/`, `.copilot/skills/`, `.kiro/skills/`), and on top of that most have adopted a shared alias — `.agents/skills/` at the workspace tier and `~/.agents/skills/` at the user tier — so one bundle can serve several agents without duplication or symlink gymnastics.

## The shared path

| Tier | Path | Scope |
|------|------|-------|
| Workspace | `.agents/skills/` | Project-specific, committed to VCS |
| User | `~/.agents/skills/` | Personal, shared across projects |

Each skill is a subdirectory:

```
.agents/skills/
└── pr-review/
    ├── SKILL.md          # required: frontmatter + instructions
    ├── scripts/          # optional: helpers the agent may run
    ├── references/       # optional: supporting docs
    └── assets/           # optional: templates, prompts, fixtures
```

## Agents that read `.agents/skills/` natively

### Gemini CLI

Reads both `~/.gemini/skills/` and `~/.agents/skills/` at the user tier, and both `.gemini/skills/` and `.agents/skills/` at the workspace tier. Within the same tier, **the `.agents/skills/` alias takes precedence over the vendor-specific path** — a small but pointed editorial choice, signalling that the shared standard is the canonical surface and the vendor path is the legacy one.

Discovery order, low to high precedence: built-in → extension → user → workspace.

### GitHub Copilot CLI

Personal skills live in `~/.copilot/skills` or `~/.agents/skills`; project skills in `.github/skills`, `.claude/skills`, or `.agents/skills`. The CLI also exposes `/skills reload` to pick up new skills mid-session without restarting.

Agent Skills is treated as an open standard inside Microsoft's stack: skills authored in VS Code work across Copilot in VS Code, Copilot CLI, and the Copilot cloud agent.

### OpenAI Codex

Scans `.agents/skills` in **every directory from the current working directory up to the repository root**, plus user/admin/system locations. Two skills with the same name are not merged — both appear in skill selectors, which is the right call for a system where silent precedence would be a debugging nightmare.

Codex also caps the initial skill list at roughly 2% of the model's context window (or 8,000 characters when the window size is unknown), shortening descriptions before dropping skills entirely. Worth knowing when you're tempted to write a treatise in the `description` field.

### Cursor, Rovo Dev, Augment, Kiro CLI, OpenCode

All listed by Atlassian's TWG installer as agents that read the universal `.agents/skills/` layout out of the box. Kiro additionally supports a `skill://` URI scheme for explicit references, with glob patterns and `~` expansion.

## The Claude Code exception

Claude Code does **not** read `.agents/skills/`. It reads `.claude/skills/` (workspace) and `~/.claude/skills/` (user), full stop.

The ecosystem works around this rather than waiting for it. Atlassian's TWG installer writes the canonical bundle to `~/.agents/skills` and, when it detects Claude Code locally, also copies it to `~/.claude/skills`. `gh skill install` does the same, dispatching to the correct directory per agent host. The result is that Claude Code participates in the standard via shadow-population — the convergence happens at the installer layer rather than in Claude Code itself.

If you're authoring for Claude Code specifically, target `.claude/skills/` directly. If you're authoring for everyone else, target `.agents/skills/` and let an installer handle the Claude Code copy.

## Authoring gotchas

A few sharp edges worth internalising before they cost you an afternoon:

* **The `name` field must match the directory name.** If the directory is `skills/pr-review/`, the frontmatter `name` must be `pr-review`. Mismatch and the skill silently fails to load — no warning, no error, just absence.
* **Don't namespace the `name` field manually.** Prefixes like `myorg/skillname` or `myorg:skillname` cause silent load failure; plugin distribution handles namespacing automatically.
* **Skill names must be lowercase with hyphens.** No underscores, no camelCase.
* **Description is load-bearing.** Implicit invocation depends entirely on the description matching the user's task; front-load the trigger words and keep scope clear, because Codex (and likely others) will truncate descriptions before omitting skills.
* **Progressive disclosure is real.** Agents load only the name and description at session start, the full `SKILL.md` only when the skill is selected, and bundled files only when the instructions reference them. Design the directory accordingly — keep the entry point lean and push detail into referenced files.

## Distribution

For local authoring and repo-scoped workflows, dropping skills into `.agents/skills/` is sufficient. For wider distribution, the emerging conventions are:

* **`gh skill`** (GitHub CLI, public preview since April 2026) — install, pin, preview, update, and publish, with content-addressed change detection via git tree SHAs written into the skill's own frontmatter. Functions as a package manager for skills; pins survive copy-paste because the provenance lives inside the file.
* **Plugins** (Codex, others) — bundle multiple skills with app mappings, MCP server configuration, and presentation assets in a single package.

## Quick reference: where each agent looks

| Agent | User tier | Workspace tier |
|-------|-----------|-----------------|
| Gemini CLI | `~/.gemini/skills/`, `~/.agents/skills/` | `.gemini/skills/`, `.agents/skills/` |
| GitHub Copilot CLI | `~/.copilot/skills/`, `~/.agents/skills/` | `.github/skills/`, `.claude/skills/`, `.agents/skills/` |
| OpenAI Codex | user location + `~/.agents/skills/` | `.agents/skills/` (walked up to repo root) |
| Cursor | `~/.agents/skills/` | `.agents/skills/` |
| Rovo Dev | `~/.agents/skills/` | `.agents/skills/` |
| Kiro CLI | `~/.kiro/skills/`, `~/.agents/skills/` | `.kiro/skills/`, `.agents/skills/` |
| OpenCode | `~/.agents/skills/` | `.agents/skills/` |
| Augment | `~/.agents/skills/` | `.agents/skills/` |
| **Claude Code** | `~/.claude/skills/` _(only)_ | `.claude/skills/` _(only)_ |
