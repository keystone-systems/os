# Audit Existing Repo

## Objective

Inventory an existing notes repo to understand its current structure before migration.
If a `detection_report.md` exists from the `detect` step, use it to focus the audit
on format-specific concerns.

## Task

1. **File inventory**: Count all markdown files, grouped by directory:

   ```bash
   rg --files <notes_path> -g '*.md' -g '!.zk/**' -g '!.git/**' -g '!.obsidian/**' -g '!.deepwork/**' -g '!.claude/**' | wc -l
   rg --files <notes_path> -g '*.md' -g '!.zk/**' -g '!.git/**' -g '!.obsidian/**' -g '!.deepwork/**' -g '!.claude/**' | xargs -r -n1 dirname | sort | uniq -c | sort -rn
   ```

2. **Structure detection**: Is the repo flat, shallow (1 level of dirs), or deeply nested?

3. **Frontmatter analysis**: Sample 10-20 markdown files and check:
   - Do they have YAML frontmatter (`---` delimiters)?
   - What fields are present? (title, date, tags, etc.)
   - What format are dates in?
   - Is there any existing ID scheme?

4. **Link format detection**: Search for existing links:

   ```bash
   # Wikilinks (standard and Obsidian-style)
   rg -n '\[\[' <notes_path> -g '*.md' | head -20
   # Markdown links to local files
   rg -n '\[.*\]\((?!http)' <notes_path> -g '*.md' -P | head -20
   # Obsidian embedded files
   rg -n '!\[\[' <notes_path> -g '*.md' | head -10
   ```

5. **Naming convention**: Are files named with dates, slugs, titles, or randomly?

6. **Format-specific analysis** (based on detection_report.md if available):

   **Obsidian vaults:**
   - Count files using callout syntax (`> [!`)
   - Count files with dataview blocks
   - Check for Obsidian-specific frontmatter fields (aliases, cssclass, publish)
   - List Obsidian plugins that affect content format (dataview, templater, etc.)
   - Check for `_archive/` or other Obsidian-convention dirs

   **Apple Notes exports:**
   - Count files with HTML fragments
   - Check for attachment references
   - Identify date patterns from filenames

7. **Operational files**: Identify and list files that MUST NOT be migrated:
   - TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml
   - SOUL.md, AGENTS.md, CLAUDE.md, HUMAN.md
   - SERVICES.md, ARCHITECTURE.md, REQUIREMENTS.md
   - Any dotfiles/directories (.git, .zk, .agents, .deepwork, .envrc, .repos)
   - Build/config files: flake.nix, flake.lock, pyproject.toml, uv.lock, etc.

8. **Canonical hub and spike conventions**: Identify whether the repo already uses:
   - `index/` for project hub notes (`type: index`, usually tagged with `project` plus a project slug)
   - `reports/` as an extra canonical note group
   - `spikes/<slug>/README.md` as the canonical spike note, with sibling `scope.md`, `research.md`, or `prototype/` files treated as support artifacts
   - `.zk/config.toml` ignore rules that intentionally exclude spike support docs from indexing

   If these conventions exist, record them explicitly. Do not treat canonical project hubs or canonical spike README notes as stray legacy content.

9. **Legacy tree inventory**: Explicitly identify noncanonical directories that still contain note-like markdown:
   - Check common legacy trees such as `projects/`, `workflow/`, `research/`, `talks/`, `people/`, `journal/`, `ideas/`, `spikes/`, and `_archive/`
   - Separate them into:
     - note-like markdown that still needs migration
     - operational or generated markdown that should remain excluded
   - If `spikes/` is present, distinguish canonical spike README notes from support docs and from truly stray spike content
   - If a large legacy tree remains, do not stop at the canonical groups — call it out clearly in the audit

10. **VCS ref field audit**: Detect non-normalized repository, issue, milestone, and PR references in frontmatter:

   Canonical field names: `repo_ref`, `issue_ref`, `milestone_ref`, `pr_ref`.
   Canonical formats:
   - Repo-only: `gh:<owner>/<repo>` or `fj:<owner>/<repo>`
   - With number: `gh:<owner>/<repo>#<number>` or `fj:<owner>/<repo>#<number>`

   Search for notes that need normalization:

   ```bash
   # Raw GitHub/Forgejo URLs in frontmatter
   rg -n "https://github\.com|https://git\.ncrmro\.com" <notes_path> -g '*.md' | head -20

   # Bare issue/PR/milestone numbers (e.g., `issue: 225`)
   rg -n "^(issue|pr|milestone|repo):\s+[0-9]" <notes_path> -g '*.md' | head -20

   # Non-standard field names that should be canonical refs
   rg -n "^(github_issue|github_pr|github_repo|forgejo_issue|pr_number|issue_number|issue_url|pr_url):" <notes_path> -g '*.md' | head -20

   # Existing canonical fields with wrong format (should match gh:/fj: prefix)
   rg -n "^(repo_ref|issue_ref|milestone_ref|pr_ref):\s+(?!gh:|fj:)" <notes_path> -g '*.md' -P | head -20
   ```

   Record:
   - Count of files with non-normalized refs
   - What non-standard field names exist
   - What raw URL patterns are present

11. **Project tag gap audit**: Look for files that likely need project tags:

- Derive project names and aliases from project hub notes in `index/` (title, slug tag, and `subprojects:` if present)
- Search across `notes/`, `literature/`, `reports/`, `index/`, and canonical spike `README.md` files for project-name mentions using `rg`
- Prefer `scripts/find_missing_project_tags.py <notes_path>` when available, or reproduce its logic manually with `rg`
- Record the files that appear to reference a project strongly but do not carry the corresponding project tag yet

## Output Format

Write `.deepwork/tmp/audit_report.md` with sections (add `## VCS Ref Field Audit` between `## Naming Conventions` and `## Canonical hub and spike conventions`):

```markdown
# Audit Report

## Summary

- Total markdown files: N
- Files with frontmatter: N
- Files without frontmatter: N
- Existing link format: wikilinks / markdown / mixed / none
- Source format: Obsidian / Apple Notes / Plain Markdown
- Keystone repo: yes / no

## Directory Structure

(tree or listing)

## Frontmatter Analysis

(field frequency table)

## Link Analysis

(existing link patterns)

## Format-Specific Findings

(Obsidian callouts count, dataview usage, Apple Notes HTML fragments, etc.)

## Naming Conventions

(observed patterns)

## VCS Ref Field Audit

- Files with raw GitHub/Forgejo URLs in frontmatter: N
- Files with bare issue/PR/milestone numbers: N
- Non-standard field names found: (list, e.g., `issue:`, `github_issue:`)
- Canonical fields with wrong format: N
- Files already using correct `gh:`/`fj:` prefixed canonical fields: N

## Canonical hub and spike conventions

(project hub notes in `index/`, report group usage, spike README conventions, `.zk/config.toml` ignore rules)

## Legacy Trees Requiring Migration

(noncanonical directories that still contain note-like markdown, plus which content is operational residue)

## Probable missing project tags

(files that mention projects but are missing the corresponding project tags)

## Excluded Files (not to be migrated)

(list of operational/identity/config files)
```

## Important Notes

- Do NOT modify any files during audit — this is read-only
- Do NOT read personal note content in detail — only scan structure and metadata
- Sample files for frontmatter analysis rather than reading every file
- Exclude `.obsidian/`, `.deepwork/`, `.claude/` from file counts and analysis
- Prefer `rg` over `grep` for content discovery and for project-name searches
- The audit report is transient workflow state. Store it under `.deepwork/tmp/` and do not commit it.
