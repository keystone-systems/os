# Write stakeholder brief

## Objective

Convert the risk register into a stakeholder-facing reprioritization brief that explains what should change now, what can wait, and what evidence needs to be gathered next.

## Task

Read `risk_register` and write a concise, decision-oriented brief for project stakeholders.

The brief should change priorities in response to the diagnosed risks. It should not merely restate the register. It also must remain diagnosis-only: recommend follow-up work, but do not pretend the workflow already created tasks, changed milestones, or executed the plan.

### Process

1. Read the executive summary and detailed risks.
2. Identify the few changes in priority that matter most.
3. Translate technical and business risks into stakeholder language.
4. Separate recommendations into immediate, near-term, and later work.
5. Call out work that should slow down or pause if it is crowding out more urgent gaps.
6. Recommend what evidence should be gathered next to reduce uncertainty.
7. Save the brief to `risk_management/[resolved_project_slug]/stakeholder_brief.md`.

## Output Format

### `risk_management/[resolved_project_slug]/stakeholder_brief.md`

A markdown brief for stakeholders with explicit reprioritization.

**Structure**:
```markdown
# Stakeholder brief: [Project Name]

## Bottom line
[2-4 sentences summarizing the current imbalance and what must change]

## What should change now
- Stop or slow:
  - [work that should pause or slow]
- Prioritize immediately:
  - [highest-priority corrective action]
  - [highest-priority corrective action]

## Near-term priorities
- [action for the next phase]
- [action for the next phase]

## Later priorities
- [important but not immediate action]

## Why this reprioritization is necessary
- [risk-to-priority explanation]
- [risk-to-priority explanation]

## Evidence to gather next
- [metric, interview, artifact, or validation step]
- [metric, interview, artifact, or validation step]

## Functional recommendations
### Product and engineering
- [recommendation]

### Marketing and growth
- [recommendation]

### Customer and operations
- [recommendation]
```

**Concrete example**:
```markdown
# Stakeholder brief: Acme Launchpad

## Bottom line
The project is not blocked by engineering throughput. It is blocked by a missing activation model, weak onboarding evidence, and no clear growth narrative. Stakeholders should redirect the next cycle toward measurement, onboarding validation, and positioning before funding more secondary feature work.

## What should change now
- Stop or slow:
  - New UI polish work that does not improve activation or onboarding
- Prioritize immediately:
  - Define activation KPIs and instrument the onboarding funnel
  - Run customer onboarding reviews with at least five target users

## Near-term priorities
- Refresh landing-page messaging around the actual target customer
- Publish a launch narrative and basic release cadence

## Later priorities
- Resume secondary feature work after activation metrics and onboarding evidence improve

## Why this reprioritization is necessary
- More feature work will not reduce the highest current risks.
- The project lacks enough customer and measurement feedback to know whether current engineering work is compounding value.

## Evidence to gather next
- Baseline activation and retention metrics
- Interview notes from onboarding sessions

## Functional recommendations
### Product and engineering
- Shift effort from feature breadth to activation and onboarding instrumentation.

### Marketing and growth
- Define a simple positioning statement and publish a consistent outward narrative.

### Customer and operations
- Build a lightweight onboarding review process and capture recurring friction.
```

## Quality Criteria

- The brief is written for stakeholders rather than only for engineers.
- It clearly changes priorities in response to the risk register.
- Immediate, near-term, and later work are separated.
- Non-engineering recommendations appear where the diagnosis requires them.
- The brief remains advisory and does not imply that follow-up work already happened.

## Context

The value of this workflow is not just in naming risks. It is in helping stakeholders reallocate attention and budget toward the neglected functions most likely to determine whether the project succeeds. This brief is the decision artifact they should use for that conversation.
