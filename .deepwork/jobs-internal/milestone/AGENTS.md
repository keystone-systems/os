# Job Management

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended Workflows

- `deepwork_jobs/new_job` - Full lifecycle: define → implement → test → iterate
- `deepwork_jobs/learn` - Improve instructions based on execution learnings
- `deepwork_jobs/repair` - Clean up and migrate from prior DeepWork versions

## Directory Structure

```
.
├── .deepreview        # Review rules for the job itself using Deepwork Reviews
├── AGENTS.md          # This file - project context and guidance
├── job.yml            # Job specification (created by define step)
├── steps/             # Step instruction files (created by implement step)
│   └── *.md           # One file per step
├── hooks/             # Custom validation scripts and prompts
│   └── *.md|*.sh      # Hook files referenced in job.yml
├── scripts/           # Reusable scripts and utilities created during job execution
│   └── *.sh|*.py      # Helper scripts referenced in step instructions
└── templates/         # Example file formats and templates
    └── *.md|*.yml     # Templates referenced in step instructions
```

## Learning History

### 2026-03-20: Milestone must reference press release

- **Source**: Keystone Desktop Context System milestone setup — milestone was created without linking to the press release that drove the scope
- **Issue**: The `setup_milestone` step only suggested generic source references ("From issue #N" or "From freehand scope notes"). When the pipeline is `press_release → milestone/setup`, reviewers had no way to find the working-backwards doc from the milestone page.
- **Resolution**: Updated `steps/setup_milestone.md` to require checking for a preceding press release and including its path in the milestone description. Added "Press Release Referenced" quality criterion to the `setup_milestone` review in `job.yml`.
- **Reference**: `steps/setup_milestone.md` step 3, `job.yml` setup_milestone reviews

### 2026-03-20: Embed press release, don't link to vault paths

- **Source**: Follow-up to previous learning — the milestone was created with a vault file path (`projects/keystone/press/.../press_release.mdx`) that doesn't exist in the public repo
- **Issue**: Vault file paths (obsidian notes) are private. Reviewers on GitHub/Forgejo cannot access them. Linking to a path that doesn't exist in the repo is useless.
- **Resolution**: Changed instruction from "include a link or path" to "embed the full press release text into the milestone description." This ensures the working-backwards doc is directly readable on the milestone page without needing access to the private vault.
- **Reference**: `steps/setup_milestone.md` step 3
- **Superseded by**: 2026-03-20 learning below (milestone descriptions are collapsed)

### 2026-03-20: Milestone description must be short; press release goes on the issue

- **Source**: User tested milestone #5 on GitHub and found the press release was hidden behind a "show more" collapse
- **Issue**: GitHub milestone descriptions are collapsed by default. Long content (like an embedded press release) is invisible unless the reviewer clicks to expand. This defeats the purpose of embedding it there.
- **Resolution**: Two changes: (1) Milestone description is now a short summary only (2-3 sentences). (2) The press release is embedded in the **issue body** under a `## Press Release` heading, where it's fully visible. Updated step 3 (milestone description) and step 5 (issue body composition).
- **Reference**: `steps/setup_milestone.md` steps 3 and 5, `job.yml` setup_milestone reviews

### 2026-03-20: Milestone description must include Why, not just What

- **Source**: Keystone Desktop Context System milestone #5 — description was "Unified context system for launching and switching between project work environments. User stories: #174"
- **Issue**: The description only stated what the milestone delivers (a feature label). It didn't explain _why_ — the problem being solved or the business motivation. Reviewers scanning the milestone list couldn't tell why this work was prioritized.
- **Resolution**: Updated `steps/setup_milestone.md` step 3 to require both "why" (problem/motivation) and "what" (deliverable) in the description. Added "Milestone Description Motivating" quality criterion. Example now leads with the problem: "Developers lose minutes every day switching between projects..."
- **Reference**: `steps/setup_milestone.md` step 3, `job.yml` setup_milestone reviews

### 2026-03-20: Single plan issue per milestone — no child issue decomposition

- **Source**: Milestones ncrmro/keystone#milestone/1 (Projctl Terminal Session Management — 19 issues) and ncrmro/keystone#milestone/2 (Keystone TUI — 19 issues)
- **Issue**: The `decompose_child_issues` step created 10+ granular child issues per milestone (19 in both observed cases). This caused issue sprawl that was difficult to track, diluted context across many issues, and made it harder to understand parallelism and blocking at a glance.
- **Resolution**: Removed the `decompose_child_issues` step entirely. The plan issue now serves as the single tracking issue per milestone. It includes a phased task checklist with conventional commit prefixes, parallelism documentation, and blocking dependencies. PRs reference the plan issue directly with `Part of #N`. Version bumped to 1.2.0.
- **Reference**: `job.yml` engineering_handoff workflow (step removed), `steps/create_plan_issue.md` (task checklist and context sections added)
- **Removed file**: `steps/decompose_child_issues.md` deleted (was orphaned)

### 2026-03-21: Issue count cap — 1 plan issue, 1-3 max with human approval

- **Source**: Follow-up to the 19-issue problem above — the human's policy is stricter than just "no child issues"
- **Issue**: Even after removing `decompose_child_issues`, the principle needed to be stated as a hard cap: one architecture/plan issue is the default. Everything follows from that single issue. Only genuinely large delineating features may warrant additional issues, but even then the cap is 1-3 and the agent MUST stop to ask the human before creating them.
- **Resolution**: Added "Human-in-the-loop for issue creation" principle to `job.yml` common_job_info. Added explicit "ISSUE COUNT CAP" block to `steps/create_plan_issue.md`. Cleaned up stale "issue decomposition" references in `steps/review_milestone.md`. Version bumped to 1.3.1.
- **Reference**: `job.yml` Key Engineering Principles, `steps/create_plan_issue.md` (cap block)

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
