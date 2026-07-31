# Create Functional Requirement Specs

## Objective

Write spec files grouped by system boundary, each containing behavioral requirements, data contracts, and edge case documentation. Commit specs to a branch, open a draft PR, and assign reviewers.

## Task

Read the scope analysis from the previous step, group stories by system boundary, and write spec files using RFC 2119 keywords. Each spec covers one system boundary and defines the behavioral requirements that implementation must satisfy.

### Process

1. **Read the scope analysis**
   - Load `scope_analysis.md` from the previous step
   - Extract the system boundaries and their associated stories
   - Note the repository slug and platform

2. **Navigate to the project repo**
   - Work in `.repos/{owner}/{repo}`
   - Ensure the repo is up to date: `git fetch origin`

3. **Create a branch and worktree**
   - Derive a milestone slug from the milestone title (e.g., "Recipe Sharing Platform" → `recipe-sharing-platform`)
   - Create a branch: `git branch docs/specs-{milestone-slug} origin/main`
   - Create a worktree: `git worktree add "$HOME/.worktrees/{owner}/{repo}/docs/specs-{milestone-slug}" docs/specs-{milestone-slug}`
   - Work in the worktree for all subsequent operations

4. **Create spec files**
   - Create a `specs/` directory in the repo root (if it doesn't exist)
   - For each system boundary identified in the scope analysis, create a spec file at `specs/{NNN}-{slug}.md`
   - Number specs sequentially: `001`, `002`, etc.
   - The slug should be a short kebab-case name derived from the boundary name

5. **Write each spec**
   - For each spec file, include:
     - Which user stories this spec covers
     - Affected modules and files
     - Data models or API contracts (request/response schemas, database columns)
     - Behavioral requirements using RFC 2119 keywords (MUST, SHOULD, MAY)
     - Edge cases and error handling
     - ASCII art mockups for UI components (if applicable)
   - Cross-reference other specs when boundaries interact

6. **Commit and push**
   - Stage all spec files: `git add specs/`
   - Commit: `git commit -m "docs(specs): add functional requirement specs for {milestone}"`
   - Push: `git push -u origin docs/specs-{milestone-slug}`

7. **Open a draft PR**

   **GitHub**:

   ```bash
   gh pr create --draft \
     --title "docs(specs): functional requirement specs for {milestone}" \
     --body "Specs for milestone #{milestone_issue_number}. Review before implementation begins."
   ```

   **Forgejo**:

   ```bash
   fj pr create "WIP: docs(specs): functional requirement specs for {milestone}" \
     --head docs/specs-{milestone-slug} --base main \
     --body "Specs for milestone #{milestone_issue_number}. Review before implementation begins." \
     -r {owner}/{repo}
   ```

8. **Assign reviewers**
   - Read `.agents/TEAM.md` for the correct platform usernames
   - Assign Luce (CPO) and Nicholas (human) as reviewers
   - GitHub: `gh pr edit {pr_number} --add-reviewer {username1},{username2}`
   - Forgejo: use the API to add reviewers

9. **Write the specs PR report**

## Output Format

### specs_pr_report.md

A report documenting the created spec files and the draft PR.

**Structure**:

```markdown
# Specs PR Report: [Milestone Title]

## Platform

- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]
- **Branch**: docs/specs-[milestone-slug]

## Draft PR

- **Number**: [PR number]
- **Title**: [PR title]
- **URL**: [PR URL]
- **Reviewers**: [assigned reviewers]

## Spec Files Created

| File                           | Boundary        | Stories Covered        |
| ------------------------------ | --------------- | ---------------------- |
| `specs/001-api-layer.md`       | API Layer       | US-001, US-002, US-003 |
| `specs/002-database-schema.md` | Database Schema | US-001, US-002, US-004 |
| `specs/003-auth-middleware.md` | Auth Middleware | US-003, US-005         |

## Spec Summary

### specs/001-api-layer.md

- **Boundary**: API Layer
- **Key requirements**: [1-2 sentence summary of MUST requirements]
- **Data contracts**: [list of API endpoints or models defined]

### specs/002-database-schema.md

...

## Notes

[Any issues encountered, cross-spec dependencies, or items needing attention]
```

### Spec File Format

Each spec file at `specs/{NNN}-{slug}.md` should follow this structure:

````markdown
# Spec: [Boundary Name]

## Stories Covered

- US-001: [title]
- US-003: [title]

## Affected Modules

- `src/routes/api.ts`
- `src/lib/db.ts`

## Data Models

### [Model Name]

| Field | Type   | Required | Notes         |
| ----- | ------ | -------- | ------------- |
| id    | UUID   | yes      | Primary key   |
| name  | string | yes      | Max 255 chars |

## API Contracts

### POST /api/recipes

**Request**:

```json
{
  "title": "string",
  "ingredients": ["string"]
}
```
````

**Response** (201):

```json
{
  "id": "uuid",
  "title": "string",
  "created_at": "iso8601"
}
```

**Errors**:

- 400: Missing required fields
- 401: Not authenticated

## Behavioral Requirements

1. The system MUST validate all required fields before persisting.
2. The system MUST return a 400 error with a descriptive message when validation fails.
3. The system SHOULD sanitize HTML in user-provided text fields.
4. The system MAY cache search results for up to 60 seconds.

## Edge Cases

- Empty string fields MUST be rejected (not treated as valid input)
- Concurrent updates to the same resource MUST use optimistic locking
- File uploads exceeding 10MB MUST be rejected with a 413 error

## UI Mockups (if applicable)

```
┌─────────────────────────────────┐
│  New Recipe                     │
├─────────────────────────────────┤
│  Title: [________________]      │
│                                 │
│  Ingredients:                   │
│  [________________] [+ Add]     │
│  • Flour                        │
│  • Sugar                        │
│                                 │
│  [Save Recipe]  [Cancel]        │
└─────────────────────────────────┘
```

```

## Quality Criteria

- Every system boundary identified in the scope analysis has a corresponding spec file
- Specs use RFC 2119 keywords (MUST, SHOULD, MAY) for behavioral requirements
- API contracts, data models, or interface definitions are specified where applicable
- A draft PR has been created with the spec files and assigned to reviewers
- Edge cases and error handling are documented in each spec
- Spec files are numbered sequentially and use kebab-case slugs

## Context

This step bridges analysis and implementation planning. Specs serve as the contract between product and engineering: they define what the system must do (behavioral requirements) without prescribing how (implementation details). The specs PR goes through review before implementation starts, ensuring alignment between Luce (product), Nicholas (human), and Drago (engineering). Subsequent steps reference these specs when creating the plan issue.
```
