# Sync Owner Notes

## Objective

Mirror assigned task state into owner notes repos while keeping the human daily
note as the canonical coordination record.

Use `shared/task_note_frontmatter.md` as the source of truth for mirrored note
frontmatter.

## Task

Update or create owner-local mirror notes only for tasks assigned to that owner.
Each mirror should point back to the human daily note and preserve the shared-
surface references needed for continuity.

### Process

1. **Read prior context**
   - `notes_repo_inventory.md`
   - `daily_priorities.md`
   - `executive_assistant_daily.md`

2. **Determine mirror set**
   - For each ranked or carry-forward task assigned to an owner other than the
     human:
     - decide whether a mirror already exists
     - decide whether it needs creation, update, or no change

3. **Create or update owner mirrors**
   - Mirror only the assigned work for that owner.
   - Keep shared-surface fields aligned:
     - `project`
     - `assigned_agent`
     - `milestone_ref`
     - `issue_ref`
     - `pr_ref`
     - `repo_ref`
     - `source_ref`
   - Add a backlink to the human daily note.

4. **Preserve local context**
   - If the owner repo already has owner-specific notes or status comments,
     preserve them unless they conflict with the shared state.

5. **Handle missing repos cleanly**
   - If an owner repo is missing or not zk-ready, record the skipped sync in the
     log and continue.

6. **Index changed repos**
   - Run `zk index` in repos that changed.

## Output Format

### owner_sync_log.md

```markdown
# Owner Sync Log

- **Human Daily Note**: /abs/path/to/human/daily-note.md

## Sync Actions

### drago

- **Repo**: /abs/path/to/drago/notes
- **Changed**: yes
- **Updated Mirrors**:
  - /abs/path/to/drago/notes/202603280930 prepare-investor-update.md
- **Backlink Added**: yes

### luce

- **Repo**: missing
- **Changed**: no
- **Reason**: owner notes repo not found
```

## Quality Criteria

- The human daily note remains the coordination source of truth.
- Agent repos receive only assigned-work mirrors.
- Each created or updated mirror backlinks to the human daily note.
- Missing repos are logged without aborting the whole run.

## Context

This step makes the workflow async across notes repos. The human sees the full
ledger, while each owner gets only the work relevant to them.
