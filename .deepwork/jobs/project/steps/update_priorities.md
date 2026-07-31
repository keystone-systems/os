# Update Priorities

## Objective

Translate the success review verdict into concrete, actionable next steps: which workflows to run, which milestones to create or close, and whether the project's priority in PROJECTS.yaml should change.

## Task

Read the success review and charter, then produce a prioritized list of recommendations that the human can act on immediately or delegate to agents.

### Process

1. **Read inputs**
   - Load the success review report from the reality_check step
   - Load the charter for context on goals and KPIs
   - Note the verdict and confidence level

2. **Map verdict to action patterns**

   Each verdict implies a different set of actions:
   - **Accelerate**:
     - Recommend increasing investment: more milestones, faster cadence
     - Suggest which goals to push harder on
     - Recommend `project/press_release` if there's a shippable feature worth announcing
     - Consider raising priority in PROJECTS.yaml

   - **Continue**:
     - Recommend maintaining current pace
     - Identify the next milestone to set up (`milestone/setup`)
     - Flag any at-risk goals that need attention before they go off-track
     - Priority stays the same in PROJECTS.yaml

   - **Pivot**:
     - Identify what to keep (validated problem space) vs what to change (approach, target segment, solution)
     - Recommend a new `project/press_release` to reframe the value proposition
     - Suggest updating the charter with revised goals
     - May need a new onboard cycle for the pivoted direction

   - **Pause**:
     - Recommend closing active milestones or moving issues to backlog
     - Specify what would trigger resumption (external event, resource availability, market change)
     - Lower priority in PROJECTS.yaml
     - Note: paused projects should still get periodic success reviews (quarterly minimum)

   - **Archive**:
     - Recommend closing all milestones and issues
     - Suggest a final retrospective note in the charter
     - Set status to "archived" in PROJECTS.yaml
     - Move to lowest priority or remove from active list

3. **Generate specific workflow recommendations**
   - For each recommended action, specify the exact workflow to run:
     - `project/onboard` — if pivoting requires re-profiling
     - `project/press_release` — if there's a feature to announce or reframe
     - `project/success` — schedule the next review (quarterly for active, semi-annual for paused)
     - `milestone/setup` — if a new milestone should be created
     - `research/research` — if market validation or competitive analysis is needed
   - Order by urgency and impact

4. **Draft PROJECTS.yaml changes** (if applicable)
   - If the verdict warrants a priority change, specify exactly what to change
   - Show the before/after for the project entry
   - Do NOT make the change — just recommend it for human approval

5. **Identify charter updates needed**
   - If goals need revision based on the review, note what should change
   - This feeds back into the next `project/success` run
   - Do NOT modify the charter — just note what needs updating

## Output Format

### priority_recommendations.md

````markdown
# Priority Recommendations: [Project Name]

**Based on**: Success Review [Month YYYY]
**Verdict**: [verdict] (confidence: [level])

## Immediate Actions

### 1. [Most urgent action]

- **What**: [specific action]
- **Workflow**: `[job/workflow]` or manual action
- **Why**: [tied to verdict reasoning]
- **Owner**: [human / luce / drago]

### 2. [Next action]

...

## Priority Adjustment

**Current Priority**: [from PROJECTS.yaml]
**Recommended Priority**: [same / higher / lower / archive]
**Reasoning**: [why, tied to verdict]

### Proposed PROJECTS.yaml Change

```yaml
# Before
- name: [project]
  priority: [current]
  status: [current]

# After
- name: [project]
  priority: [new]
  status: [new]
```
````

## Charter Updates Needed

- [Goal or KPI that should be revised, and suggested revision]
- [Or "No updates needed — charter is current"]

## Next Review

- **Recommended**: [date — quarterly for active, semi-annual for paused]
- **Focus Areas**: [what to pay attention to before next review]

## Decision Points

[Key questions for the human to decide on — things the agent can't decide unilaterally.
e.g., "Should we pivot the target segment from developers to data scientists?"
or "Is the $X/month budget still available for this project?"]

```

## Quality Criteria

- Recommendations follow directly from the verdict in the success review
- Each recommendation specifies a concrete action with an owner and workflow
- Recommendations are ordered by urgency and impact
- PROJECTS.yaml changes are proposed but not applied (human approval required)
- The next review date is specified
- Decision points requiring human judgment are clearly called out

## Context

This is the final step that turns analysis into action. The recommendations should be specific enough that the human can say "yes, do it" and the agents can execute immediately. Avoid vague recommendations like "consider improving marketing" — instead say "run `project/press_release` for the X feature to test messaging with customers." The human is busy and focused on engineering — these recommendations are the business thread that keeps the project strategically coherent.
```
