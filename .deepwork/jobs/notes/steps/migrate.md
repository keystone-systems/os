# Execute Migration

## Objective

Execute the migration plan: add frontmatter, assign IDs, move files to correct directories, and convert links. Each transformation is a separate commit for reversibility.

## Task

1. **Read the migration plan** from `migration_plan.md`.

2. **For each file to migrate**, execute in order:

   a. **Format-specific content conversion** (before frontmatter/move):
   - **Obsidian callouts**: Keep as-is (`> [!type]` is widely supported)
   - **Dataview queries**: Wrap in HTML comment with TODO marker:
     ````
     <!-- TODO: dataview query removed during migration
     ```dataview
     LIST FROM #tag
     ````
     -->
     ```

     ```
   - **Apple Notes HTML**: Strip HTML tags, preserve text content:
     ```bash
     sed -i 's/<br>/\n/g; s/<[^>]*>//g' "$file"
     ```
   - **Obsidian inline tags**: Extract `#tag-name` from body text, add to frontmatter tags array, remove from body

   b. **Add/update YAML frontmatter**:
   - Insert `---` delimiters if absent
   - Add required fields: id, title, type, created, author, tags
   - Preserve any existing frontmatter fields
   - **Obsidian**: Keep `aliases` field if present

   c. **Rename and move the file**:
   - New filename: `{id} {title-slug}.md`
   - Move to target directory (inbox/, literature/, notes/, decisions/, or index/)

   d. **Convert links** (if applicable):
   - Standard markdown links to local files: `[text](file.md)` -> `[[id]]`
   - Obsidian wikilinks by filename: `[[filename]]` -> `[[id]]` (match by old filename)
   - Obsidian embeds: `![[filename]]` -> `![[id]]`
   - Update links in OTHER files that reference this file's old path

   e. **Normalize VCS ref fields** (from the migration plan's ref normalization list):
   - Rename non-standard fields to canonical names (`issue_ref`, `pr_ref`, `milestone_ref`, `repo_ref`)
   - Convert raw GitHub/Forgejo URLs to `gh:<owner>/<repo>#<N>` / `fj:<owner>/<repo>#<N>` format
   - Convert bare issue/PR numbers to include the repo prefix, deriving the repo from `repo_ref` in the same frontmatter or from the project hub note
   - Preserve all other frontmatter fields — this is a rename+reformat only, no content deletion
   - Example transformation:
     ```yaml
     # Before
     issue: 225
     repo: https://github.com/ncrmro/keystone

     # After
     repo_ref: gh:ncrmro/keystone
     issue_ref: gh:ncrmro/keystone#225
     ```

   f. **Apply project ownership tags where the evidence is strong**:
   - Derive project names and aliases from project hub notes in `index/`
   - Search with `rg` or `scripts/find_missing_project_tags.py` to find migrated files that mention a project but still lack that project tag
   - Add the missing project tag when the file has a clear project owner
   - Leave ambiguous ownership untouched and record it in the migration log instead of guessing

   f. **Respect project hub and spike conventions**:
   - Keep project hub notes in `index/`
   - If the repo uses root spike trees, keep `spikes/<slug>/README.md` as the canonical spike note
   - Do not force spike support docs such as `scope.md`, `research.md`, or `prototype/README.md` into `notes/` just because they are markdown
   - If `.zk/config.toml` intentionally ignores spike support docs, preserve that behavior

   g. **Commit this single file's changes**:

   ```bash
   git add -A
   git commit -m "chore(notes): migrate {old-filename} to {type}/{new-filename}"
   ```

3. **Batch mode for large repos** (> 500 files):
   - Group files by source directory
   - Process each batch, committing per-file within the batch
   - After each batch of 50 files, run `zk index` as a sanity check
   - If errors, stop and report — do not continue with broken state

4. **After all files are migrated**, do a final commit for any remaining changes (e.g., deleted empty directories, updated cross-references).

5. **Clean up format artifacts** (final pass):
   - Remove `.obsidian/` directory if present (commit separately: `chore(notes): remove obsidian config`)
   - Remove Apple Notes export artifacts (empty attachment dirs, etc.)
   - Do NOT remove `.deepwork/`, `.claude/`, or other tool directories

6. **Resolve legacy note trees**:
   - Revisit every noncanonical directory identified in the migration plan
   - Migrate all note-like markdown into canonical zk groups unless the plan explicitly marked that subtree as operational residue
   - If a directory still exists afterward, it should contain only operational/generated files or non-markdown assets
   - If note-like markdown remains outside canonical groups, the migration is incomplete
   - Root `spikes/` is allowed when the plan marked it as a canonical spike-note convention rather than a legacy tree

## Output Format

Write `.deepwork/tmp/migration_log.md`:

```markdown
# Migration Log

## Source Format

(Obsidian / Apple Notes / Plain Markdown)

## Transformations

| #   | Old Path              | New Path                            | Type      | ID           | Commit  |
| --- | --------------------- | ----------------------------------- | --------- | ------------ | ------- |
| 1   | journal/2026-03-15.md | notes/202603151200 daily-journal.md | permanent | 202603151200 | abc1234 |

## Format-Specific Conversions

- Dataview blocks commented out: N
- HTML tags stripped: N
- Inline tags extracted: N
- Obsidian callouts preserved: N

## VCS Ref Field Normalization

- Files with ref fields normalized: N
- Field renames applied: (e.g., `issue:` → `issue_ref:`, N files)
- URL-to-prefix conversions: (e.g., `https://github.com/...` → `gh:...`, N files)
- Bare-number expansions: N files

## Project Tag Updates

- Files given missing project tags: N
- Ambiguous project-tag candidates left for manual review: N

## Summary

- Files migrated: N
- Commits created: N
- Batches processed: N (if applicable)
- Errors: 0
```

## Important Notes

- ONE COMMIT PER FILE — this is critical for reversibility (`git revert <hash>` undoes one file)
- NEVER delete note content — only add frontmatter, rename, and move
- Preserve existing frontmatter fields — merge, don't replace
- Skip operational files (TASKS.yaml, SOUL.md, etc.) entirely
- If a file already conforms to the standard, skip it and note "already compliant" in the log
- Obsidian callouts are PRESERVED — they are valid markdown
- Prefer `rg` over `grep` when searching for project-name matches and old link paths
- For large repos, use batch processing with periodic sanity checks
- The migration log is transient workflow state. Store it under `.deepwork/tmp/` and do not commit it.
- Do not declare success while `projects/`, `workflow/`, `spikes/`, or similar legacy directories still contain note-like markdown that should have been migrated.
