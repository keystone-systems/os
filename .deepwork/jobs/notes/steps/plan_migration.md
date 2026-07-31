# Plan Migration

## Objective

Based on the audit report, propose a concrete migration plan that converts the existing repo to standardized zk structure, with format-specific strategies.

## Task

1. **File classification**: For each markdown file (excluding operational files), determine:
   - Target note type: fleeting, literature, permanent, decision, index, or report
   - Target directory: inbox/, literature/, notes/, decisions/, index/, reports/, or an explicitly preserved spike/support path
   - Classification rationale (brief)

   Classification heuristics:
   - Files with structured analysis or ADR-like format -> `decisions/`
   - Files that summarize external sources (articles, docs) -> `literature/`
   - Files that summarize work done or outcomes captured for a project -> `reports/` if the repo already uses a report group
   - Files that curate links to other files -> `index/`
   - Project hub notes belong in `index/`, even when they are project-specific
   - Files with developed, standalone ideas -> `notes/`
   - Short, unstructured captures -> `inbox/`
   - Canonical spike notes may stay at `spikes/<slug>/README.md` when the repo already uses root spike trees
   - Spike support docs such as `spikes/<slug>/scope.md`, `research.md`, or `prototype/README.md` may remain as artifacts instead of being forced into canonical zk groups

   **Obsidian-specific heuristics:**
   - `_archive/` or `Archive/` contents -> `inbox/` (to be triaged)
   - `_archive/Clippings/` -> `literature/` (web clippings are source summaries)
   - `journal/` or `daily/` -> `notes/` (permanent, timestamped)
   - `people/` -> `notes/` (person notes are permanent knowledge)
   - `projects/` -> preserve as-is or flatten to `notes/` with project tags
   - `ideas/` -> `inbox/` (fleeting captures to be promoted)
   - `research/` -> `literature/` (source-based research)
   - `talks/` -> `literature/` (external content summaries)
   - old spike/prototype notes in `notes/` or `index/` -> consolidate into canonical `spikes/<slug>/README.md` plus support files where the repo already follows that convention

   **Apple Notes heuristics:**
   - Flat files with HTML fragments -> strip HTML, classify by content length
   - Short notes (< 100 words) -> `inbox/`
   - Longer notes -> `notes/`

2. **ID assignment strategy**: Decide how to assign IDs:
   - **Preferred**: Backdate from git history (`git log --follow --diff-filter=A --format=%ai -- <file>`)
   - **Fallback**: Use file modification time (`stat -c %Y <file>`)
   - **Last resort**: Generate new timestamps (only for files with no git history)
   - Handle collisions: if two files share the same minute, offset by 1 minute

