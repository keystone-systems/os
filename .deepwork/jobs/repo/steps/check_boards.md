# Check Boards

## Objective

Verify that each milestone has a corresponding project board and that item counts match the milestone's issue count.

## Prerequisite

Requires `platform_context.md` (board inventory) and `milestones_report.md` (milestone data). Board checks depend on milestones because boards are organized per-milestone.

## Task

### Process

1. **Handle Forgejo early exit**
   - If platform is Forgejo (`boards_api: false`), output manual instructions:
     - Board URL pattern: `https://git.ncrmro.com/{owner}/{repo}/projects`
     - Steps to create a board manually in the web UI
     - Skip all CLI automation steps below

2. **For each open milestone:**

   a. **Check for corresponding board**
   - Match board title against milestone title (from `platform_context.md` boards inventory)
   - GitHub: `gh project list --owner {owner} --format json` and filter by title

   b. **If board exists, verify item count**

   ```bash
   gh project item-list {project_number} --owner {owner} --format json --jq 'length'
   ```

   - Compare board item count against milestone issue count (from `milestones_report.md`)
   - Flag mismatches

   c. **If no board exists**
   - Flag as missing
   - Do NOT create it in the setup workflow — only report
   - Note: the `project_board` job can be used to create and populate boards

3. **Check board columns** (for existing boards)
   - Verify the five standard columns exist: Backlog, To Do, In Progress, In Review, Done
   ```bash
   gh project field-list {project_number} --owner {owner} --format json
   ```

## Output Format

### boards_report.md

```markdown
# Boards Report

## Platform

- **Platform**: [github | forgejo]
- **Boards API**: [true | false]

## Summary

- **Milestones Checked**: [count]
- **Boards Found**: [count]
- **Boards Missing**: [count]
- **Item Count Mismatches**: [count]

## Milestones

### [Milestone Title]

- **Board**: [found (#{number}) | missing]
- **Board URL**: [url | N/A]
- **Milestone Issues**: [count]
- **Board Items**: [count | N/A]
- **Match**: [yes | no — [details] | N/A]
- **Columns OK**: [yes | no — missing: [list] | N/A]

## Forgejo Manual Instructions (if applicable)

[Step-by-step web UI instructions for creating and managing boards, or "N/A — using GitHub CLI"]
```

## Quality Criteria

- Each milestone was checked for a corresponding board
- Board item counts are compared against milestone issue counts
- Missing boards are flagged
- If Forgejo, manual instructions are provided
