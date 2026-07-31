# Document Review

## Objective

Conduct the crucible — where engineering interrogates the press release and internal FAQ, challenges assumptions, and negotiates scope down to a defensible MVP. This step produces a binding review decision that green-lights the agreed scope for spec writing. Required spikes are executed here before proceeding.

## Background

Before a project is greenlit, the PR/FAQ is reviewed by all stakeholders. Engineers are crucial participants. The role is to:
- Interrogate the document and challenge assumptions
- Ensure the idealized customer experience does not mask catastrophic technical debt
- Poke holes in the logic
- Negotiate scope down to a manageable Minimum Viable Product

This is not a rubber stamp — it is a structured negotiation between what the product promises and what engineering can deliver.

## Task

Present the internal FAQ verdict to the user, run any required spikes as nested workflows, negotiate scope if needed, and produce a binding review decision document.

### Process

1. **Present the verdict to the user**
   - Read `internal_faq.md` from the previous step
   - Present the summary verdict (`green` / `yellow` / `red`) and the list of required spikes
   - For a `green` verdict: proceed directly to scope confirmation
   - For `yellow`: run spikes first (see step 3)
   - For `red`: initiate scope negotiation (see step 4)

2. **Confirm or negotiate scope (green path)**
   - Present each story with its engineering assessment (cost, risk)
   - Ask the user: "Are there any stories you'd like to defer, simplify, or cut from MVP scope?"
   - Document the agreed scope as-is or with modifications

3. **Run required spikes (yellow path)**
   - For each spike listed in the internal FAQ:
     - Start a nested `spike/spike` workflow with the spike question as the goal
     - The spike produces findings that inform the scope decision
   - After all spikes complete, update the scope decision with spike findings
   - If spike findings change the verdict to `red`, escalate to scope negotiation

4. **Scope negotiation (red path or post-spike escalation)**
   - Walk through each story that is infeasible or too risky with the user
   - Use `AskUserQuestion` to present options:
     - **Cut**: remove the story from this milestone entirely
     - **Defer**: move to a future milestone as stretch goal
     - **Renegotiate**: simplify the story so it is feasible (document the constraint and revision)
   - Continue until all remaining in-scope stories are `green`

5. **Update the milestone issue**
   - Update the milestone issue body to reflect the negotiated scope:
     - Mark deferred stories clearly (e.g., move to a "Stretch Goals" section)
     - Add a note on renegotiated stories explaining the constraint and revision
   - GitHub: `gh issue edit {number} --repo {owner}/{repo} --body "$UPDATED_BODY"`
   - Forgejo: equivalent API call

6. **Write the review decision**

## Output Format

### review_decision.md

```markdown
# Review Decision: [Milestone Title]

## Decision date: YYYY-MM-DD

## Verdict: green | yellow | red → resolved

## Summary

[2-3 sentences on what was decided and why.]

## Approved MVP scope

### In scope

- US-001: [title] — [scope notes if any negotiation occurred]
- US-003: [title]

### Deferred (stretch goals — future milestone)

- US-005: [title] — [reason deferred]

### Renegotiated

- US-002: [title]
  - **Original**: [what the press release promised]
  - **Revised**: [what engineering can deliver]
  - **Constraint**: [the technical reason for the revision]

## Spikes completed

| Spike | Question | Finding | Decision |
|-------|----------|---------|----------|
| SP-001 | [question] | [finding] | [decision made based on finding] |

(or: "No spikes required.")

## Blocking assumptions resolved

| Assumption | Resolution |
|------------|------------|
| [assumption from internal FAQ] | [how resolved] |

## Green-lit for specs

The scope above is approved. The `create_specs` step may proceed with the in-scope and renegotiated stories listed above.
```

**Concrete example** (abbreviated):

```markdown
# Review Decision: Recipe Sharing Platform

## Decision date: 2026-03-28

## Verdict: yellow → resolved

## Summary

The spike confirmed pg_trgm is sufficient for search at current scale. All stories are in scope with
one simplification: image uploads are deferred to a follow-up milestone in favor of text-only recipes for MVP.

## Approved MVP scope

### In scope

- US-001: Add recipe creation form — text-only for MVP; image upload deferred
- US-002: Add recipe search — pg_trgm confirmed sufficient (see SP-001)
- US-003: Add recipe list view

### Deferred (stretch goals — future milestone)

- US-004: Image upload for recipes — requires S3 provisioning; deferred to v2

### Renegotiated

- US-001: Add recipe creation form
  - **Original**: Create recipe with title, ingredients, instructions, and photo
  - **Revised**: Create recipe with title, ingredients, and instructions (no photo)
  - **Constraint**: S3 infrastructure not yet provisioned; adding it to this milestone would add L effort

## Spikes completed

| Spike | Question | Finding | Decision |
|-------|----------|---------|----------|
| SP-001 | Does pg_trgm meet performance requirements for 100k recipes? | Spike showed < 50ms query time at 100k rows with GIN index | Proceed with pg_trgm; no Elasticsearch needed |

## Green-lit for specs

The scope above is approved. The `create_specs` step may proceed.
```

## Quality Criteria

- Internal FAQ verdict and required spikes were presented to the user before proceeding
- Every required spike was completed via `spike/spike` nested workflow before reaching a decision
- Every story is explicitly categorized: in scope, deferred, or renegotiated
- Renegotiated stories document the original promise, the revision, and the technical constraint
- The milestone issue body was updated to reflect the negotiated scope
- The document ends with an explicit "Green-lit for specs" statement

## Context

This step is the boundary between product intent and engineering commitment. Once the review decision is written and signed off, the scope is frozen for this milestone. The `create_specs` step will only write specs for stories that are in scope or renegotiated — deferred stories are excluded. The review decision document becomes the audit trail for why the final implementation differs from the original press release.
