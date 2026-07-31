# Gather Project Data

## Objective

Fetch milestones, git activity, and existing profile/charter data for a single project
to provide raw material for the status summary.

## Task

Collect data from three sources for the specified project: platform milestones, git
history, and existing notes repo files.

### Process

1. **Receive project parameters**
   - This step runs as part of the `review_one` sub-workflow, launched by the
     `review_all_projects` orchestration step
   - Inputs (`project_slug`, `project_repos`, `notes_path`) are provided by the
     parent workflow — do not ask the user for them
   - If any input is missing or malformed, ask structured questions to clarify
     (e.g., "Which repos belong to this project?")
   - Parse `project_repos` as comma-separated `owner/repo:platform` entries

2. **Fetch milestones from the platform**

   For each repo in `project_repos`:

   **GitHub repos** (platform: github):

   ```bash
   gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, open_issues, closed_issues, due_on, state, description}'
   ```

   Also fetch open issues and PRs:

   ```bash
   gh issue list --repo {owner}/{repo} --state open --limit 20
   gh pr list --repo {owner}/{repo} --state open --limit 10
   ```

   **Forgejo repos** (platform: forgejo):

   ```bash
   # Use tea or curl with the Forgejo API
   tea milestones list --repo {owner}/{repo}
   tea issues list --repo {owner}/{repo} --state open --limit 20
   ```

   Record for each milestone:
   - Title
   - Open vs closed issue count → completion percentage
   - Due date (if set)
   - State (open/closed)

3. **Fetch git activity (last 30 days)**

   If a local clone exists (check `~/code/{owner}/{repo}/`):

   ```bash
   git -C ~/code/{owner}/{repo} log --oneline --since="30 days ago" | head -30
   git -C ~/code/{owner}/{repo} log --oneline --since="30 days ago" | wc -l
   git -C ~/code/{owner}/{repo} log -1 --format="%ci" 2>/dev/null
   ```

   If no local clone, try:

   ```bash
   gh api repos/{owner}/{repo}/commits --jq '.[0:20] | .[] | {date: .commit.author.date, message: .commit.message}' 2>/dev/null
   ```

   Record:
   - Total commits in last 30 days
   - Last commit date
   - Summary of recent commit messages (top 5-10)

   **Automated commit detection**: Notes repos and config repos often have high commit
   counts from automated sync (repo-sync, agenix relocking). If most recent commits
   follow a repetitive pattern (e.g., "chore: relock", "Auto-sync"), note this in the
   data so the summary step can distinguish human activity from automation.

4. **Read existing project files from notes repo**

   Check `{notes_path}/projects/{project_slug}/` for:
   - `charter.md` — extract mission, KPIs, goals
   - `README.yaml` — extract structured profile data
   - `status.md` — extract most recent status and blockers
   - `README.md` — extract description and goals

   If the project directory doesn't exist, note "No existing profile in notes repo."

5. **Record everything as raw data**

   Combine all collected data into a single raw data file. Include actual CLI output
   and file contents — do not summarize or interpret at this stage.

### Error Handling

- If a repo is not accessible, record the error and continue with other repos
- If git log fails, note "No local clone available" and use API data instead
- If notes repo has no project directory, note this and rely on milestone/git data

## Output Format

### project_data.md

Raw collected data for one project.

**Structure**:

```markdown
# Project Data: [project_slug]

**Collected**: [YYYY-MM-DD HH:MM]
**Repos**: [list of repos checked]

## Milestones

### [repo: owner/repo (platform)]

| Milestone           | Open | Closed | Total | % Complete | Due Date   |
| ------------------- | ---- | ------ | ----- | ---------- | ---------- |
| Desktop Integration | 4    | 8      | 12    | 67%        | 2026-04-01 |
| v2.0 Release        | 10   | 2      | 12    | 17%        | —          |

### Open Issues (top 20)

- #123: Fix boot sequence on AMD hardware (bug, open 5 days)
- #120: Add LUKS2 support (enhancement, open 12 days)

### Open PRs

- PR #125: feat(desktop): add hyprland bindings (draft, 3 days old)

## Git Activity (Last 30 Days)

### [repo: owner/repo]

- **Total commits**: 23
- **Last commit**: 2026-03-19
- **Recent commits**:
  - bfb55a5 Merge branch 'worktree-keystone-desktop-integration'
  - 2f3a9d4 fix(deepwork): add PR Demo section update to engineering review step
  - 5ce7401 fix(desktop): quote parameter expansions in prefix stripping
    [...]

## Existing Profile (from notes repo)

### charter.md

[Full content or "Not found"]

### status.md

[Full content or "Not found"]

### README.yaml / README.md

[Full content or "Not found"]
```

## Quality Criteria

- All repos listed in `project_repos` are queried for milestones (or errors are recorded)
- Git activity includes commit count and last commit date
- Existing notes repo files are read when available
- Raw data is preserved without interpretation — the next step does the analysis

## Context

This step is the data collection workhorse of the `review_one` sub-workflow. It runs
once per project (in parallel with other projects). The raw data it produces feeds
directly into `write_summary` which interprets and formats it.
