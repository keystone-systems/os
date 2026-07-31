# Review Inbox

## Objective

List all fleeting notes in `inbox/`, read each, and classify them for promotion or discard.

## Task

1. List all notes in inbox:

   ```bash
   zk list inbox/ --format json
   ```

2. If inbox is empty, report "Inbox empty — nothing to process" and output an empty classification.

3. For each note, read its content and classify:
   - **promote-to-permanent**: Contains a standalone idea worth preserving as an atomic note
   - **promote-to-literature**: Summarizes or references an external source
   - **discard**: Stale, duplicate, or no longer relevant
   - **keep**: Not ready to process yet (needs more thought)

4. For promotable notes, draft a brief target title and suggested tags.

## Output Format

Write `inbox_review.md`:

```markdown
# Inbox Review

## Classification

| ID           | Title              | Action  | Target Type | Suggested Title                       | Tags        |
| ------------ | ------------------ | ------- | ----------- | ------------------------------------- | ----------- |
| 202603201430 | CI failure pattern | promote | permanent   | CI failures from missing flake inputs | [ci, nix]   |
| 202603201445 | Quick thought      | discard | -           | -                                     | -           |
| 202603201500 | NixOS manual notes | promote | literature  | NixOS module system overview          | [nix, docs] |

## Summary

- Total inbox notes: N
- Promote to permanent: N
- Promote to literature: N
- Discard: N
- Keep: N
```
