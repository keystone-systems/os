## Issue Journal

## Purpose

This convention defines structured comments that agents MUST post on issues
to provide real-time visibility into task execution. These comments form a
living journal on the issue itself, letting humans and other agents see what
is happening without checking TASKS.yaml or waiting for a PR.

## Scope

1. This convention applies ONLY when a task's `source_ref` points to a GitHub or Forgejo issue URL.
2. Tasks without an issue `source_ref` are exempt from these rules.

## Work Started Comment

3. Agents MUST post a `## Work Started` comment on the source issue BEFORE beginning substantive work.
4. The comment MUST include:
   - Agent name
   - Task name
   - Brief plan (1-3 bullets describing the intended approach)
5. The platform comment timestamp serves as the authoritative record — agents MUST NOT include an explicit timestamp.
6. The comment MUST follow this template:

```
## Work Started

**Agent:** {agent name}
**Task:** {task name}

### Plan
- {bullet 1}
- {bullet 2}
- {bullet 3}
```

## Work Update Comment

7. Agents MUST post a `## Work Update` comment on the source issue AFTER task execution completes or is blocked. See `process.vcs-context-continuity` for content standards when documenting difficulties.
8. The comment MUST include:
   - Agent name
   - Task name
   - Outcome (`completed` or `blocked`)
   - Brief summary of what was done or what blocked progress
   - PR references (if any) or blocker description (if blocked)
9. The comment MUST follow this template:

```
## Work Update

**Agent:** {agent name}
**Task:** {task name}
**Outcome:** {completed | blocked}

### Summary
{1-3 sentences describing what was accomplished or what blocked progress}

### References
- {PR URL, issue URL, or blocker description}
```

## Relationship to Demo Artifacts

10. Issue journal comments do NOT replace the `## Demo Artifacts` comment defined in `process.product-engineering-handoff` (rules 18-21).
11. Demo Artifacts remain a separate post-merge comment — issue journal comments track in-flight work.

## Platform Commands

12. For GitHub issues: `gh issue comment {number} --repo {owner}/{repo} --body "..."`.
13. For Forgejo issues: `fj issue comment {number} --body "..."`.
14. Multi-line comment bodies SHOULD use a HEREDOC to preserve formatting.

## Error Handling

15. Journal comment failures MUST be logged but MUST NOT block task execution.
16. If a comment fails to post, the agent SHOULD continue with the task and note the failure in the task report.
