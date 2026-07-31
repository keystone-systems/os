# Define or Update Charter

## Objective

Create or update the project's living charter document with a mission statement, business KPIs with targets, and goals across 5 time horizons (1 month, 6 months, 1 year, 5 years, 10 years).

## Task

Read the state assessment, then work with the human interactively to define or refine the charter. If a charter already exists, present the current version and ask what needs updating. If no charter exists, build one from scratch using the project profile as a starting point.

### Process

1. **Read the state assessment**
   - Load `state_assessment.md` from the previous step
   - Note existing charter content (if any), lean canvas data, and project status

2. **Define or confirm mission statement**
   - If a mission exists in the charter or README.yaml, present it and ask: "Is this still accurate, or should we refine it?"
   - If no mission exists, ask: "What is this project's mission? In one sentence, what does it exist to accomplish?"
   - The mission should be specific enough to guide prioritization decisions

3. **Define business KPIs**
   - Ask structured questions about which business metrics matter most. Suggest relevant KPIs based on the project type:
     - **Commercial**: revenue, MRR, users, conversion rate, CAC, LTV, churn
     - **Open-source**: stars, contributors, downloads, community engagement
     - **Nonprofit/Mission**: beneficiaries served, impact metrics, funding secured
   - For each KPI, gather:
     - **Current value** (or "not yet measured" if pre-launch)
     - **Target value** with timeframe
     - **How it's measured** (data source, frequency)
   - Aim for 3-5 KPIs — enough to be comprehensive, few enough to focus
   - Each KPI should appear as a single row in the table with one primary target and timeframe. Use the goals section (not the KPI table) for longer-term targets of the same metric.

4. **Define goals at 5 horizons**

   For each horizon, ask what success looks like. Guide the conversation:
   - **1 Month**: "What's the most important thing to accomplish in the next 30 days?"
     - Should be tactical, specific, and achievable
   - **6 Months**: "Where should this project be in 6 months?"
     - Should be milestone-level: features shipped, users reached, revenue targets
   - **1 Year**: "What does year-end success look like?"
     - Should cover product, market position, and business metrics
   - **5 Years**: "Where is this project in 5 years?"
     - Should describe market position, scale, and strategic positioning
   - **10 Years**: "What's the long-term vision?"
     - Should describe the enduring impact or market position

   Each goal must have concrete success criteria — not vague aspirations.

5. **Write the charter**
   - Save to `projects/{slug}/charter.md`
   - If updating an existing charter, preserve the creation date and add an "Updated" date
   - Include a change log section at the bottom tracking what changed and when

### Conversation Tips

- If the project is pre-launch, KPI current values can be "0" or "not yet measured" — that's fine
- For long horizons (5yr/10yr), it's OK to be more visionary, but still include at least one measurable criterion
- If the human seems unsure about a horizon, help them think through it: "Given your 1-year goal of X, what would the 5-year version of that look like?"
- Keep the conversation focused — 3-5 rounds of questions maximum
- Use AskUserQuestion for structured choices

## Output Format

### projects/{slug}/charter.md

```markdown
# Project Charter: [Project Name]

**Created**: [YYYY-MM-DD]
**Updated**: [YYYY-MM-DD]
**Status**: [from PROJECTS.yaml]

## Mission

[One clear sentence describing why this project exists and what it accomplishes]

## Key Performance Indicators

| KPI      | Current | Target   | Timeframe | How Measured  |
| -------- | ------- | -------- | --------- | ------------- |
| [metric] | [value] | [target] | [by when] | [data source] |

## Goals

### 1 Month

**Goal**: [specific, tactical goal]
**Success Criteria**:

- [ ] [measurable criterion 1]
- [ ] [measurable criterion 2]

### 6 Months

**Goal**: [milestone-level goal]
**Success Criteria**:

- [ ] [measurable criterion 1]
- [ ] [measurable criterion 2]

### 1 Year

**Goal**: [annual goal covering product and business]
**Success Criteria**:

- [ ] [measurable criterion 1]
- [ ] [measurable criterion 2]

### 5 Years

**Goal**: [strategic positioning goal]
**Success Criteria**:

- [ ] [measurable criterion 1]
- [ ] [measurable criterion 2]

### 10 Years

**Goal**: [long-term vision]
**Success Criteria**:

- [ ] [measurable criterion 1]
- [ ] [measurable criterion 2]

## Change Log

| Date         | Change                  |
| ------------ | ----------------------- |
| [YYYY-MM-DD] | Initial charter created |
```

## Quality Criteria

- The charter includes a clear mission statement that distinguishes this project
- At least 3 business KPIs are defined with current and target values
- Goals are defined for all 5 horizons: 1 month, 6 months, 1 year, 5 years, 10 years
- Each goal has concrete, measurable success criteria
- The charter is saved to `projects/{slug}/charter.md`

## Context

The charter is the strategic backbone of the project. It provides the criteria against which all prioritization decisions are made. The reality_check step will score progress against these KPIs and goals, and the update_priorities step will recommend actions based on the gap between current state and charter targets. A well-defined charter prevents scope creep, engineering-only drift, and unfocused effort.
