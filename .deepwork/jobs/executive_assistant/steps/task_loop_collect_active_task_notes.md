# Collect Active Task Notes

## Objective

Discover the active zk task notes and the project context they belong to across
the participating notes repos.

Use the shared frontmatter contract in `shared/task_note_frontmatter.md` when
deciding which fields to read and normalize.

## Task

Search the notes repos for active task-like notes, project hubs, and linked
shared-surface references. The result should describe what work already exists
before the workflow creates or updates anything.

### Process

1. **Read prior context**
   - Use `notes_repo_inventory.md` for repo locations.
   - Use `calendar_context.md` to look for projects or work items that deserve
     extra attention.

2. **Discover project hubs**
   - In each existing repo, use `zk --notebook-dir <path> list index/ --tag "status/active" --format json`.
   - Record project slugs, hub paths, and repo URLs when present.
   - If the canonical query returns zero hubs but `index/` notes clearly carry
     `project:` frontmatter, record that as a notebook-structure mismatch rather
     than pretending no hubs exist.
   - In that fallback case, inspect the project-frontmatter notes, use them as
     provisional hubs for the report, and call out that they need
     `status/active` normalization for future runs.

3. **Pull project stats and recent PRs**

   For each project with a known repo (e.g., `gh:ncrmro/catalyst`), run:

   ```bash
   # Open issues count + milestone summary
   gh issue list --repo <owner/repo> --state open --json number,title,milestone \
     --jq 'length as $count | {open_issues: $count, items: .}'

   # Open PRs
   gh pr list --repo <owner/repo> --state open \
     --json number,title,author,reviewDecision

   # Recently merged PRs (last 5)
   gh pr list --repo <owner/repo> --state merged --limit 5 \
     --json number,title,mergedAt

   # Active milestones
   gh api repos/<owner/repo>/milestones \
     --jq '.[] | {title, open_issues, state}'
   ```

   Record a compact stats block per project in the output. This data feeds the
   Eisenhower matrix in the next step — a project with no recent merges and no
   active milestone is likely a candidate for icebox or delegation.

4. **Discover active task notes**
   - Search `notes/`, `reports/`, and other notebook groups as needed for notes
     that appear to represent active work.
   - Use frontmatter and links first. Useful fields include:
     - `project`
     - `owner`
     - `status`
     - `assigned_agent`
     - `milestone_ref`
     - `issue_ref`
     - `pr_ref`
     - `repo_ref`
     - `source_ref`
     - `next_review`
   - Treat notes with completed or archived status as history, not active work.

5. **Normalize shared-surface refs**
   - Keep tags within the approved namespaces only.
   - If a note encodes milestone, issue, PR, or repo identity in tags or body
     text, record that in the report and recommend frontmatter normalization in
     later updates.

6. **Avoid legacy TASKS.yaml**
   - Do not use legacy task ledgers as the source of truth for this workflow.
   - If you notice them, list them under legacy context only.

7. **Group by project and urgency**
   - Organize the inventory by project when possible.
   - Highlight notes that directly support calendar-critical work.
   - If no active task notes yet use the executive-assistant frontmatter
     contract, say so explicitly. That is a valid smoke-test outcome.

## Output Format

### active_task_notes.md

```markdown
# Active Task Notes

- **Human Repo**: /abs/path/to/ncrmro/notes
- **Repos Scanned**: 3

## Projects

### catalyst

- **Hub**: /abs/path/to/index/202603101200 catalyst.md
- **Repo**: gh:ncrmro/catalyst
- **Stats**: 12 open issues · 2 open PRs · last merge 2026-03-25 · milestone: Cloud Platform (#5, 2 open)

#### Tasks

1. **Prepare investor update**
   - **Note**: /abs/path/to/notes/202603271030 prepare-investor-update.md
   - **Owner**: ncrmro
   - **Status**: active
   - **Assigned Agent**: drago
   - **Milestone Ref**: gh:ncrmro/catalyst#12
   - **Issue Ref**: gh:ncrmro/catalyst#88
   - **PR Ref**: none
   - **Source Ref**: calendar-investor-update-2026-03-28
   - **Calendar Alignment**: supports event on 2026-03-28 14:00

#### Recent Merged PRs

| PR | Title | Merged |
|----|-------|--------|
| #91 | fix: billing webhook retry logic | 2026-03-25 |
| #90 | feat: cloud account onboarding UI | 2026-03-22 |

## Legacy Context

- Legacy YAML task ledgers found:
  - /path/to/legacy/TASKS.yaml
- These files were not used for task discovery in this run.
```

## Quality Criteria

- Project hubs and active task notes are grounded in zk discovery.
- Each active task note includes available project and shared-surface metadata.
- Calendar-relevant tasks are explicitly called out.
- Legacy task ledgers are not treated as authoritative.

## Context

This is the core state-discovery step for the zk-backed task loop. It should
make the existing work visible without mutating it.
