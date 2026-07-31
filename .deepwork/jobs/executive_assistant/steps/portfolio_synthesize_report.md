# Synthesize Portfolio Report

## Objective

Combine all per-project summaries into a single portfolio health report with cross-project
analysis, an overall health assessment, and priority recommendations.

## Task

Read the combined per-project summaries and the project list, then produce a portfolio
report that gives the user a complete picture of where everything stands.

**CRITICAL**: The report MUST only contain data that appears in `all_summaries.md` and
`project_list.md`. Do not include projects, commit counts, dates, or metrics from any
other source. Every number in the report must trace back to the input files.

### Process

1. **Calculate portfolio-level metrics**

   From the per-project summaries, compute:
   - Total active projects
   - Projects by status: 🟢 On Track, 🟡 At Risk, 🔴 Behind, ⚪ Deferred
   - Total open milestones across all projects
   - Overall activity trend (how many projects have high/medium/low/stagnant activity)

2. **Build the project status table**

   Create a summary table with one row per project showing:
   - Project name
   - Status indicator
   - Active milestone (most important one) with progress
   - Activity level
   - Top blocker (if any)

   Order by priority (from the project list), or by status severity if no priority exists.

3. **Detail all in-flight milestones**

   Aggregate all open milestones across projects into one table:
   - Project, milestone title, progress, due date, health
   - Highlight overdue milestones
   - Show recently completed milestones as wins

4. **Create the activity heatmap**

   A visual summary of which projects are active vs. stagnant:
   - Rank projects by commit count in last 30 days
   - Flag projects with zero activity that have open milestones (these are at risk)

5. **Build portfolio Eisenhower matrix**

   Classify each active project into the Eisenhower quadrants:
   - **Urgent**: Has overdue milestones, approaching deadlines, critical blockers,
     or time-sensitive external dependencies (e.g., a client deadline)
   - **Important**: Core to the user's mission, revenue-generating, has active
     milestones with momentum, or is a dependency for other projects
   - Projects with no milestones and no activity typically fall in Q4 (eliminate/archive)
   - Projects with high activity and near-complete milestones are Q1 (do first)

   Render the matrix as one HTML 2x2 chart embedded directly in the markdown. Use
   bullet lists inside the quadrants so the output stays scannable in both markdown
   and print. The chart MUST use this exact structure so `ks print` can style it:
   - one `<table class="eisenhower-matrix">`
   - one `<colgroup>` with `axis-col` then two `quadrant-col` columns
   - a header row for `Urgent` / `Not urgent`
   - a left column for compact axis labels such as `Imp.` / `Not imp.`
   - one `<td class="quadrant quadrant-qN">` per quadrant
   - one `<div class="quadrant-heading">` per quadrant
   - one `<ul>` with project bullets per quadrant

6. **Identify cross-project concerns**

   Look for patterns across projects:
   - Are multiple projects blocked on the same thing?
   - Is attention too scattered (many projects, low activity each)?
   - Are there resource conflicts (same person/agent needed across projects)?
   - Are any projects drifting without clear direction (no milestones, no charter)?

