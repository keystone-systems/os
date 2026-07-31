# Promote Notes

## Objective

Create permanent or literature notes from promotable fleeting notes, then delete the originals.

## Task

1. Read `inbox_review.md` for the list of notes to promote.

2. For each note classified as "promote":

   a. Read the fleeting note's full content.

   b. Create the new note in the target directory:

   ```bash
   zk new notes/ --title "<suggested title>" --no-input --print-path
   # or
   zk new literature/ --title "<suggested title>" --no-input --print-path
   ```

   c. Edit the new note:
   - Expand and refine the content from the fleeting note
   - For permanent notes: distill to one atomic idea, write clearly
   - For literature notes: add source/source_url, write summary in your own words
   - Add suggested tags to frontmatter
   - Add a `## Links` section (will be populated in the next step)

   d. Delete the original fleeting note from `inbox/`:

   ```bash
   rm inbox/<fleeting-note-filename>.md
   ```

   e. Commit:

   ```bash
   git add -A
   git commit -m "chore(notes): promote <fleeting-id> to <type>/<new-id>"
   ```

3. For notes classified as "discard":
   ```bash
   rm inbox/<note-filename>.md
   git add -A
   git commit -m "chore(notes): discard fleeting note <id>"
   ```

## Output Format

Write `promotion_log.md`:

```markdown
# Promotion Log

## Promoted

| Fleeting ID  | New ID       | Type      | New Path                                               | Commit  |
| ------------ | ------------ | --------- | ------------------------------------------------------ | ------- |
| 202603201430 | 202603201600 | permanent | notes/202603201600 ci-failures-missing-flake-inputs.md | abc1234 |

## Discarded

| ID           | Title         | Commit  |
| ------------ | ------------- | ------- |
| 202603201445 | Quick thought | def5678 |

## Summary

- Promoted: N
- Discarded: N
```
