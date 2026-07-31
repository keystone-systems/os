# Assess Project State

## Objective

Gather the current state of a project from all available sources — README.yaml, PROJECTS.yaml, platform milestones/issues, git activity, and any existing charter — to establish a factual baseline for the charter and reality check steps.

## Task

Read all available project data and compile a comprehensive state assessment. This is a data-gathering step — do not make judgments or recommendations here.

### Process

1. **Read the project profile**
   - Read `projects/{slug}/README.yaml` for the project's mission, repos, lean canvas, and status
   - If no README.yaml exists, note the absence and use PROJECTS.yaml description as the only profile data. Recommend running `project/onboard` as a follow-up in the state assessment output.
   - Read `PROJECTS.yaml` for the project's current priority ranking
   - Note the project type, status, and any riskiest assumptions listed

2. **Check for existing charter**
   - Look for `projects/{slug}/charter.md`
   - If it exists, read it and note: mission statement, KPIs (with any recorded values), goals at each horizon, and when it was last updated
   - If it doesn't exist, note "No charter exists — will be created in the next step"

3. **Check previous success reviews**
   - Look for `projects/{slug}/reports/success_review_*.md`
   - If any exist, read the most recent one and note: last verdict, confidence, and key findings
   - This provides continuity across reviews

4. **Gather platform activity**
   - Identify the project's primary repo and platform from README.yaml
   - Check milestone status:
     - GitHub: `gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, open_issues, closed_issues, state}'`
     - Forgejo: equivalent API call
   - Check recent issue activity (last 30 days):
     - GitHub: `gh issue list --repo {owner}/{repo} --state all --limit 20`
   - Note: total open issues, recently closed, any blockers or stale issues

5. **Gather git activity**
   - Check recent commit frequency:
     - `gh api repos/{owner}/{repo}/commits --jq '.[0:10] | .[] | {date: .commit.author.date, message: .commit.message}'`
   - Note: last commit date, commit frequency, active contributors

6. **Assess activity balance**
   - Categorize recent activity as engineering (code, PRs, technical issues) vs business (milestones, user stories, press releases, research)
   - Note the ratio — this feeds the "business thread" check in the reality_check step

## Output Format

### state_assessment.md

```markdown
# State Assessment: [Project Name]

## Project Profile

- **Name**: [name]
- **Slug**: [slug]
- **Status**: [from PROJECTS.yaml]
- **Priority**: [from PROJECTS.yaml]
- **Mission**: [from README.yaml]
- **Type**: [commercial / nonprofit / open-source / mission-focused]

## Existing Charter

[Summary of current charter if it exists, or "No charter exists"]

- **Last Updated**: [date or N/A]
- **Current Mission**: [from charter or "not defined"]
- **KPIs Defined**: [count and list, or "none"]
- **Goals Defined**: [which horizons have goals, or "none"]

## Previous Reviews

- **Last Review**: [date or "none"]
- **Last Verdict**: [verdict or "N/A"]
- **Last Confidence**: [level or "N/A"]
- **Key Findings**: [summary or "N/A"]

## Milestone Status

| Milestone | Open Issues | Closed Issues | Completion |
| --------- | ----------- | ------------- | ---------- |
| [title]   | [n]         | [n]           | [%]        |

## Recent Activity (Last 30 Days)

- **Issues Opened**: [n]
- **Issues Closed**: [n]
- **Last Commit**: [date]
- **Commit Frequency**: [e.g., "3-4 per week" or "1 in last month"]
- **Active Contributors**: [list]

## Activity Balance

- **Engineering Activity**: [summary — PRs merged, code issues, deployments]
- **Business Activity**: [summary — milestones created, user stories, research, press releases]
- **Balance Assessment**: [e.g., "heavily engineering-skewed" or "balanced" or "mostly business planning"]

## Raw Data for Charter

- **Lean Canvas Problem**: [from README.yaml]
- **Customer Segments**: [from README.yaml]
- **UVP**: [from README.yaml]
- **Riskiest Assumptions**: [from README.yaml]
- **Recommended Next Steps**: [from README.yaml]
```

## Quality Criteria

- Project data from README.yaml and PROJECTS.yaml is captured
- Existing charter and previous reviews are read if they exist
- Milestone and issue status is gathered from the platform
- Recent git activity is summarized
- Activity balance between engineering and business work is assessed
