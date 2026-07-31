## Nested Claude Sessions

## Testing Workflows

1. To test a workflow step from inside an active Claude Code session, the `CLAUDECODE` env var MUST be unset before calling `claude --print`.
2. Nested sessions SHOULD use a timeout to prevent hangs: `timeout 180 claude --print ...`.
3. The `--dangerously-skip-permissions` flag MAY be used in automated test contexts.

```bash
unset CLAUDECODE && timeout 180 claude --print --dangerously-skip-permissions --model haiku -p "prompt here"
```

Without `unset CLAUDECODE`, Claude Code refuses to launch with "cannot be launched inside another Claude Code session."
