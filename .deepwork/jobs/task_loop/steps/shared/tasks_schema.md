# TASKS.yaml Schema

This is the canonical schema for TASKS.yaml. All steps that modify this file MUST produce output conforming to this schema exactly.

## Structure

```yaml
tasks:
  - name: "task-name" # REQUIRED: kebab-case identifier
    description: "What needs to be done" # REQUIRED: human-readable description
    status: pending # REQUIRED: pending | in_progress | completed | blocked
    project: "project-name" # MAY: project from PROJECTS.yaml
    source: "email" # MAY: where the task came from
    source_ref: "email-42-user@host" # MAY: unique identifier for deduplication
    model: "sonnet" # MAY: execution model override
    workflow: "job/workflow" # MAY: DeepWork workflow to invoke
    needs: ["other-task-name"] # MAY: task names that must complete first
    blocked_reason: "why it's blocked" # MAY: explanation when status is blocked
```

## Rules

1. The file MUST be a valid YAML document
2. The top-level key MUST be `tasks` containing a YAML sequence (list)
3. There MUST NOT be any other top-level keys (no `summary:`, no `metadata:`, etc.)
4. Every task MUST have `name`, `description`, and `status` fields
5. The `status` field MUST be one of: `pending`, `in_progress`, `completed`, `blocked`
6. Field names MUST match this schema exactly -- do not rename, add, or invent fields
7. Do NOT use `id`, `priority`, `urgency`, `effort`, `depends_on`, or any fields not listed above

## Validation

After modifying TASKS.yaml, validate with:

```bash
yq e '.' TASKS.yaml > /dev/null 2>&1 && echo "Valid" || echo "INVALID"
```
