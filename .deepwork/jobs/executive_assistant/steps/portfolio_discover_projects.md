# Discover Projects

## Objective

Scan the user's notes repo to build a complete list of all active projects with their
associated repositories, platforms, and local clone paths.

## Task

Read project data from the notes repo to produce a structured project list. This list
drives the rest of the portfolio review — every project in it will be reviewed.

### Process

1. **Prepare the notes repo — always start from a clean main**

   The portfolio review MUST run against the latest `main` branch in a dedicated
   worktree so it doesn't interfere with any in-progress notes work.

   Per `process.git-repos`, worktrees MUST live at `$WORKTREE_DIR/{owner}/{repo}/{branch}/`
   — never inside the repo itself.

   ```bash
   NOTES_PATH="${NOTES_DIR:-$HOME/notes}"
   BRANCH="portfolio-review/$(date +%Y-%m)"
   # Resolve owner/repo from the notes remote, defaulting to ncrmro/notes
   NOTES_OWNER_REPO=$(git -C "$NOTES_PATH" remote get-url origin \
     | sed 's|.*[:/]\([^/]*/[^/]*\)\.git|\1|')
   WORKTREE_PATH="${WORKTREE_DIR:-$HOME/.worktrees}/${NOTES_OWNER_REPO}/${BRANCH}"
   ```

   a. **Switch the primary checkout to `main` and pull**:
      ```bash
      git -C "$NOTES_PATH" stash            # stash any uncommitted changes
      git -C "$NOTES_PATH" checkout main
      git -C "$NOTES_PATH" pull --ff-only   # fast-forward only — stop on divergence
      ```
      If `pull --ff-only` fails (diverged), stop and report the blocker. Do not
      proceed with a stale repo.

   b. **Create (or reuse) a worktree for this review**:
      ```bash
      if git -C "$NOTES_PATH" worktree list | grep -q "$WORKTREE_PATH"; then
        # Worktree already exists — reuse it
        echo "Reusing existing worktree at $WORKTREE_PATH"
      else
        mkdir -p "$(dirname "$WORKTREE_PATH")"
        git -C "$NOTES_PATH" worktree add -b "$BRANCH" "$WORKTREE_PATH" main
      fi
      ```

   c. **All subsequent work uses `$WORKTREE_PATH`**, not `$NOTES_PATH`.
      Pass `$WORKTREE_PATH` forward as the working notes directory for this run.

2. **Determine the notes repo path**
   - The `notes_path` input specifies where the notes repo lives
   - If `notes_path` was not provided, ask structured questions to determine it:
     offer common paths like `~/code/ncrmro/obsidian`, `~/notes`, or let the user
     specify a custom path
   - Verify the path exists before proceeding

2. **Read the notes repo project index**
   - Check for `PROJECTS.yaml` at the notes repo root — if it exists, use it as the
     primary source (it has priority ordering)
   - Check for `projects/README.md` — this has the full project listing with repos
   - If neither exists, scan `projects/*/` directories for project slugs

3. **For each active project, extract**
   - Project name and slug
   - Repository list (owner/repo format)
   - Platform for each repo (github or forgejo)
   - Any status or priority info from the source file

4. **Detect local clones**
   - For each repo, check if a local clone exists at `~/code/{owner}/{repo}/`
   - Note the local path if present (used by `gather_data` step for git log)

5. **Filter out archived/inactive projects**
   - Projects marked as archived, inactive, or in an `_archive/` directory are excluded
   - Note excluded projects at the bottom for transparency

6. **Determine platform**
   - Repos on `github.com` → platform: github
   - Repos on `git.ncrmro.com` or other Forgejo instances → platform: forgejo
   - If the platform is unclear from the URL, default to github for `github.com` URLs
     and forgejo for everything else

## Output Format

### project_list.md

A structured list of all active projects ready for parallel review.

**Structure**:

```markdown
# Portfolio Project List

**Generated**: [YYYY-MM-DD]
**Source**: [path to notes repo]
**Active Projects**: [count]

## Projects

### keystone

- **Repos**: ncrmro/keystone:github
- **Local**: ~/code/ncrmro/keystone
- **Priority**: 1
- **Notes**: Self-sovereign NixOS infrastructure platform

### catalyst

- **Repos**: ncrmro/catalyst:github
- **Local**: ~/code/ncrmro/catalyst
- **Priority**: 2
- **Notes**: Business project

### meze

- **Repos**: ncrmro/meze:github, ncrmro/meze-rails:github
- **Local**: ~/code/ncrmro/meze, ~/code/ncrmro/meze-rails
- **Priority**: 3
- **Notes**: Meal planning app

[... one section per active project ...]

## Excluded (Archived/Inactive)

- broadscape — archived
- runsum — archived
```

## Quality Criteria

- Every active project from the notes repo is included with at least one repo reference
- Each repo entry specifies the platform (github or forgejo)
- Archived or inactive projects are excluded from the active list and noted separately
- Local clone paths are checked and recorded when present
- The list is ordered by priority if PROJECTS.yaml provides ordering

## Context

This step is the foundation for the entire portfolio review. The project list it produces
determines which projects get reviewed in the parallel `review_one` sub-workflows. Missing
a project here means it won't appear in the final portfolio report.
