## Product-Engineering Handoff

## Purpose

This convention defines how product scope flows from press release through milestone
setup (product phase) to engineering planning (engineering phase), producing trackable
work via GitHub/Forgejo milestones and issues.

## Pipeline Overview

The handoff is a two-phase process with distinct ownership:

1. **Product phase** (`project_milestone_setup/setup`) — CPO (Luce) creates a milestone
   and consolidated user stories issue from a press release or freehand notes.
2. **Engineering phase** (`project_milestone_engineering_handoff/plan`) — CTO (Drago)
   responds with specs, a plan issue, and decomposed child issues.

The product phase MUST complete before the engineering phase begins. The milestone and
user stories issue MUST exist before engineering planning starts.

## Platform

1. Milestones and issues MUST be created on the project's primary platform (GitHub or Forgejo).
2. Check the project's `README.yaml` `repos[].platform` field to determine which platform to use.
3. For GitHub: use `gh` CLI. For Forgejo: use `fj` CLI for issues, `tea api`/`curl` for milestones and labels per `tool.forgejo` convention.
4. Agent usernames differ by platform — read the correct column from `.agents/TEAM.md`.

## Product Phase: Milestone Setup

5. Each product initiative MUST produce exactly one milestone in the project's repository.
6. The milestone title MUST be derived from the press release headline, product name, or scope description.
7. All user stories MUST be created as a **single consolidated issue** within the milestone.
8. The consolidated issue title MUST follow the pattern: "[Milestone Title]: User Stories for Review".
9. The issue body MUST contain all stories grouped by type (engineering / product), each with:
   - User story statement: "As a [persona], I want [action], so that [benefit]"
   - Acceptance criteria as a markdown checklist
   - "Derived from" line referencing the source material
   - Priority tag (high / medium / low)
10. The consolidated issue MUST be assigned to the business agent (Luce).
11. The human MUST review and approve the consolidated issue before engineering planning begins.

## Engineering Phase: Specs, Plan, and Decomposition

12. Engineering planning MUST NOT begin until the milestone and user stories issue exist.
13. The engineering phase produces three artifacts:
    - **Spec files** in `docs/specs/REQ-{NNN}-{slug}.md` with behavioral requirements (RFC 2119: MUST/SHOULD/MAY)
    - **Plan issue** — master implementation plan referencing specs, with happy paths, test expectations, design mockups, and demo descriptions
    - **Child issues** — small, non-blocking issues decomposed from the plan, each mapping to a single PR
14. Specs MUST be committed to a branch and opened as a draft PR for review before implementation.
15. Child issues MUST use type separation: `feat:` for user story work, `chore:`/`refactor:` for infrastructure, `test:` for test suites.
16. Each child issue MUST reference the plan issue with "Part of #N".
17. Child issues MUST be scoped for small PRs (2-3 files max) and designed to be non-blocking.
18. Feature-flaggable features SHOULD use feature flags for continuous deployment.
19. No stretch goals MUST be included in milestone scope; stretch goals are noted as separate future work.

## Labels

20. The consolidated issue MUST have the `product` label.
21. The repo MUST have `product` and `engineering` labels available.
22. The plan issue MUST have `engineering` and `plan` labels.

## Traceability

23. Every story MUST trace back to the source material (press release or freehand notes).
24. Every child issue MUST trace back to the plan issue.
25. Every plan issue MUST reference the specs PR and the milestone issue.

## Issue Work Protocol

26. When a PR resolving a milestone issue is merged, the closing agent MUST post a structured `## Demo Artifacts` comment on the issue containing screenshot URLs, video links, and/or preview links from the PR's Demo section (see `process.pull-request` convention, rules 5-9). See `process.vcs-context-continuity` for evidence requirements during implementation.
27. Issues producing visible output MUST NOT be closed until the demo artifact comment is posted.
28. Agents MUST reference the PR number (e.g., `PR #42`) in the artifact comment so reviewers can trace back to the full Demo section.
29. For issues with no visible output (e.g., infrastructure, refactoring), the artifact comment MAY be omitted but the closing PR MUST still have a Demo section per `process.pull-request` convention.

## Milestone Completion

30. A milestone is complete when all its issues are closed with artifact comments where applicable.
31. Before closing a milestone, the business agent MUST verify that all demo artifacts are collected.
32. The business agent closes the milestone after verifying artifacts are present.

## Press Release Publication

33. The press release is published (committed to the project's blog directory) when the milestone is closed.
34. The milestone closing does NOT require updating the press release content — the press release stands as written at handoff time.
