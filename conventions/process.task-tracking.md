## Task Tracking

## TASKS.yaml

1. All tasks MUST be tracked in `TASKS.yaml` at the agent-space root.
2. `TASKS.yaml` MUST be checked for current and historical task context before starting work. See `process.vcs-context-continuity` for standards on public state tracking on Issues/PRs.
3. Task status MUST be updated to `completed` when done.
4. Task names MUST be descriptive slugs (e.g., `daily-priorities-2026-03-12`).
5. Tasks MUST include `source` and `source_ref` to trace where they came from.

## Schema

```yaml
tasks:
  - name: "slug-style-task-name"
    description: "What the task involves"
    status: pending | completed
    source: email | schedule # where the task originated
    source_ref: "email-23-..." # reference to the source
    workflow: "job/workflow" # deepwork workflow used (if any)
    project: "project-name" # which project this relates to
    profile: fast | medium | max # semantic model profile override
    provider: claude | gemini | codex
    model: "provider-specific-model"
    fallback_model: "provider-specific-model"
    effort: low | medium | high | max
    needs: ["other-task-name"] # task dependencies (if any)
```

When these fields are omitted, the task loop MUST fall back to the stage-level
settings (`ingest`, `prioritize`, or `execute`), then to
`keystone.os.agents.<name>.notes.taskLoop.defaults`, then to the built-in stage
and profile defaults. `fallback_model` and `effort` currently affect Claude
only.
