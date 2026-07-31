---
title: CLI coding agent hooks
description: Cross-provider comparison of hook systems in Claude Code, Gemini CLI, Codex, and OpenCode
---

# CLI coding agent hooks

All four CLI coding agents Keystone manages support extensibility through
lifecycle hooks — shell commands (or plugins) that fire at defined points during
a session. This document maps the common ground across providers and notes where
they diverge.

**Provider documentation:**

- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Gemini CLI hooks](https://geminicli.com/docs/hooks/)
- [Codex hooks](https://developers.openai.com/codex/hooks)
- [OpenCode plugins](https://opencode.ai/docs/plugins/) (event-based plugin system)

## Architecture comparison

| Aspect | Claude Code | Gemini CLI | Codex | OpenCode |
|--------|-------------|------------|-------|----------|
| Mechanism | Shell commands, HTTP, prompts, agents | Shell commands | Shell commands | JS/TS plugin functions |
| Config format | JSON in settings files | JSON in settings files | `hooks.json` | `opencode.json` + JS exports |
| Communication | JSON on stdin/stdout | JSON on stdin/stdout | JSON on stdin/stdout | Function arguments |
| Event count | 25+ | 11 | 5 | 20+ (event bus) |
| Matcher support | Regex on tool names and event subtypes | Regex on tool names, exact match on lifecycle | Regex on tool names | N/A (subscribe by event key) |

## Common lifecycle events

Six lifecycle concepts appear across most or all providers. The table maps each
concept to the provider-specific event name.

| Concept | Claude Code | Gemini CLI | Codex | OpenCode |
|---------|-------------|------------|-------|----------|
| Session start | `SessionStart` | `SessionStart` | `SessionStart` | `session.created` |
| Session end | `SessionEnd` | `SessionEnd` | — | `session.deleted` |
| Before tool execution | `PreToolUse` | `BeforeTool` | `PreToolUse` | `tool.execute.before` |
| After tool execution | `PostToolUse` | `AfterTool` | `PostToolUse` | `tool.execute.after` |
| User prompt submitted | `UserPromptSubmit` | `BeforeAgent` | `UserPromptSubmit` | — |
| Turn completed | `Stop` | `AfterAgent` | `Stop` | `session.idle` |
| Permission requested | `PermissionRequest` | — | — | `permission.asked` |
| Task created | `TaskCreated` | — | — | `todo.updated` |
| Task completed | `TaskCompleted` | — | — | `todo.updated` |
| Context compaction | `PreCompact` / `PostCompact` | `PreCompress` | — | `session.compacted` |
| Notification | `Notification` | `Notification` | — | `tui.toast.show` |

## Common input data

All shell-based providers (Claude Code, Gemini CLI, Codex) pass a JSON object on
**stdin** with these shared fields:

| Field | Claude Code | Gemini CLI | Codex | Description |
|-------|:-----------:|:----------:|:-----:|-------------|
| `session_id` | yes | via env var | yes | Unique session identifier |
| `cwd` | yes | via env var | yes | Current working directory |
| `hook_event_name` | yes | — | yes | Which event fired |
| Project directory | `CLAUDE_PROJECT_DIR` env | `GEMINI_PROJECT_DIR` env | — | Absolute path to project root |

OpenCode passes a **context object** instead, containing `project`, `directory`,
`worktree`, and a `client` SDK handle.

### Session start input

| Field | Claude Code | Gemini CLI | Codex |
|-------|:-----------:|:----------:|:-----:|
| `source` (startup/resume/clear) | yes | yes (via matcher) | yes |
| `model` | yes | — | yes |

### Pre-tool-use input

| Field | Claude Code | Gemini CLI | Codex |
|-------|:-----------:|:----------:|:-----:|
| `tool_name` | yes | yes (via matcher) | yes (Bash only) |
| `tool_input` (arguments) | yes | yes | yes |
| `tool_use_id` | yes | — | yes |

### Post-tool-use input

| Field | Claude Code | Gemini CLI | Codex |
|-------|:-----------:|:----------:|:-----:|
| `tool_name` | yes | yes (via matcher) | yes (Bash only) |
| `tool_input` | yes | yes | yes |
| `tool_response` | yes | yes | yes |

### User prompt input

| Field | Claude Code | Gemini CLI | Codex |
|-------|:-----------:|:----------:|:-----:|
| `prompt` | yes | yes | yes |

### Stop / turn-completed input

| Field | Claude Code | Gemini CLI | Codex |
|-------|:-----------:|:----------:|:-----:|
| `last_assistant_message` | — | — | yes |
| `stop_hook_active` | — | — | yes |

## Common output format

Shell-based providers share a JSON output protocol on **stdout**:

```json
{
  "continue": true,
  "stopReason": "optional reason if continue=false",
  "systemMessage": "optional warning injected into context",
  "suppressOutput": false
}
```

### Exit codes

All three shell-based providers use the same exit code semantics:

| Exit code | Behavior |
|-----------|----------|
| **0** | Success — stdout parsed as JSON |
| **2** | Blocking error — stderr sent as rejection reason, stdout ignored |
| **Other** | Non-blocking warning — execution continues |

### Pre-tool-use decisions

The pre-tool-use hook is the primary gate for controlling tool execution. All
three shell providers support blocking via either exit code 2 or JSON output:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny",
    "permissionDecisionReason": "explanation"
  }
}
```

Claude Code extends this with `"ask"` and `"defer"` decisions and supports
`updatedInput` to modify tool arguments before execution. Gemini CLI also
supports argument modification.

### Session start output

All three shell providers support injecting additional context into the session
via the hook's stdout:

| Capability | Claude Code | Gemini CLI | Codex |
|------------|:-----------:|:----------:|:-----:|
| Inject context | `additionalContext` in JSON | JSON stdout | Plain text stdout |
| Set env vars | `CLAUDE_ENV_FILE` | — | — |
| Block session | exit code 2 | exit code 2 | — |

## Provider-specific events

### Claude Code only

Claude Code has the richest hook surface. Events unique to it include:

- `InstructionsLoaded` — fires when CLAUDE.md or rules files load
- `PermissionDenied` — fires when auto-mode classifier denies a tool call
- `PostToolUseFailure` — fires when a tool call fails
- `SubagentStart` / `SubagentStop` — fires when subagents spawn or finish
- `TeammateIdle` — fires when an agent team member goes idle
- `StopFailure` — fires on API errors (rate limit, auth failure, etc.)
- `ConfigChange` — fires when settings files change during a session
- `CwdChanged` / `FileChanged` — file system watchers
- `Elicitation` / `ElicitationResult` — MCP server user-input requests
- `WorktreeCreate` / `WorktreeRemove` — git worktree lifecycle

Claude Code also supports four hook types: `command`, `http`, `prompt`, and
`agent`. The other providers support only shell commands.

### Gemini CLI only

- `BeforeModel` / `AfterModel` — wrap the LLM request itself (can modify
  prompts or mock responses)
- `BeforeToolSelection` — fires before the LLM chooses which tools to call

Gemini CLI fingerprints project-level hooks and shows a security warning if a
hook's command changes between runs.

### OpenCode only

OpenCode uses a JavaScript plugin system rather than shell hooks. Plugins are
npm packages that export async functions returning event handler maps:

```javascript
export const MyPlugin = async (ctx) => {
  return {
    "tool.execute.before": async (input, output) => { /* ... */ },
    "session.created": async (input, output) => { /* ... */ }
  }
}
```

Unique event categories include `lsp.client.diagnostics`, `file.watcher.updated`,
`installation.updated`, and `tui.command.execute`. OpenCode also provides access
to the full SDK client and Bun's shell API within plugin context.

## Configuration structure

All shell-based providers use a similar JSON structure with matchers and handler
arrays:

```json
{
  "hooks": {
    "EventName": [
      {
        "matcher": "regex_pattern",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/script.sh",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

### Configuration file locations

| Scope | Claude Code | Gemini CLI | Codex |
|-------|-------------|------------|-------|
| User | `~/.claude/settings.json` | `~/.gemini/settings.json` | `~/.codex/hooks.json` |
| Project | `.claude/settings.json` | `.gemini/settings.json` | `.codex/hooks.json` |
| System | Managed policy | `/etc/gemini-cli/settings.json` | — |

OpenCode uses `opencode.json` (project) and `~/.config/opencode/opencode.json`
(global), with plugins loaded from `.opencode/plugins/` or
`~/.config/opencode/plugins/`.

## Designing cross-provider hooks

When writing hooks that target multiple providers, keep these constraints in
mind:

1. **Stick to the common five events** — session start, pre-tool-use,
   post-tool-use, user prompt submit, and stop are the only events all three
   shell providers share.
2. **Read JSON from stdin, write JSON to stdout** — this protocol is identical
   across Claude Code, Gemini CLI, and Codex.
3. **Use exit code 2 for hard blocks** — all three providers treat it as a
   blocking error with stderr as the reason.
4. **Check `hook_event_name`** — a single script can handle multiple events by
   dispatching on this field (present in Claude Code and Codex; infer from
   stdin structure for Gemini CLI).
5. **Pre-tool-use is Bash-only in Codex** — Codex currently only intercepts
   Bash tool calls, while Claude Code and Gemini CLI intercept all tools.
6. **OpenCode requires a different approach** — its plugin system is
   fundamentally JS/TS, not shell scripts. A cross-provider hook strategy
   needs a thin JS wrapper that calls the same underlying script.
