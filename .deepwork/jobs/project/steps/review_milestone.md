# Review Milestone and Analyze Scope

## Objective

Fetch the milestone's consolidated user stories issue, clone/navigate to the project repo, and produce a scope analysis that maps every user story to affected codebase files, identifies shared system boundaries, and flags gaps or ambiguities.

## Task

Read the milestone issue from the platform, explore the project's codebase, and build a systems map showing how the proposed user stories interact with existing code. This analysis informs the internal FAQ and spec creation in subsequent steps.

### Process

1. **Gather inputs**
   - Ask structured questions to collect the `project_repo` (repo slug and platform) and `milestone_issue_number` if not already provided
   - Determine the platform (GitHub or Forgejo) from the input or the project's `README.yaml`

2. **Fetch the milestone issue**

   **GitHub**:

   ```bash
   gh issue view {number} --repo {owner}/{repo} --json title,body,labels,milestone,assignees
   ```

   **Forgejo**:

   ```bash
   fj issue view {number} -r {owner}/{repo}
   ```

   - Capture the full issue body with all user stories
   - Note the milestone title, labels, and assignees

3. **Clone or navigate to the project repo**
   - Check if the repo exists at `.repos/{owner}/{repo}`
   - If not, clone it per the cloning convention:
     - GitHub: `gh repo clone {owner}/{repo} .repos/{owner}/{repo}`
     - Forgejo: `git clone ssh://forgejo@git.ncrmro.com:2222/{owner}/{repo}.git .repos/{owner}/{repo}`
   - If it exists, `git fetch origin && git pull` to ensure it's up to date

4. **Analyze each user story against the codebase**
   - For each user story in the issue body:
     - Identify which files, modules, or directories are affected
     - Classify the story type: `feat` (new feature), `chore` (infrastructure), `test` (test suite), `refactor` (restructuring)
     - Note the estimated complexity (small / medium / large)
   - Use `find`, `grep`, and file reading to ground the analysis in actual code

5. **Build the systems map**
   - Group stories by the system/module they touch
   - Identify shared boundaries where multiple stories affect the same code
   - Note any shared infrastructure needs (database migrations, API routes, shared components)

6. **Identify prerequisites and gaps**
   - List implied prerequisites not explicitly stated in the user stories (e.g., database setup, auth middleware, CI config)
   - Flag ambiguous stories that need CPO clarification before implementation
   - Note any stories that seem too large and should be split

7. **Write the scope analysis**

## Output Format

### scope_analysis.md

A structured document mapping user stories to codebase systems with boundary and gap analysis.

**Structure**:

```markdown
# Scope Analysis: [Milestone Title]

## Source

- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]
- **Milestone Issue**: #[number] — [issue title]
- **Milestone**: [milestone title]
- **Analysis Date**: [YYYY-MM-DD]

## Story-to-System Map

### US-001: [Story title]

- **Type**: feat | chore | test | refactor
- **Affected files/modules**:
  - `src/routes/search.ts` — new route handler
  - `src/lib/db.ts` — new query method
- **Complexity**: small | medium | large
- **Notes**: [any implementation notes]

### US-002: [Story title]

...

## System Boundaries

Boundaries where multiple stories intersect or share infrastructure.

### [Boundary Name] (e.g., "API Layer", "Database Schema", "Auth Middleware")

- **Stories involved**: US-001, US-003, US-005
- **Shared concern**: [what they share — e.g., "All need new API routes with auth"]
- **Key files**: [files at this boundary]
- **Coordination notes**: [ordering or dependency implications]

### [Another Boundary]

...

## Implied Prerequisites

Items not listed as user stories but required for implementation.

| #   | Prerequisite                       | Required By    | Type  | Notes     |
| --- | ---------------------------------- | -------------- | ----- | --------- |
| 1   | [e.g., Database migration setup]   | US-001, US-003 | chore | [details] |
| 2   | [e.g., CI pipeline for new module] | All stories    | chore | [details] |

## Ambiguities and Clarification Needed

Items requiring CPO clarification before implementation.

| #   | Story  | Question                                              | Impact                        |
| --- | ------ | ----------------------------------------------------- | ----------------------------- |
| 1   | US-004 | [What does "real-time" mean — websockets or polling?] | [Affects architecture choice] |

## Stories Recommended for Splitting

| Story  | Reason                                         | Suggested Split                        |
| ------ | ---------------------------------------------- | -------------------------------------- |
| US-007 | [Too large — covers both backend and frontend] | [Split into US-007a: API, US-007b: UI] |
```

**Concrete example** (abbreviated):

```markdown
# Scope Analysis: Recipe Sharing Platform

## Source

- **Platform**: github
- **Repository**: ncrmro/recipes
- **Milestone Issue**: #15 — Recipe Sharing Platform: User Stories for Review
- **Milestone**: Recipe Sharing Platform
- **Analysis Date**: 2026-03-18

## Story-to-System Map

### US-001: Add recipe creation form

- **Type**: feat
- **Affected files/modules**:
  - `src/app/recipes/new/page.tsx` — new page component
  - `src/components/RecipeForm.tsx` — new form component
  - `src/lib/api/recipes.ts` — new API client methods
  - `src/app/api/recipes/route.ts` — new API route
- **Complexity**: medium
- **Notes**: Requires image upload support for recipe photos

### US-002: Add recipe search

- **Type**: feat
- **Affected files/modules**:
  - `src/app/recipes/page.tsx` — add search UI
  - `src/app/api/recipes/search/route.ts` — new search endpoint
  - `src/lib/db/recipes.ts` — new search query
- **Complexity**: medium
- **Notes**: Full-text search vs. simple LIKE query needs decision

## System Boundaries

### API Layer

- **Stories involved**: US-001, US-002, US-003
- **Shared concern**: All need new API routes under `/api/recipes/`
- **Key files**: `src/app/api/recipes/`
- **Coordination notes**: Define shared response types before individual routes

### Database Schema

- **Stories involved**: US-001, US-002, US-004
- **Shared concern**: All require the `recipes` table and related models
- **Key files**: `prisma/schema.prisma`, `src/lib/db/recipes.ts`
- **Coordination notes**: Schema migration must land before any feature work

## Implied Prerequisites

| #   | Prerequisite                                | Required By            | Type  | Notes                                      |
| --- | ------------------------------------------- | ---------------------- | ----- | ------------------------------------------ |
| 1   | Prisma schema + migration for recipes table | US-001, US-002, US-004 | chore | Must define schema before feature branches |
| 2   | Image upload infrastructure (S3 or local)   | US-001                 | chore | Recipe photos need storage                 |

## Ambiguities and Clarification Needed

| #   | Story  | Question                                                 | Impact                                         |
| --- | ------ | -------------------------------------------------------- | ---------------------------------------------- |
| 1   | US-002 | Does "search" mean full-text search or simple filtering? | Determines if we need pg_trgm or Elasticsearch |
```

## Quality Criteria

- Every user story from the milestone issue is analyzed and mapped to affected codebase files or modules
- References actual files and directories in the project repository, not hypothetical or generic paths
- Shared system boundaries across stories are identified and documented
- Implied prerequisites not explicitly listed in the user stories are identified and flagged
- Ambiguous stories needing clarification are flagged with specific questions

## Context

This is the first step in the engineering handoff workflow. The scope analysis drives the internal FAQ, specs, and plan issue. A thorough analysis prevents rework later — missing a shared boundary means specs won't cover it, and missing a prerequisite means blocked PRs during implementation.
