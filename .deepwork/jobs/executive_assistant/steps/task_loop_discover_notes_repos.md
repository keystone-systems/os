# Discover Notes Repos

## Objective

Find the human and agent notes repos under the keystone owner layout, establish
the working date, and identify which repos participate in this task-loop run.

## Task

Resolve notes repos from `~/.keystone/repos/{owner}/notes` and produce a clean
inventory. This workflow coordinates work across notes repos, so repo discovery
must be explicit before any task-note or daily-note updates happen.

### Process

1. **Establish the working date**
   - Use the `target_date` input when provided.
   - Otherwise use the local current date in ISO 8601 format.
   - Record the human owner. Default to `ncrmro` when `human_owner` is omitted.

2. **Resolve the repo root**
   - Use `notes_root` when provided.
   - Otherwise assume `~/.keystone/repos`.
   - Resolve it to an absolute path before writing the inventory.

3. **Discover owner repos**
   - If `owner_filter` is provided, treat it as the authoritative owner list.
   - Otherwise inspect one level under the repo root and look for `notes/`
     repos.
   - For each owner:
     - record the expected notes path
     - note whether the repo exists
     - note whether it is a git repo
     - note whether `.zk/config.toml` exists

4. **Classify owners**
   - Mark exactly one owner as the human coordination repo.
   - Mark every other discovered notes repo as an agent-owner repo unless the
     environment makes a different role obvious.
   - Missing repos should remain in the report as `missing`, not silently
     dropped.

5. **Flag prerequisites**
   - Note any repos that are missing, not initialized as zk notebooks, or not
     clean git repos.
   - Do not fail the run solely because an agent repo is missing; this workflow
     should degrade gracefully.

## Output Format

### notes_repo_inventory.md

```markdown
# Notes Repo Inventory

- **Working Date**: 2026-03-28
- **Repo Root**: /home/ncrmro/.keystone/repos
- **Human Owner**: ncrmro

## Owners

| Owner | Role | Notes Path | Exists | Git Repo | zk Ready | Status |
| ----- | ---- | ---------- | ------ | -------- | -------- | ------ |
| ncrmro | human | /abs/path/to/notes | yes | yes | yes | active |
| drago | agent | /abs/path/to/notes | yes | yes | yes | active |
| luce | agent | /abs/path/to/notes | no | no | no | missing |

## Constraints

- [Any missing repos or notebook issues]

## Guidance

- The human notes repo is the coordination source of truth for this run.
- Missing owner repos will be skipped during sync unless they appear later.
```

## Quality Criteria

- The report records one working date and one human owner.
- Every owner considered by the run appears in the inventory.
- Absolute notes paths are recorded for existing repos.
- Missing or invalid repos are called out explicitly.

## Context

This step anchors the rest of the workflow. Later steps must not guess where
notes live or which repo is canonical.
