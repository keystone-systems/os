# Reality Check

## Objective

Compare the project's current state against its charter goals and KPIs, score progress at each horizon, check for business-thread drift, and produce a verdict (accelerate/continue/pivot/pause/archive) with a confidence score (high/medium/low).

## Task

Read the state assessment and charter, then produce a dated success review report that gives the human an honest, evidence-based picture of where the project stands and what should happen next.

### Process

1. **Read inputs**
   - Load `state_assessment.md` for current project data
   - Load the charter (`projects/{slug}/charter.md`) for goals and KPIs

2. **Score each KPI**
   - For each KPI in the charter, compare the current value to the target
   - Calculate progress as a percentage or directional indicator
   - Flag KPIs that are declining, stagnant, or significantly off-target
   - If a KPI has no current data (pre-launch), note it as "not yet measurable" rather than scoring

3. **Assess each goal horizon**
   - For each of the 5 horizons (1mo/6mo/1yr/5yr/10yr):
     - Check each success criterion against current state
     - Rate as: **on-track**, **at-risk**, or **off-track**
     - Provide evidence for the rating (specific data points)
   - For longer horizons (5yr/10yr), assess whether the trajectory is aligned even if the goal is far out

4. **Check the business thread**
   - Using the activity balance from the state assessment, evaluate:
     - Is the project making progress on business goals, or only engineering?
     - Are customer-facing milestones moving, or just internal infrastructure?
     - Has there been business activity (user research, marketing, customer conversations) in the last 30 days?
   - Flag if the project appears to be in "heads-down engineering" mode without business validation

5. **Determine the verdict**
   - Based on KPI scores, goal progress, and business thread assessment, recommend one of:
     - **Accelerate**: KPIs trending up, goals on-track, strong product-market signals — invest more
     - **Continue**: Steady progress, no red flags — maintain current pace and direction
     - **Pivot**: Some goals off-track but the problem space is validated — change approach, not mission
     - **Pause**: Blocked by external factors or resource constraints — park and revisit later
     - **Archive**: Mission no longer relevant, goals consistently off-track, no path to viability — close out gracefully

6. **Assess confidence**
   - Rate confidence as **high**, **medium**, or **low** based on:
     - **High**: Multiple data points support the verdict, clear trend, no ambiguity
     - **Medium**: Some data supports the verdict but gaps exist or trends are mixed
     - **Low**: Insufficient data, conflicting signals, or the situation is genuinely unclear
   - Explain what would increase confidence (e.g., "3 more months of KPI data" or "customer interviews needed")

7. **Write the success review report**
   - Save to `projects/{slug}/reports/success_review_YYYY-MM.md` using the current month
   - Create the `reports/` directory if it doesn't exist

## Output Format

### projects/{slug}/reports/success_review_YYYY-MM.md

```markdown
# Success Review: [Project Name] — [Month YYYY]

**Review Date**: [YYYY-MM-DD]
**Charter Version**: [last updated date from charter]
**Previous Verdict**: [from last review, or "First review"]

## KPI Scorecard

| KPI      | Current | Target   | Progress         | Trend                              |
| -------- | ------- | -------- | ---------------- | ---------------------------------- |
| [metric] | [value] | [target] | [% or indicator] | [improving / stagnant / declining] |

### KPI Analysis

[2-3 sentences on overall KPI health. Flag any that are significantly off-target.]

## Goal Progress

### 1 Month — [on-track / at-risk / off-track]

- [criterion 1]: [status with evidence]
- [criterion 2]: [status with evidence]

### 6 Months — [on-track / at-risk / off-track]

- [criterion 1]: [status with evidence]
- [criterion 2]: [status with evidence]

### 1 Year — [on-track / at-risk / off-track]

- [criterion 1]: [status with evidence]
- [criterion 2]: [status with evidence]

### 5 Years — [on-track / at-risk / off-track]

[Trajectory assessment — is current direction aligned?]

### 10 Years — [on-track / at-risk / off-track]

[Vision alignment assessment]

## Business Thread Check

**Activity Balance**: [engineering-skewed / balanced / business-skewed]

[Assessment of whether business goals are getting attention alongside engineering.
Flag specific concerns if the human appears to be losing the business thread.]

## Verdict

**Recommendation**: [accelerate / continue / pivot / pause / archive]
**Confidence**: [high / medium / low]

### Reasoning

[3-5 sentences explaining why this verdict was reached, citing specific KPI data,
goal progress, and business thread observations.]

### What Would Change This Verdict

[What data or events would shift the recommendation in either direction?
e.g., "If MRR reaches $X in the next 2 months, upgrade to accelerate.
If no customer signups in 60 days, consider pause."]
```

## Quality Criteria

- Each KPI from the charter is scored with current vs target values
- Each goal across all 5 horizons has an on-track/at-risk/off-track assessment with evidence
- A clear verdict is stated with confidence level
- The review flags if activity is skewed toward engineering at the expense of business goals
- The verdict is supported by specific data points, not generic reasoning
- The "What Would Change This Verdict" section gives the human actionable decision criteria

## Context

This is the core accountability step. The review must be honest — its value comes from surfacing uncomfortable truths, not from confirming what the human wants to hear. If the project is drifting, say so clearly. If KPIs aren't being measured, that itself is a finding worth flagging. The goal is to help the human make informed decisions about where to invest their time and energy.
