# Verify Initialization

## Objective

Confirm the notebook structure is valid and functional.

## Task

1. Run `zk index` — should complete without errors.

2. Test each group resolves:

   ```bash
   zk list inbox/ --format json 2>&1
   zk list literature/ --format json 2>&1
   zk list notes/ --format json 2>&1
   zk list decisions/ --format json 2>&1
   zk list index/ --format json 2>&1
   ```

   Each should return an empty array or results — no errors.

3. Test template creation for each group:

   ```bash
   zk new inbox/ --title "Test fleeting" --no-input --print-path --dry-run
   ```

   If `--dry-run` is not supported, create a test note, verify frontmatter, then delete it.

4. Verify the index notes from the seed step exist and have valid frontmatter.

## Output Format

Write `init_report.md`:

```markdown
# Initialization Report

## Index Status

- `zk index`: OK (N notes indexed)

## Group Resolution

| Group      | Status | Note Count |
| ---------- | ------ | ---------- |
| inbox      | OK     | 0          |
| literature | OK     | 0          |
| notes      | OK     | 0          |
| decisions  | OK     | 0          |
| index      | OK     | 3          |

## Template Verification

- fleeting: OK (id, title, type, created, author, tags present)
- literature: OK (includes source, source_url)
- permanent: OK
- decision: OK (includes status, supersedes)
- index: OK (includes index tag)

## Overall: PASS
```
