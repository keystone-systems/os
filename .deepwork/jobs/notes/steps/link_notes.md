# Link Notes

## Objective

Ensure newly promoted notes are properly linked to the knowledge graph.

## Task

1. Read `promotion_log.md` for the list of newly promoted notes.

2. For each promoted note:

   a. Search for related existing notes:

   ```bash
   zk list --related <new-note-path> --format json
   zk list --match "<key terms from title>" --format json
   ```

   b. Add wikilinks in the new note's `## Links` section to the most relevant existing notes.

   c. Optionally add backlinks in the related notes pointing to the new note.

3. Update relevant index notes:

   a. Find index notes whose topic matches the new note:

   ```bash
   zk list index/ --format json --match "<topic>"
   ```

   b. Add a wikilink to the new note in the index's `## Notes` section.

4. Commit all link additions:
   ```bash
   git add -A
   git commit -m "chore(notes): link newly promoted notes to knowledge graph"
   ```

## Output Format

Write `link_report.md`:

```markdown
# Link Report

## Links Added

| Note                       | Links To                        | Linked From                         |
| -------------------------- | ------------------------------- | ----------------------------------- |
| 202603201600 (CI failures) | [[202603101430]] (Nix patterns) | index/202603201430 (Infrastructure) |

## Index Notes Updated

- index/202603201430 (Infrastructure): added [[202603201600]]

## Orphan Check

- Permanent notes without links: 0
```
