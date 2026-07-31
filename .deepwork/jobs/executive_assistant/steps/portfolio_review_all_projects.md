# Review All Projects

## Objective

Launch the `portfolio_review_one` sub-workflow for each active project in parallel via sub-agents,
then collect all per-project summaries into a single combined output.

## Task

Read the project list from the previous step and orchestrate parallel reviews of every
project using the `executive_assistant/portfolio_review_one` sub-workflow.

### Process

1. **Read the project list**
   - Parse `project_list.md` from the `discover_projects` step
   - Extract each project's slug, repos (with platforms), local clone paths, and notes path

2. **Launch sub-workflows in parallel**
   - For each project, launch the `executive_assistant/portfolio_review_one` workflow as
     a sub-agent using the Agent tool (Task tool)
   - Pass these inputs to each sub-workflow:
     - `project_slug`: the project's slug (e.g., "keystone")
     - `project_repos`: comma-separated repo list as `owner/repo:platform`
       (e.g., "ncrmro/keystone:github")
     - `notes_path`: the notes repo path from the discover step
   - Launch ALL projects concurrently — do not wait for one to finish before starting
     the next
   - Use the `mcp__deepwork__start_workflow` tool with:
     - `job_name`: "executive_assistant"
     - `workflow_name`: "portfolio_review_one"
     - `goal`: "Review project {slug} for portfolio status"

3. **Collect results**
   - As each sub-workflow completes, read the `project_summary.md` it produced
   - If a sub-workflow fails (e.g., repo not accessible, no milestones found), note the
     failure with the project slug and error — do not block other projects

4. **Combine all summaries**
   - Concatenate all per-project summaries into `all_summaries.md`
   - Preserve the original project ordering from the project list
   - Add a header with completion stats (N of M projects reviewed successfully)

### Error Handling

- If a project's repos are unreachable (e.g., private repo without access), include a
  stub entry noting the access failure
- If git log fails (no local clone), the summary should still include milestone data
- If no milestones exist, the summary should note "No milestones" rather than failing

## Output Format

### all_summaries.md

Combined per-project status summaries from all sub-workflow runs.

**Structure**:

```markdown
# Per-Project Status Summaries

**Generated**: [YYYY-MM-DD]
**Projects Reviewed**: [N] of [M] active projects
**Failed**: [count, if any]

---

## keystone

**Status**: 🟡 At Risk

### Milestones

| Milestone           | Progress   | Target Date |
| ------------------- | ---------- | ----------- |
| Desktop Integration | 8/12 (67%) | 2026-04-01  |

### Recent Activity (30 days)

- 23 commits across 3 PRs
- Last commit: 2026-03-19

### Blockers

- Installer TUI broken (PR #50)

### Next Actions

1. Complete desktop integration milestone
2. Fix installer TUI

---

## catalyst

**Status**: 🟢 On Track

[... repeat for each project ...]

---

## Failed Reviews

### some-project

**Error**: Repository ncrmro/some-project not accessible via gh CLI
```

## Quality Criteria

- Every active project from `project_list.md` has a corresponding summary or failure note
- All per-project summaries follow the same structure
- Projects are in the same order as the project list
- Completion stats in the header are accurate

## Context

This is the orchestration step that enables parallelism. Each project review runs
independently, so a slow or failing review for one project does not block others.
The combined output feeds directly into the final synthesis step.
