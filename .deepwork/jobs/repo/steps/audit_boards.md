# Audit Boards

## Objective

Full board audit: add missing items, correct wrong statuses, flag stale cards. For Forgejo, output manual instructions.

## Prerequisite

Requires `platform_context.md` and `milestones_audit.md`. Board audit depends on milestone audit because it needs accurate milestone-issue mappings.

## Task

### Process

1. **Handle Forgejo early exit**
   - If platform is Forgejo (`boards_api: false`), output manual review instructions:
     - How to check boards in the web UI at `https://git.ncrmro.com/{owner}/{repo}/projects`
     - Checklist of things to verify manually
     - Skip all CLI automation steps below

2. **For each open milestone with a board:**

   a. **Fetch board items**

   ```bash
   gh project item-list {project_number} --owner {owner} --format json
   ```

   b. **Fetch milestone issues**

   ```bash
   gh issue list --repo {owner}/{repo} --milestone "{milestone}" --state all \
     --json number,title,state,labels
   ```

   c. **Find missing items** — milestone issues not on the board
   - Add missing items:
     ```bash
     gh project item-add {project_number} --owner {owner} \
       --url https://github.com/{owner}/{repo}/issues/{issue_number} \
       --format json
     ```

   d. **Cross-reference statuses** — for each board item:
   - Check linked issue state and PR state
   - Expected status rules:
     - Closed issue → Done
     - Open + non-draft PR with reviewers → In Review
     - Open + draft PR or any open PR → In Progress
     - Open + no PR → Backlog
   - Correct wrong statuses:
     ```bash
     gh project item-edit --id {item_id} --project-id {project_id} \
       --field-id {status_field_id} \
       --single-select-option-id {correct_option_id}
     ```

   e. **Find stale cards** — board items whose linked issue is NOT in the milestone
   - Flag but do NOT auto-remove

3. **For milestones without boards:**
   - Flag as missing
   - Optionally create if there are issues to track (ask user or just report)

## Output Format

### boards_audit.md

```markdown
# Boards Audit

## Platform

- **Platform**: [github | forgejo]
- **Boards API**: [true | false]

## Summary

- **Boards Audited**: [count]
- **Items Added**: [count]
- **Statuses Corrected**: [count]
- **Stale Cards Flagged**: [count]
- **Missing Boards**: [count]

## Per-Board Details

### [Milestone Title] — Board #{number}

**Items Added:**

| Issue # | Item ID | Status Set | Reason |
| ------- | ------- | ---------- | ------ |
| ...     | ...     | ...        | ...    |

**Statuses Corrected:**

| Issue # | Item ID | Old Status | New Status | Reason |
| ------- | ------- | ---------- | ---------- | ------ |
| ...     | ...     | ...        | ...        | ...    |

**Stale Cards:**

| Item ID | Linked Issue | Recommendation |
| ------- | ------------ | -------------- |
| ...     | ...          | ...            |

## Missing Boards

- [Milestone Title] — [count] issues, no board

## Forgejo Manual Instructions (if applicable)

[Manual review checklist, or "N/A"]

## Actions Taken

- [Summary of all automated fixes]

## Remaining Issues

- [Items needing manual attention]
```

## Quality Criteria

- Every milestone's board was inspected
- Missing items were added to boards
- Wrong statuses were corrected based on issue/PR state
- Stale cards (not in milestone) are flagged
- Forgejo repos get manual instructions
