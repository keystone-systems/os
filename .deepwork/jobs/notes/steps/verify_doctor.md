# Verify Migration

## Objective

Run post-migration health checks to confirm the notebook is valid and no data was lost.

## Task

1. **Index check**: Run `zk index` — should complete without errors.

2. **Frontmatter coverage**: Check all markdown files in `notes/`, `literature/`, `decisions/`, and `index/` have valid frontmatter:

   ```bash
   # List files missing frontmatter
   for f in notes/*.md literature/*.md decisions/*.md index/*.md reports/*.md; do
     [ -f "$f" ] && head -1 "$f" | grep -q "^---" || echo "MISSING: $f"
   done
   ```

3. **Required fields**: Spot-check 5-10 migrated files for all required fields (id, title, type, created, author, tags).

4. **Orphan check**: Find permanent notes with no links:

   ```bash
   zk list notes/ --orphan --format json
   ```

   Report the count. Orphans are acceptable post-migration but should be addressed over time.

5. **Dead link check**: Search for wikilinks pointing to non-existent notes:

   ```bash
   # zk lsp diagnostics can detect this, or:
   rg -o '\[\[[0-9]{12}\]\]' notes/ literature/ decisions/ index/ reports/ | sort -u | while read link; do
     id=$(echo "$link" | tr -d '[]')
     zk list --format json --match "id: $id" | grep -q "$id" || echo "DEAD: $link"
   done
   ```

6. **Operational files intact**: Verify TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml are unchanged:

   ```bash
   git diff HEAD~N -- TASKS.yaml PROJECTS.yaml SCHEDULES.yaml
   ```

   (where N = number of migration commits)

7. **Content preservation**: Verify total markdown content is preserved:

   ```bash
   # Compare word count before/after (approximate check)
   git stash  # or compare against pre-migration commit
   ```

8. **Stray note tree check**: Verify that noncanonical directories do not still contain note-like markdown requiring migration:

   ```bash
   find projects workflow research talks people journal ideas spikes _archive -name "*.md" 2>/dev/null
   ```

   Classify any remaining markdown as either:
   - operational/generated residue that is intentionally excluded, or
   - missed notebook content, which should fail verification

9. **Project hub and spike convention check**:
   - If `index/` contains project hub notes, confirm they remain in `index/` and are not mixed with stray spike prototypes or migrated artifact docs
   - If the repo uses root `spikes/`, confirm canonical spike notes live at `spikes/<slug>/README.md`
   - Confirm spike support docs such as `scope.md`, `research.md`, and `prototype/README.md` are either intentionally ignored by `.zk/config.toml` or explicitly treated as support artifacts

10. **VCS ref field compliance check**: Verify all notes use canonical ref field names and formats:

   ```bash
   # Any remaining raw GitHub/Forgejo URLs in frontmatter
   rg -n "^(repo_ref|issue_ref|milestone_ref|pr_ref):\s+https://" <notes_path> -g '*.md'

   # Any remaining non-standard field names
   rg -n "^(issue|pr|milestone|repo|github_issue|github_pr|forgejo_issue|issue_url|pr_url):" <notes_path> -g '*.md'

   # Canonical fields missing the required prefix
   rg -n "^(repo_ref|issue_ref|milestone_ref|pr_ref):\s+(?!gh:|fj:)" <notes_path> -g '*.md' -P
   ```

   - PASS: zero raw URLs and zero non-standard field names remain
   - FAIL: any raw URL or non-standard field name found in frontmatter

11. **Missing project tag check**:

- Run `scripts/find_missing_project_tags.py .` from the repo root, or reproduce its logic with `rg`
- Report likely missing project tags in `notes/`, `literature/`, `reports/`, `index/`, and canonical spike README files
- Distinguish between:
  - strong misses that should fail verification
  - ambiguous matches that should be called out for manual follow-up

## Output Format

Write `.deepwork/tmp/doctor_report.md`:

```markdown
# Doctor Report

## Index Status

- `zk index`: OK (N notes indexed)

## Frontmatter Coverage

- notes/: N/N files have valid frontmatter
- literature/: N/N
- decisions/: N/N
- index/: N/N
- reports/: N/N
- inbox/: N/N (frontmatter optional for fleeting)

## Orphan Notes

- Count: N orphan permanent notes
- (list if < 10)

## Dead Links

- Count: N dead wikilinks
- (list if any)

## Remaining Noncanonical Markdown

- `projects/`: migrated / operational-only / failed
- `workflow/`: migrated / operational-only / failed
- Other legacy trees: ...

## Project hubs and spikes

- Project hubs in `index/`: OK / FAIL
- Canonical spike README notes: OK / FAIL
- Spike support docs: intentionally ignored / explicit artifacts / failed

## VCS ref field compliance

- Raw URLs remaining in ref fields: N (PASS if 0)
- Non-standard field names remaining: N (PASS if 0)
- Malformed `gh:`/`fj:` refs: N (PASS if 0)

## Missing project tags

- Strong misses: N
- Ambiguous candidates: N
- (list strong misses; summarize ambiguous ones)

## Operational Files

- TASKS.yaml: unchanged
- PROJECTS.yaml: unchanged
- SCHEDULES.yaml: unchanged

## Overall: PASS / FAIL
```

## Important Notes

- The doctor report is transient workflow state. Store it under `.deepwork/tmp/` and do not commit it.
- The workflow should FAIL if substantial note-like markdown still lives outside canonical groups without an explicit operational-residue justification.
- The workflow should also FAIL if there are obvious missing project tags on clearly project-owned notes after migration.