3. **Frontmatter plan**: For each file, specify:
   - Fields to add (id, title, type, created, author, tags)
   - How to derive `title` (from existing frontmatter, filename, or first heading)
   - How to derive `tags` (from existing frontmatter, directory name, project hubs, or content keywords)
   - **Obsidian**: Preserve `aliases` field if present; convert Obsidian tags (#tag) to frontmatter tags
   - **Apple Notes**: Derive title from first line of content
   - For project tags, derive the project slug from project hub notes in `index/`, then use `rg`-based matching across note bodies to find files that should inherit that project tag
   - Preserve the repo's existing project tag style if one already exists (`project, catalyst` and `project/catalyst` are both valid house styles; do not rewrite styles unnecessarily)

4. **Directory moves**: Map current paths to target paths.

5. **Link conversion**: Plan conversion to wikilinks:
   - Standard markdown links: `[text](file.md)` -> `[[id]]`
   - Obsidian wikilinks: `[[filename]]` -> `[[id]]` (resolve by filename match)
   - Obsidian embeds: `![[filename]]` -> `![[id]]` (preserve embed syntax)
   - Obsidian block refs: `[[note#^block]]` -> preserve as-is (zk supports these)

6. **Format-specific content conversion plan**:
   - **Obsidian callouts**: Preserve `> [!type]` syntax (widely supported in markdown renderers)
   - **Dataview queries**: Convert to static content or wrap in HTML comments with a TODO marker
   - **Apple Notes HTML**: Strip `<div>`, `<br>`, `<span>` tags, preserve content
   - **Obsidian-specific plugins**: Document which plugin features will lose functionality

7. **Batch strategy for large repos** (> 500 files):
   - Group files by directory for batch processing
   - Prioritize: operational files exclusion -> structure migration -> frontmatter -> links
   - Consider processing in batches of 50-100 files per commit group to avoid huge diffs

8. **Legacy tree disposition**:
   - For every noncanonical directory found in the audit that still contains note-like markdown, specify one of:
     - migrate into canonical zk groups
     - keep in place as operational residue
     - delete only after note content has been preserved elsewhere
   - `projects/` and `workflow/` are not automatically exempt. The plan must explicitly decide whether their markdown is notebook content or operational residue.
   - If the repo already uses root `spikes/` with canonical README notes, classify that as an intentional convention, not a failed migration

9. **VCS ref field normalization plan**: Based on the audit's ref field findings:

   - For each non-standard field name (e.g., `issue: 225`, `github_issue: foo/bar#3`):
     - Map to the canonical field name (`issue_ref`, `repo_ref`, etc.)
     - Convert raw URLs to `gh:<owner>/<repo>#<number>` or `fj:<owner>/<repo>#<number>`
     - Drop the old field and add the normalized one

   Conversion rules:
   - `https://github.com/<owner>/<repo>/issues/<N>` → `issue_ref: gh:<owner>/<repo>#<N>`
   - `https://github.com/<owner>/<repo>/pull/<N>` → `pr_ref: gh:<owner>/<repo>#<N>`
   - `https://github.com/<owner>/<repo>/milestone/<N>` → `milestone_ref: gh:<owner>/<repo>#<N>`
   - `https://github.com/<owner>/<repo>` → `repo_ref: gh:<owner>/<repo>`
   - Forgejo (`git.ncrmro.com`): same patterns with `fj:` prefix
   - Bare number fields (e.g., `issue: 225` with no repo context): derive the repo from
     `repo_ref` if present in the same frontmatter, or from project hub notes

   Record each file that needs ref field corrections so the migrate step can apply them.

10. **Project tag remediation plan**:
   - Use the audit's ripgrep-based findings to list files that likely need project tags
   - Decide whether each gap should be fixed during migration or left as ambiguous/manual follow-up
   - For ambiguous matches, explain why the project ownership is not strong enough to tag automatically

## Output Format

Write `.deepwork/tmp/migration_plan.md`:

```markdown
# Migration Plan

## Source Format

(Obsidian / Apple Notes / Plain Markdown — from audit)

## ID Assignment Strategy

(backdating method + collision handling)

## File Mappings

| Current Path          | Target Path                         | Type      | ID           | Notes             |
| --------------------- | ----------------------------------- | --------- | ------------ | ----------------- |
| journal/2026-03-15.md | notes/202603151200 daily-journal.md | permanent | 202603151200 | Backdate from git |

## Frontmatter Additions

(summary of what needs to be added per file or batch)

## Link Conversions

(before/after examples for each link type found)

## Format-Specific Conversions

(callout handling, dataview handling, HTML stripping, etc.)

## Batch Strategy

(for large repos: processing order, batch sizes)

## Legacy Tree Disposition

(explicit per-directory treatment for `projects/`, `workflow/`, `spikes/`, etc.)

## VCS ref field normalization

(list of files with non-canonical refs, proposed field name mappings, and conversion approach for each URL/bare-number pattern found)

## Project tag remediation

(files or batches that will receive missing project tags, plus any ambiguous leftovers)

## Excluded (no action)

(list of operational files skipped)
```

## Important Notes

- NEVER plan to delete content — only add frontmatter, move files, and convert links
- Files already conforming to the standard should be left as-is
- Obsidian callouts (`> [!type]`) should be PRESERVED, not stripped
- Use `rg`-based project-name discovery instead of ad hoc filename guessing when deciding missing project tags
- The plan must be reviewable before execution (next step is the actual migration)
- For repos > 500 files, include a batch strategy to keep commits manageable
- The migration plan is transient workflow state. Store it under `.deepwork/tmp/` and do not commit it.
