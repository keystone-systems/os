# Rollover Daily Note

## Objective

Create or update the executive-assistant daily note for the working date and
carry unfinished work forward by linking existing task notes.

When this step creates or updates task notes as part of rollover, follow the
shared frontmatter contract in `shared/task_note_frontmatter.md`.

## Task

Write the daily coordination artifact into the human notes repo. If a note
already exists for the working date, update it in place. If it does not exist,
create it and link it to the prior daily note when one exists.

### Process

1. **Read prior context**
   - Use `notes_repo_inventory.md` to locate the human notes repo.
   - Use `daily_priorities.md` for the items that belong in today's note.

2. **Find today's note**
   - Search the human repo for an executive-assistant daily note matching the
     working date.
   - If one exists, update it.
   - If not, create a new dated note with `zk new`.
   - Run `zk new` from inside the notebook workdir when creating the note. Do
     not assume `zk --notebook-dir <path> new reports/ ...` will resolve the
     relative note group correctly from an arbitrary shell cwd.

3. **Find yesterday's note**
   - Search for the most recent prior executive-assistant daily note.
   - If it exists, capture its path or note ID for linkage.

4. **Populate the note**
   - Include:
     - working date
     - calendar-critical items
     - ranked priorities
     - delegated work by agent owner
     - waiting or blocked items
     - carry-forward links to unfinished task notes
   - Carry unfinished work forward by linking existing task notes. Do not copy
     and paste full task descriptions into a new note body.

5. **Use explicit metadata**
   - Set frontmatter that keeps the note discoverable, including:
     - `type: report` or another notebook-native type already used for this repo
     - `author`
     - `tags` using approved namespaces only
     - `source_ref` tied to the working date
     - `previous_report` or an equivalent backlink field when the repo pattern
       supports it

6. **Index and verify**
   - Run `zk index` if note creation or linking changed the notebook.
   - If `zk new` fails with a path-outside-the-notebook error, retry from the
     notebook root and record that behavior as an environment note rather than
     silently dropping the failure.

## Output Format

### executive_assistant_daily.md

Provide the absolute path to the updated daily note, followed by a concise
summary:

```markdown
# Executive Assistant Daily Note

- **Path**: /abs/path/to/notes/202603281000 executive-assistant-daily-2026-03-28.md
- **Working Date**: 2026-03-28
- **Previous Note**: /abs/path/to/notes/202603271000 executive-assistant-daily-2026-03-27.md

## Included

- 2 calendar-critical priorities
- 3 delegated items
- 1 blocked item
- 4 carry-forward task-note links
```

## Quality Criteria

- Exactly one daily note is used for the working date.
- Unfinished work is carried forward by link, not by duplicating task bodies.
- The note records delegated work, blockers, and ranked priorities.

## Context

This note is the main coordination artifact for the workflow. Later sync steps
must backlink to it from mirrored owner notes.