7. **Write priority recommendations**

   Based on the data, recommend where to focus:
   - Which projects need immediate attention (🔴 Behind or overdue milestones)?
   - Which projects should be explicitly paused/archived to reduce cognitive load?
   - Which milestones are closest to completion and should be finished first?
   - What new milestones or reviews should be initiated?

   Recommendations must be specific and actionable. Each should reference a DeepWork
   workflow to run if applicable (e.g., "Run `project/success` for catalyst to update
   the charter").

8. **Write the report and open a PR from the worktree branch**

   The report is delivered as a pull request from the `portfolio-review/YYYY-MM`
   worktree branch set up in `discover_projects`. Use `$WORKTREE_PATH` (not the
   primary `notes_path` checkout).

   ```bash
   NOTES_OWNER_REPO=$(git -C "$NOTES_PATH" remote get-url origin \
     | sed 's|.*[:/]\([^/]*/[^/]*\)\.git|\1|')
   WORKTREE_PATH="${WORKTREE_DIR:-$HOME/.worktrees}/${NOTES_OWNER_REPO}/portfolio-review/$(date +%Y-%m)"
   mkdir -p "${WORKTREE_PATH}/projects/portfolio/reviews/"
   ```

   Write the report to `projects/portfolio/reviews/YYYY-MM.md` inside the worktree.

   Then commit and push:

   ```bash
   git -C "$WORKTREE_PATH" add projects/portfolio/reviews/YYYY-MM.md
   git -C "$WORKTREE_PATH" commit -m "docs(portfolio): add YYYY-MM portfolio review"
   git -C "$WORKTREE_PATH" push -u origin portfolio-review/YYYY-MM
   ```

   Open a PR using the appropriate platform CLI. Detect the platform from the
   remote URL:
   - `github.com` → use `gh pr create`
   - `git.ncrmro.com` or other Forgejo → use `tea pr create`

   **GitHub**:

   ```bash
   gh pr create --title "docs(portfolio): YYYY-MM portfolio review" \
     --body "$(cat <<'PREOF'
   ## Portfolio Review — YYYY-MM

   [Portfolio Summary section from report]

   > This PR will auto-merge in 72 hours. Comment or request changes before then.
   PREOF
   )"
   gh pr merge --auto --squash
   ```

   **Forgejo** (tea CLI):

   ```bash
   tea pr create --repo ncrmro/notes \
     --title "docs(portfolio): YYYY-MM portfolio review" \
     --description "$(cat <<'PREOF'
   ## Portfolio Review — YYYY-MM

   [Portfolio Summary section from report]

   > This PR will auto-merge in 72 hours. Comment or request changes before then.
   PREOF
   )"
   ```

   The PR allows the user to comment on specific sections, request changes,
   and refine the report before it lands on main.

   **Auto-merge convention**: If the platform supports auto-merge, enable it so the
   PR merges automatically after a 72-hour review window. This gives the user time
   to comment but prevents stale PRs.

9. **Output the PR URL**

   After creating the PR, output the PR URL prominently so the user can navigate
   directly to it for review. This is the primary deliverable of the workflow — the
   user needs this link.

## Output Format

### portfolio_report.md

The final portfolio review report.

**Structure**:

```markdown
# Portfolio Review — [Month YYYY]

| Date | Active projects |
| --- | --- |
| [YYYY-MM-DD] | [N] |

| Open milestones | Overall health |
| --- | --- |
| [N] | [🟢/🟡/🔴] [summary sentence] |

## Portfolio Summary

[2-3 sentence executive summary of where things stand. Highlight the biggest win,
the biggest risk, and the recommended focus area.]

<div class="note-box">
  <div class="note-box-title">Summary notes</div>
  <div class="note-lines"></div>
</div>

## Project Status

| Project  | Status      | Active Milestone    | Progress | Activity     | Top Blocker    |
| -------- | ----------- | ------------------- | -------- | ------------ | -------------- |
| keystone | 🟡 At Risk  | Desktop Integration | 67%      | High (23)    | Installer TUI  |
| catalyst | 🟢 On Track | MVP Launch          | 45%      | Medium (8)   | —              |
| meze     | ⚪ Deferred | —                   | —        | Stagnant (0) | No active work |
| eonmun   | ⚪ Deferred | —                   | —        | Stagnant (0) | —              |

[...]

## In-Flight Milestones

| Project  | Milestone           | Open | Closed | Progress | Due Date   | Health |
| -------- | ------------------- | ---- | ------ | -------- | ---------- | ------ |
| keystone | Desktop Integration | 4    | 8      | 67%      | 2026-04-01 | 🟡     |
| catalyst | MVP Launch          | 6    | 5      | 45%      | 2026-05-01 | 🟢     |

[...]

**Recently Completed**: keystone/Terminal Module (2026-02-15)

## Activity (Last 30 Days)

| Project      | Commits | Last Commit | Trend    |
| ------------ | ------- | ----------- | -------- |
| keystone     | 23      | 2026-03-19  | High     |
| catalyst     | 8       | 2026-03-15  | Medium   |
| nixos-config | 5       | 2026-03-10  | Medium   |
| meze         | 0       | 2025-12-01  | Stagnant |

[...]

## Portfolio priority matrix

<table class="eisenhower-matrix">
  <colgroup>
    <col class="axis-col" />
    <col class="quadrant-col" />
    <col class="quadrant-col" />
  </colgroup>
  <thead>
    <tr>
      <th></th>
      <th>Urgent</th>
      <th>Not urgent</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>Imp.</th>
      <td class="quadrant quadrant-q1">
        <div class="quadrant-heading">Q1 - Do first</div>
        <ul>
          <li>keystone - Desktop integration, 67%, high activity</li>
          <li>nixos-config - Infra maintenance, medium activity</li>
        </ul>
      </td>
      <td class="quadrant quadrant-q2">
        <div class="quadrant-heading">Q2 - Schedule</div>
        <ul>
          <li>catalyst - Cloud platform, medium activity</li>
          <li>obsidian - ZK migration, active but not urgent</li>
        </ul>
      </td>
    </tr>
    <tr>
      <th>Not imp.</th>
      <td class="quadrant quadrant-q3">
        <div class="quadrant-heading">Q3 - Delegate</div>
        <ul>
          <li>plant-caravan - Open milestone, low importance today</li>
        </ul>
      </td>
      <td class="quadrant quadrant-q4">
        <div class="quadrant-heading">Q4 - Eliminate / Archive</div>
        <ul>
          <li>meze - No milestones, stagnant</li>
          <li>eonmun - No milestones, stagnant</li>
          <li>tetrastack - No active work</li>
          <li>ks.systems - No active work</li>
          <li>latinum-space - No active work</li>
          <li>ncrmro-website - No active work</li>
          <li>ks-hw - No active work</li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

<div class="note-box">
  <div class="note-box-title">Matrix notes</div>
  <div class="note-lines note-lines-tall"></div>
</div>

**Reading the matrix**: Q1 projects need your time NOW. Q2 projects are strategic
but not time-pressured — schedule dedicated blocks. Q3 items have urgency signals
(open milestones) but low importance — delegate to agents or deprioritize. Q4 projects
should be explicitly archived to reduce cognitive overhead.

## Cross-Project Concerns

- **Attention spread**: [N] active projects but only [M] have meaningful activity —
  consider pausing projects without clear milestones
- **Stale projects with potential**: meze and eonmun have repos but no recent activity
  or milestones — decide to reactivate or archive

## Recommendations

1. **Finish keystone Desktop Integration** — 67% complete, closest to done. Focus
   remaining effort here. (4 issues remaining)
2. **Archive or reactivate meze** — No activity in 90+ days. Run `project/success`
   to decide: continue, pivot, or archive.
3. **Create milestone for nixos-config** — Active commits but no milestone to track
   against. Run `milestone/setup` to formalize scope.
4. **Pause eonmun** — No activity, no milestones. Explicitly mark as paused in
   PROJECTS.yaml to reduce cognitive load.

<div class="note-box">
  <div class="note-box-title">Decision notes</div>
  <div class="note-lines note-lines-tall"></div>
</div>
```

## Quality Criteria

- The report opens with an overall portfolio health assessment and project count
- A summary table lists every project with status indicator, milestone, and activity
- All open milestones across projects are listed with completion percentages and dates
- Cross-project concerns are identified (resource conflicts, scattered attention, stagnation)
- Recommendations are specific, actionable, and ordered by impact
- All status indicators and assessments cite specific data, not vague assertions
- The report is written to the correct path in the notes repo

## Context

This is the capstone step of the portfolio review. The user reads this report to decide
where to allocate their time and energy. It should be scannable (tables, not paragraphs)
and opinionated (clear recommendations, not just data dumps). Keep the matrix HTML
shape consistent so the document prints as a real four-quadrant chart. The report replaces the
old per-project `status.md` files with a single portfolio-level view.
