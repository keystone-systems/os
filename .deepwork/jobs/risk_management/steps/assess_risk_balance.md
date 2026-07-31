# Assess risk balance

## Objective

Turn the discovered project context into a defensible risk register that identifies neglected functions, misaligned priorities, and the most urgent cross-functional bottlenecks.

## Task

Read `project_context` and assess whether the project's current priorities fit its stage, goals, and evidence base.

This step must evaluate both engineering and non-engineering functions. Do not default to startup boilerplate. The register should explain why the current priority mix is acceptable or incorrect using concrete evidence from the project context.

### Process

1. Read the full project snapshot before forming conclusions.
2. Identify the most important risks across:
   - execution and delivery
   - market and positioning
   - customer discovery and onboarding
   - measurement and KPIs
   - growth, distribution, and audience-building
   - stakeholder visibility and operating discipline
3. Explicitly test whether the project is over-indexing on engineering while under-investing elsewhere.
4. For each material risk, record severity, urgency, confidence, evidence, and the priority correction implied by the risk.
5. Distinguish between proven risks and evidence gaps.
6. Save the register to `risk_management/[resolved_project_slug]/risk_register.md`.

## Output Format

### `risk_management/[resolved_project_slug]/risk_register.md`

A structured markdown risk register with evidence and priority implications.

**Structure**:
```markdown
# Risk register: [Project Name]

## Executive summary
- Overall posture: [healthy | imbalanced | high risk]
- Core imbalance: [one-sentence summary]
- Most urgent correction: [one sentence]

## Risk table
| Risk | Category | Severity | Urgency | Confidence | Evidence | Priority correction |
|------|----------|----------|---------|------------|----------|---------------------|
| [risk title] | [category] | [high/medium/low] | [now/soon/later] | [high/medium/low] | [artifact-based summary] | [what should change] |

## Detailed analysis

### [Risk title]
- Category: [category]
- Severity: [high/medium/low]
- Urgency: [now/soon/later]
- Confidence: [high/medium/low]
- Evidence:
  - [artifact or finding]
  - [artifact or finding]
- Why this matters:
  - [impact on project success]
- Priority correction:
  - [what should be deprioritized]
  - [what should be elevated]
- Unknowns:
  - [remaining evidence gap]

## Neglected functions
- [function]: [why it is underdeveloped and what risk that creates]
- [function]: [why it is underdeveloped and what risk that creates]

## Balanced areas
- [function that appears appropriately prioritized]
```

**Concrete example**:
```markdown
# Risk register: Acme Launchpad

## Executive summary
- Overall posture: imbalanced
- Core imbalance: Engineering velocity is strong, but the business system around activation and growth is weak.
- Most urgent correction: Define activation KPIs and validate onboarding with real users before shipping more secondary features.

## Risk table
| Risk | Category | Severity | Urgency | Confidence | Evidence | Priority correction |
|------|----------|----------|---------|------------|----------|---------------------|
| Shipping without activation metrics | KPI/measurement | high | now | high | No KPI doc, no funnel dashboard, no metric definitions in repo or notes | Pause non-critical feature work and define activation metrics first |
| Weak onboarding loop | Customer/onboarding | high | now | medium | Minimal onboarding docs, no onboarding instrumentation, no customer notes | Elevate onboarding work above UI polish |
| No growth narrative | Marketing/growth | medium | soon | medium | Stale landing page, no release notes, no social presence | Assign messaging and launch narrative work in the next phase |
```

## Quality Criteria

- The register is project-specific and evidence-backed.
- It explicitly evaluates engineering against missing business functions.
- Each material risk includes severity, urgency, confidence, evidence, and a priority correction.
- Unknowns are separated from proven risks.
- The output makes it obvious why stakeholders should change or retain current priorities.

## Context

This is the diagnostic core of the workflow. The next step will tell stakeholders what to do, so this step must explain what is risky, what is merely incomplete, and what imbalance is most likely to stall the project if left uncorrected.
