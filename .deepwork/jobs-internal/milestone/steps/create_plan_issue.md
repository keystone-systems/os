# Create Implementation Plan Issue

## Objective

Create a **single** plan issue on the milestone that serves as the sole tracking issue for all implementation work. This issue includes happy paths, test expectations, design mockups, demo artifacts, **and a phased task checklist documenting parallelism and blocking dependencies**. PRs are opened directly against this issue — no child issues are created.

## Task

Read the scope analysis and specs PR report from prior steps, then compose and create one comprehensive plan issue on the project's platform. This issue becomes the single reference point for all implementation work on the milestone. Multiple PRs will reference this issue via `Part of #N` or `Closes #N`.

**IMPORTANT: Do NOT create child issues.** All work is tracked in this issue's task checklist.

**ISSUE COUNT CAP**: Create exactly ONE plan issue. If you identify a genuinely distinct feature that warrants its own issue (large delineating feature, not just a subtask), you MUST stop and ask the human for approval before creating it. The absolute maximum is 1-3 additional issues, and each requires explicit human sign-off. Issue bloat (10+ issues per milestone) has been a recurring problem — err on fewer issues.

### Process

1. **Read prior step outputs**
   - Load `scope_analysis.md` — for the story-to-system map and prerequisites
   - Load `specs_pr_report.md` — for the specs PR number/URL and spec file details
   - Extract the milestone title, issue number, and platform

2. **Compose the plan issue body**
   For each user story from the milestone issue, include:
   - **Happy path requirements** — the expected user flow when everything works correctly
   - **Red/green test expectations** — what test should fail before implementation (red) and pass after (green). Be specific about the assertion, not just "it should work."
   - **ASCII art design mockups** — for any new UI components, page layouts, or visual elements. Show the layout, key elements, and user interaction points.
   - **Expected demo artifacts** — describe what screenshots, videos, or preview URLs should be produced when this story is complete. These are used for the press release and human review.

   Also include:
   - **Implementation order** — which stories can be parallelized and which have dependencies
   - **Feature flag requirements** — which stories need feature flags for safe deployment
   - References to the specs PR and the original milestone issue

3. **Compose the phased task checklist**

   Break the work into tasks grouped by phase. Each task should map to a single small PR (2-3 files max). Use conventional commit prefixes for task names. Document parallelism and blocking:

   ```markdown
   ## Tasks

   ### Phase 1: Infrastructure (parallel — no dependencies)

   - [ ] chore: add recipes database migration
   - [ ] chore: set up image upload infrastructure

   ### Phase 2: Features (parallel — depends on Phase 1)

   - [ ] feat: add recipe creation form
   - [ ] feat: add recipe search

   ### Phase 3: Integration Tests (depends on Phase 2)

   - [ ] test: add recipe API integration tests

   ### Future Work (out of milestone scope)

   - Recipe ratings and reviews
   - Recipe import from external sites
   ```

   Design for non-blocking PRs:
   - Tasks within the same phase should be independently implementable
   - Infrastructure tasks (`chore:`) come first and unblock feature work
   - Feature tasks should depend on infrastructure, not on each other
   - Use feature flags to avoid blocking on deployment order

4. **Create the plan issue**

   **GitHub**:

   ```bash
   gh issue create --repo {owner}/{repo} \
     --title "Plan: {milestone title}" \
     --body "$BODY" \
     --label "engineering" --label "plan" \
     --milestone "{milestone title}" \
     --assignee {drago_username}
   ```

   **Forgejo**:

   ```bash
   fj issue create "Plan: {milestone title}" \
     --body "$BODY" \
     --label "engineering" --label "plan" \
     -r {owner}/{repo}
   ```

   Then link to milestone and assign via API.
   - Ensure `engineering` and `plan` labels exist (create if missing)
   - Assign to Drago (CTO) — read username from `.agents/TEAM.md`
   - Link to the milestone

5. **Write the plan issue report**

## Output Format

### plan_issue_report.md

A report documenting the created plan issue.

**Structure**:

