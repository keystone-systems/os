# Project Context for Notes Job

## Codebase Structure

- This is an Obsidian vault with ~2059 markdown files
- Has keystone markers: TASKS.yaml, AGENTS.md, KEYSTONE_AGENTS_METRICS.md
- Has Nix devshell: flake.nix, flake.lock, pyproject.toml, uv.lock
- Symlink: `me.md -> people/nicholas-romero.md`

## Directory Layout

- `journal/` — Daily journals, organized by `YYYY/MM_MonthName/` (largest group, ~300+ files)
- `ideas/` — Idea captures (~29 files)
- `projects/` — Project-specific notes with subdirs per project (plant-caravan, meze, ks.systems, keystone)
- `people/` — Person notes (~9 files)
- `research/` — Research notes
- `talks/` — Talk notes
- `_archive/` — Archived content including `Clippings/` (web clippings, ~10 files)
- `workflow/` — Workflow documentation
- Root files: daily.md, weekly.md, scratch.md, notes.md, Welcome.md, user-status.md

## Job-Specific Context

### notes.setup / notes.doctor

#### Keystone Detection

- This repo IS a keystone repo. Markers: TASKS.yaml, AGENTS.md
- Operational files to exclude: TASKS.yaml, AGENTS.md, KEYSTONE_AGENTS_METRICS.md, TOOLS.md, WRITING_STYLE.md

#### Source Format

- Obsidian vault (`.obsidian/` directory present if not in worktree)
- Uses Obsidian wikilinks `[[filename]]`
- Journal uses nested date dirs: `journal/2025/08_August/`
- Projects use nested structure: `projects/{name}/latinum/`, `projects/{name}/ideas/`

#### Migration Considerations

- `_archive/Clippings/` → `literature/` (web clippings are source summaries)
- `journal/` → `notes/` with date-based IDs from directory path
- `ideas/` → `inbox/` (fleeting captures)
- `people/` → `notes/` with person tags
- `projects/` — complex nested structure, may need flattening with project tags
- `research/` → `literature/`
- `talks/` → `literature/`
- `daily.md`, `weekly.md` → `index/` (recurring summaries are Maps of Content)
- `scratch.md` → `inbox/` (fleeting)

#### Config Files to Exclude

- flake.nix, flake.lock, pyproject.toml, uv.lock
- bin/ directory (scripts)
- age-yubikey-identity-959abae0.txt (encryption key)
- README.md (repo docs, not a note)

## Last Updated

- Date: 2026-03-21
- From conversation about: Creating notes_setup workflow and learning from format detection requirements

## Learnings

### 2026-03-25 — Notes doctor reports belong in `.deepwork/tmp/`

- `audit_report.md`, `migration_plan.md`, `scaffold_report.md`, `migration_log.md`, and `doctor_report.md` are transient workflow artifacts, not notebook content.
- Future `notes/doctor` and related runs should write those files under `.deepwork/tmp/` and return those paths to DeepWork instead of creating tracked files at the repo root.

### 2026-03-25 — Doctor must not stop while legacy note trees still exist

- A notes repo is not fully migrated just because `inbox/`, `literature/`, `notes/`, `decisions/`, and `index/` are populated.
- `projects/`, `workflow/`, `spikes/`, and similar legacy trees must be explicitly audited for remaining note-like markdown.
- Verification should fail if those trees still contain notebook content that was not either migrated or explicitly classified as operational residue.

### 2026-03-25 — Project hubs and spikes are first-class notebook conventions in `~/notes`

- In the current human notes repo, project hubs live in `index/` and should stay there. See `/home/ncrmro/notes/index/202509151525 projects.md` and the per-project hub notes in `/home/ncrmro/notes/index/`.
- Root `spikes/` is intentional. Canonical spike notes live at `spikes/<slug>/README.md`, while `scope.md`, `research.md`, and `prototype/` markdown are support artifacts. See `/home/ncrmro/notes/.zk/config.toml` and `/home/ncrmro/notes/spikes/`.
- When auditing missing project tags, derive project aliases from the project hub notes in `index/`, then use `rg` across `notes/`, `literature/`, `reports/`, `index/`, and spike `README.md` files to find strong ownership matches before editing tags.
