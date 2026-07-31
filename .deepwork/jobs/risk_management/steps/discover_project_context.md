# Discover project context

## Objective

Resolve which project is under review and produce a grounded snapshot of its current state across engineering, product, growth, customer, and measurement functions.

## Task

Identify the project using the current repository as the default source of truth. If `project_hint` is provided, use it to resolve ambiguity, locate a matching project, or confirm that the current repo is the intended target.

Because this step has a string input, ask structured questions when the project identity is ambiguous or when multiple notes hubs or repos could match the hint. Do not guess between plausible projects without confirming.

Gather evidence from:
- the current repository and nearby docs
- issue, PR, and milestone history when available
- README files, changelogs, docs, websites, and release material
- project hubs or related notes under `~/notes` when available

Your output should describe the project and show where effort is currently concentrated. It should make clear what you know, what you inferred, and what remains unknown.

### Process

1. Resolve the project identity.
2. Inspect the repo for purpose, target user, recent delivery activity, and visible priorities.
3. Corroborate the picture using project hubs and related notes in `~/notes` when they exist.
4. Check for evidence of:
   - customer discovery, onboarding, support, or retention work
   - KPI definition and measurement discipline
   - marketing, launch narrative, social/media presence, and growth work
5. Record missing evidence explicitly instead of filling gaps with generic assumptions.
6. Save the snapshot to `risk_management/[resolved_project_slug]/project_context.md`.

## Output Format

### `risk_management/[resolved_project_slug]/project_context.md`

A markdown snapshot of the current project state with evidence and gaps.

**Structure**:
```markdown
# Project context: [Project Name]

## Project identity
- Name: [project name]
- Slug: [resolved_project_slug]
- Repo or source: [repo path, URL, or note hub]
- Resolution notes: [how ambiguity was resolved]

## Project promise
- Customer: [who it serves]
- Problem: [problem it claims to solve]
- Value proposition: [current promise]

## Current activity profile
- Recent engineering activity: [summary]
- Product activity: [summary]
- Marketing and narrative activity: [summary]
- Social or audience activity: [summary]
- Growth or distribution activity: [summary]
- KPI and measurement activity: [summary]
- Customer onboarding or support activity: [summary]

## Evidence
- Repo artifacts:
  - [file, issue, PR, commit, or doc]
- Notes hub artifacts:
  - [hub note, charter, milestone note, or linked note]
- Public-facing artifacts:
  - [website, release note, social profile, or press material]

## Missing context and unknowns
- [missing artifact or unanswered question]
- [missing artifact or unanswered question]

## Initial observations
- [where effort appears concentrated]
- [where effort appears absent or weak]
```

**Concrete example**:
```markdown
# Project context: Acme Launchpad

## Project identity
- Name: Acme Launchpad
- Slug: acme_launchpad
- Repo or source: ~/repos/acme/launchpad
- Resolution notes: Repo README and `~/notes/projects/acme-launchpad/README.md` matched on name and domain.

## Project promise
- Customer: Solo founders launching small SaaS products
- Problem: They struggle to ship onboarding and growth loops quickly.
- Value proposition: A hosted launch workflow with setup, onboarding, and analytics defaults.

## Current activity profile
- Recent engineering activity: Active weekly commits, backend migrations, and UI polish.
- Product activity: Some issue grooming, but no recent customer-facing specs.
- Marketing and narrative activity: No current launch page updates or release notes.
- Social or audience activity: No linked social channel or content cadence found.
- Growth or distribution activity: No referral, SEO, or partnership evidence found.
- KPI and measurement activity: No KPI doc, dashboard, or metric definitions found.
- Customer onboarding or support activity: Minimal onboarding docs, no lifecycle or retention instrumentation found.

## Evidence
- Repo artifacts:
  - README.md describing core product scope
  - 14 commits in the last 30 days focused on UI and backend features
- Notes hub artifacts:
  - `~/notes/projects/acme-launchpad/README.md`
  - `~/notes/projects/acme-launchpad/charter.md`
- Public-facing artifacts:
  - Landing page with stale copy and no clear CTA

## Missing context and unknowns
- No current KPI dashboard
- No recent customer interview notes
- No visible onboarding funnel metrics

## Initial observations
- Effort is concentrated in engineering delivery.
- Marketing, measurement, and onboarding appear materially underdeveloped.
```

## Quality Criteria

- The project identity is explicit, including how ambiguity was resolved.
- The snapshot uses repo evidence and notes-hub evidence when available.
- All major functions are covered: engineering, product, marketing, social/media, growth, KPI/measurement, and customer/onboarding.
- Claims are tied to artifacts or clearly labeled as unknowns.
- The output gives the next step enough context to assess risk without redoing discovery.

## Context

This workflow exists to catch projects that are shipping code without building the rest of the system needed for success. If this first step is sloppy, every later risk judgment will drift into generic advice. The goal is a grounded picture of where the project is actually investing effort today.