```markdown
# Plan Issue Report: [Milestone Title]

## Platform

- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]

## Plan Issue

- **Number**: #[number]
- **Title**: Plan: [milestone title]
- **URL**: [issue URL]
- **Milestone**: [milestone title]
- **Assignee**: [Drago's username]
- **Labels**: engineering, plan

## References

- **Milestone Issue**: #[milestone_issue_number]
- **Specs PR**: #[specs_pr_number] ([URL])

## Stories Included

| Story           | Happy Path | Tests | Mockup | Demo |
| --------------- | ---------- | ----- | ------ | ---- |
| US-001: [title] | yes        | yes   | yes/no | yes  |
| US-002: [title] | yes        | yes   | yes/no | yes  |

...

## Implementation Order

[Summary of the phasing — what can be parallel, what must be sequential]

## Feature Flags

[List of stories requiring feature flags, or "None"]

## Notes

[Any issues or items needing attention]
```

### Plan Issue Body Format

The issue body created on the platform should follow this structure:

```markdown
# Plan: [Milestone Title]

**Milestone Issue**: #[milestone_issue_number]
**Specs PR**: #[specs_pr_number]

## Stories

### US-001: [Story title]

**Happy Path**:

1. User navigates to /recipes/new
2. User fills in title, ingredients, and instructions
3. User clicks "Save Recipe"
4. System creates recipe and redirects to /recipes/{id}
5. Recipe appears in the user's recipe list

**Test Expectations**:

- RED: `POST /api/recipes` with valid payload returns 404 (route doesn't exist yet)
- GREEN: `POST /api/recipes` with valid payload returns 201 with recipe ID
- RED: Recipe form component renders without crashing (component doesn't exist yet)
- GREEN: Recipe form component renders with title, ingredients, and save button

**Design Mockup**:
```

┌─────────────────────────────────┐
│ New Recipe │
├─────────────────────────────────┤
│ Title: [________________] │
│ │
│ Ingredients: │
│ [________________] [+ Add] │
│ • Flour │
│ • Sugar │
│ │
│ Instructions: │
│ [ ] │
│ [ ] │
│ │
│ [Save Recipe] [Cancel] │
└─────────────────────────────────┘

```

**Demo Artifacts**:
- Screenshot: Recipe creation form with sample data filled in
- Screenshot: Successfully created recipe detail page
- Video (optional): Full create flow from empty form to saved recipe

---

### US-002: [Story title]
...

## Tasks

### Phase 1: Infrastructure (parallel — no dependencies)
- [ ] chore: add recipes database migration
- [ ] chore: set up image upload infrastructure

### Phase 2: Features (parallel — depends on Phase 1)
- [ ] feat: add recipe creation form (US-001)
- [ ] feat: add recipe search (US-002)
- [ ] feat: add recipe sharing (US-003) — flag: `ENABLE_RECIPE_SHARING`

### Phase 3: Integration Tests (depends on Phase 2)
- [ ] test: add recipe API integration tests

### Future Work (out of milestone scope)
- Recipe ratings and reviews
- Recipe import from external sites

## Feature Flags

| Story | Flag Name | Reason |
|-------|-----------|--------|
| US-003 | `ENABLE_RECIPE_SHARING` | Social features need gradual rollout |
```

> **Note to implementers**: Each task above maps to one PR. Reference this issue in your PR with `Part of #N`. Check off tasks as PRs merge.

## Quality Criteria

- **No child issues created** — all work tracked in this single plan issue's task checklist
- Every user story from the milestone issue appears in the plan with happy path requirements
- A phased task checklist documents all work items with conventional commit prefixes
- Parallelism and blocking dependencies are clearly documented per phase
- Each story includes red/green test expectations describing what fails before and passes after implementation
- ASCII art mockups are included for new UI components or layouts
- Expected demo artifacts are described for each story (screenshots, videos, preview URLs)
- The specs PR is referenced in the plan issue body
- The plan issue is linked to the milestone

## Context

This step creates the engineering blueprint for the milestone. The plan issue serves as the **single tracking issue** for all implementation work — no child issues are created. Instead, the plan issue contains a phased task checklist where each task maps to one PR. This avoids issue sprawl (10+ granular issues per milestone) and keeps all context, parallelism notes, and blocking info in one place. PRs reference the plan issue with `Part of #N`. The test expectations follow TDD principles — defining what should fail and pass before writing code. The demo artifacts ensure that every story has a verifiable outcome visible to stakeholders.
