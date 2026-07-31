<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Agentic Team Operations (process.agentic-team)

This convention defines how a human operator works with a team of keystone agents to execute high-impact projects. It governs the interplay between the archetype/role system (context engineering), DeepWork jobs (structured workflows), and the human's role as decision-maker, reviewer, and strategic planner. The goal is to maximize human leverage by batching decisions, scheduling reviews, and keeping focused planning sessions separate from execution.

## Principles

1. Agents execute; the human decides. Agents MUST produce artifacts (documents, PRs, research reports, designs) autonomously. The human's time MUST be spent reviewing, approving, and steering — not writing or debugging.
2. Decisions MUST be batched. The human MUST NOT context-switch to review individual artifacts as they arrive. Instead, artifacts MUST accumulate and be reviewed in scheduled batches (see "Decision Batching" below).
3. Planning and execution MUST be temporally separated. The human MUST NOT interleave planning sessions with execution oversight in the same time block (see "Focused Planning Sessions" below).
4. Every agent action MUST be traceable to a decision the human made — an approved plan, a prioritized task, or a direct instruction.

## Team Structure

5. Each agent MUST be provisioned via `keystone.os.agents.<name>` with a defined archetype from `archetypes.yaml`. See `process.agent-cronjobs` for the timer-driven execution model.
6. Agent archetypes MUST match the work being delegated: `engineer` for implementation, `product` for planning and stakeholder work.
7. The human operator MUST be identifiable in `TEAM.md` with role assignments (CEO, CTO, CPO, or custom roles) that map to CODEOWNERS per `process.code-review-ownership`.
8. Agents MUST NOT assume roles outside their archetype without the human explicitly reassigning work.

## Keystone Agents vs. Sub-Agents

9. **Keystone agents** (provisioned via `keystone.os.agents`) are persistent identities with their own credentials, email, git accounts, desktop, and notes repo. They interact with shared platforms (GitHub, Forgejo, email) using their own identity — the same surfaces a human team member would use.
10. **Sub-agents** (spawned within a task loop iteration or DeepWork step) are ephemeral, generalized workers. They inherit the parent agent's credentials and have no persistent identity. Sub-agents are tools, not team members.
11. Keystone agents MUST be the ones that create issues, open PRs, post comments, and send emails — these actions appear under the agent's identity on shared platforms. Sub-agents MUST NOT interact with shared platforms directly.

## State and Memory

12. Agent working memory (notes repo, `TASKS.yaml`, `SCHEDULES.yaml`) is **internal state** — it drives the agent's autonomous behavior per `process.agent-cronjobs` and `process.task-tracking`. The human MAY inspect it via `agentctl <name> tasks` but SHOULD NOT treat it as the system of record.
13. The **system of record** for project state is the shared platform where work is visible to all participants:
    - **Issues and milestones**: GitHub/Forgejo per `process.project-board`.
    - **Code and specs**: PRs and committed files per `process.feature-delivery`.
    - **Progress and decisions**: Issue comments per `process.issue-journal`.
    - **Board status**: Project board columns per `process.project-board`.
14. Agents MUST write durable state to shared platforms, not just to their notes repo. The notes repo is scratch space and local memory; GitHub/Forgejo issues, PRs, and comments are the canonical record.
15. When an agent produces a research report, analysis, or plan, it MUST be committed to the project's repo (docs/specs/, docs/, or notes directory) and referenced from an issue or PR — not left only in the agent's notes directory.
16. DeepWork session outputs follow the same rule: final artifacts MUST be committed to a shared location. The DeepWork session directory is ephemeral working state.

## Context Engineering

17. Agent context MUST be composed via the archetype system: `archetypes.yaml` defines which conventions are inlined (always in context) vs. referenced (available on demand) for each archetype and role.
18. When delegating a task, the human SHOULD specify the role the agent should operate in (e.g., `code-reviewer`, `software-engineer`, `architect`, `business-analyst`). The role determines which conventions are dynamically loaded via `compose.sh`.
19. Role-specific conventions MUST NOT be duplicated across agents — they are shared via the conventions directory and composed at invocation time.
20. If an agent repeatedly fails at a task, the human SHOULD check whether the agent's role has the correct conventions loaded before re-attempting. Missing context is a more common root cause than agent incapability.

## Work Intake: From Strategy to Tasks

21. High-impact projects MUST begin with a planning session (see "Focused Planning Sessions" below) that produces one of:
    - A press release per `process.press-release` (for product initiatives).
    - A spec per `process.feature-delivery` (for engineering work).
    - A DeepWork job invocation per `process.deepwork-job` (for structured multi-domain work).
    - A direct task assignment (for small, well-defined work).
22. The planning artifact MUST be committed to the project's repo before agents begin execution (rule 15 applies).
23. The product-to-engineering handoff MUST follow `process.product-engineering-handoff`. This convention does not restate the pipeline — refer to the source.
24. Child issues MUST be scoped so that each can be completed by a single agent in a single task loop iteration. See `process.agent-cronjobs` for timeout constraints.

## DeepWork Jobs

25. For structured, multi-step work that spans domains (research, competitive analysis, due diligence, etc.), both humans and agents MUST invoke a DeepWork job rather than issuing ad-hoc instructions. DeepWork jobs MAY be invoked by:
    - The human directly (interactive session or planning session).
    - An agent's task loop, when a task references a DeepWork workflow per `process.task-tracking`.
    - An agent mid-step, as a nested workflow within another DeepWork job per `process.deepwork-job`.
    - A scheduled task per `process.agent-cronjobs`, triggering a workflow at a set cadence.
26. Job selection MUST follow `process.deepwork-job` job scope rules. This convention does not restate those rules — refer to the source.
27. Whoever starts a workflow — human or agent — MUST provide a clear goal string via `start_workflow`. The goal contextualizes all steps for the executing agent.
28. Quality gates within DeepWork workflows serve as review checkpoints. When the **human** started the workflow, quality gates are asynchronous — the human reviews outputs during the next scheduled review batch. When an **agent** started the workflow autonomously, quality gates are evaluated by the review agent inline per `process.deepwork-job`.
29. When a DeepWork job spans multiple agents (e.g., product agent runs `scope` step, engineering agent runs `implement` step), handoff MUST be coordinated by ensuring the first agent's outputs are committed to a shared location (rule 15) accessible to the second agent. The human MAY coordinate this explicitly, or the task loop MAY chain the handoff if the second task declares a dependency via `needs` in `TASKS.yaml` per `process.task-tracking`.

## Decision Batching

30. The human MUST establish a review cadence — a recurring schedule for processing accumulated agent output:

| Cadence      | Scope             | What to review                                                                                       |
| ------------ | ----------------- | ---------------------------------------------------------------------------------------------------- |
| 2x daily     | PR reviews        | Code PRs per `process.feature-delivery` review and merge section                                     |
| 1x daily     | Artifact reviews  | Documents, research outputs, DeepWork quality gates                                                  |
| 1x weekly    | Strategic review  | Milestone progress per `process.project-board`, roadmap health, blocker trends per `process.blocker` |
| 1x monthly   | Portfolio review  | Cross-project priorities, agent utilization, archetype/role effectiveness                            |
| 1x quarterly | Direction setting | OKR review, initiative planning, team structure changes                                              |

31. Agents MUST NOT block on human review for more than one review cycle. If a review is not completed within two cycles, the agent SHOULD escalate per `process.blocker`.
32. The human's review session MUST follow this order:
    1. **Triage**: Scan all pending items, categorize as approve/reject/needs-discussion.
    2. **Approve**: Merge or accept items that meet criteria — no perfectionism, bias toward shipping.
    3. **Reject with feedback**: Post actionable comments on items that need rework. The agent picks these up in its next task loop per `process.agent-cronjobs`.
    4. **Defer**: Items needing discussion go to the next planning session — do NOT resolve them inline during review.
33. Review artifacts MUST be discoverable in a single location. Agents MUST use issue journals per `process.issue-journal` and PR conventions per `process.feature-delivery` so the human can scan one dashboard (GitHub/Forgejo notifications, project board per `process.project-board`) rather than hunting across repos.

## Focused Planning Sessions

34. Planning MUST happen in dedicated time blocks, separate from review and execution oversight.
35. A planning session MUST produce at least one actionable output: a press release, spec, milestone, set of issues, DeepWork job invocation, or prioritized backlog.
36. Planning sessions SHOULD follow this structure:
    1. **Review context**: Read project board per `process.project-board`, milestone progress, and any agent-generated research or analysis.
    2. **Identify highest-leverage work**: What single decision or artifact will unblock the most agent work?
    3. **Produce the artifact**: Write the press release per `process.press-release`, spec, or plan. Commit it (rule 22).
    4. **Delegate**: Create issues, start DeepWork workflows per `process.deepwork-job`, or assign tasks to agents.
    5. **Set review expectations**: Note when you expect to review the outputs (next review batch per rule 30).
37. Planning sessions MUST NOT devolve into execution. If the human finds themselves writing code, drafting marketing copy, or performing research during a planning session, that work MUST be delegated to an agent instead.
38. The human SHOULD time-box planning sessions (recommended: 30-60 minutes) to maintain focus and prevent scope creep.

## Artifact Flow

39. All agent-produced artifacts MUST flow through a reviewable channel on the shared platform (rule 13):
    - **Code**: PR per `process.feature-delivery`.
    - **Documents** (specs, research, analysis): Committed to the project's repo, reviewed via PR or direct file review.
    - **DeepWork outputs**: Final artifacts committed to a shared repo (rule 16), reviewed at quality gates.
    - **Decisions and plans**: Posted as issue comments per `process.issue-journal`.
40. Artifacts MUST NOT be communicated via ephemeral channels (chat, email body text). If an agent sends an email notification per `tool.himalaya`, it MUST be a pointer to a committed artifact, not the artifact itself.
41. The human MUST NOT give feedback on artifacts via ephemeral channels. Feedback MUST be posted as PR comments, issue comments, or DeepWork quality gate responses so that agents can process it in their task loop per `process.agent-cronjobs`.

## Escalation and Blockers

42. Agents MUST follow `process.blocker` for infrastructure and platform issues.
43. For decision blockers (agent needs human input to proceed), the agent MUST:
    - Post a structured comment on the relevant issue per `process.issue-journal` with the decision needed, options considered, and a recommended option.
    - Label the issue `needs-decision`.
    - The human resolves decision blockers during the next review batch (rule 32).
44. The human SHOULD pre-empt decision blockers by providing clear acceptance criteria and constraints in specs and issue descriptions. Vague requirements are the primary source of decision blockers.

## Monitoring and Observability

45. The human MUST have a single-pane view of team status. Recommended: project board per `process.project-board` plus `agentctl <name> tasks` for per-agent task status.
46. Agent health MUST be observable via `agentctl <name> status` and systemd journal logs per `process.agent-cronjobs`.
47. The human SHOULD check team status at the start of each review session and planning session (rules 32, 36) — not continuously throughout the day.

## Anti-Patterns

48. **Micromanagement**: Reviewing every commit, hovering on agent logs, or providing line-by-line instructions defeats the purpose. Define the outcome, let agents find the path.
49. **Synchronous review**: Waiting for an agent to finish and reviewing immediately creates a bottleneck at the human. Batch reviews per rule 30 instead.
50. **Ad-hoc delegation**: Issuing tasks via chat or verbal instruction without a traceable artifact on the shared platform (rule 13) makes work invisible and unauditable.
51. **Planning during execution**: Mixing strategic thinking with tactical review dilutes both. Keep them in separate time blocks (rule 34).
52. **Role mismatch**: Asking an agent with `engineer` archetype to write marketing copy, or a `product` agent to debug infrastructure. Use the right archetype for the work (rule 6).
53. **Notes-as-system-of-record**: Treating the agent's notes repo as the canonical state. The notes repo is internal memory (rule 12); the shared platform is the system of record (rule 13).

## Golden Example

A human's operating rhythm with a two-agent team (Luce: product archetype, Drago: engineer archetype). Both agents have their own GitHub/Forgejo accounts, email, and notes repos provisioned via `keystone.os.agents`. They interact with issues, PRs, and project boards under their own identities.

### Daily

```
08:00 — Morning Review Session (30 min)
  1. Open project board (process.project-board) → scan columns
  2. agentctl luce tasks → check Luce's pending/blocked items
  3. agentctl drago tasks → check Drago's pending/blocked items
  4. Review PRs (Drago's code): approve 2, request changes on 1
     - Feedback posted as PR comments → Drago picks up in next task loop
  5. Review research doc committed by Luce: approve, merge PR
  6. Resolve 1 decision blocker: post decision on issue (process.issue-journal),
     remove needs-decision label

09:00 — Focused Planning Session (45 min)
  1. Read Luce's user stories issue on the milestone
  2. Write press release for next initiative (process.press-release), commit to repo
  3. Create milestone + consolidated user stories issue, assign to Luce
  4. Start DeepWork workflow: start_workflow("competitive_analysis", "quick", ...)
  5. Note: expect to review competitive analysis outputs tomorrow morning

  -- Agents execute autonomously (process.agent-cronjobs) --

16:00 — Afternoon Review Session (20 min)
  1. Review 3 new PRs from Drago
  2. Review DeepWork quality gate output from Luce's research workflow
  3. Post feedback on 1 spec draft → Drago picks up in next task loop
  4. Check project board — all items progressing, no new blockers
```

### Weekly (Friday)

```
10:00 — Strategic Review (45 min)
  1. Review project board (process.project-board) across all active milestones:
     - How many issues moved to Done this week?
     - What's been In Progress for >3 days? Investigate blockers.
     - Is the Backlog growing faster than Done? Scope may be too large.
  2. Check milestone burn-down: are we on track for the milestone deadline?
  3. Review agent utilization:
     - agentctl luce tasks → completed count this week
     - agentctl drago tasks → completed count this week
     - Are agents idle (backlog empty) or overloaded (blocked items piling up)?
  4. Triage backlog: reprioritize issues for next week.
     Move highest-impact items to To Do, defer lower-priority items.
  5. Review any open needs-decision issues that slipped through daily batches.
  6. Update the canonical project record if priorities shifted: milestones,
     board state, and any linked issues or release artifacts.
```

### Monthly (First Monday)

```
09:00 — Portfolio Review (60 min)
  1. Review all active milestones across all projects:
     - Which milestones are on track, at risk, or stalled?
     - Are any milestones complete and ready to close
       per process.product-engineering-handoff?
  2. Cross-project prioritization:
     - Given current capacity (2 agents), are we working on the highest-impact
       projects?
     - Should any project be paused to focus agents on a higher-priority one?
  3. Evaluate archetype and role effectiveness:
     - Are agents consistently failing at certain task types?
       Check convention loading (rule 20).
     - Should any role's conventions be updated in archetypes.yaml?
  4. Review agent infrastructure health:
     - agentctl <name> status for each agent
     - Check systemd journal for recurring errors (process.agent-cronjobs)
     - Are task loop timeouts or flock contention issues appearing?
  5. Produce a one-page status update: what shipped, what's next, what's blocked.
     Commit to project repo (rule 15), reference from relevant milestone issues.
```

### Quarterly (First Week)

```
Monday — Direction Setting (half day)
  1. Review quarterly OKRs / goals from last quarter:
     - What was achieved? Reference closed milestones and demo artifacts
       per process.product-engineering-handoff.
     - What was missed and why? Check blocker history per process.blocker.
  2. Assess whether the current project portfolio aligns with the mission.
     Kill or deprioritize projects that no longer serve the mission.
  3. Define next quarter's initiatives:
     - Write 1-3 press releases (process.press-release) for the highest-impact
       initiatives. These become the quarter's north stars.
     - For each press release, identify which agent archetype and roles will
       execute the work.
  4. Plan team structure changes:
     - Do we need a new agent? Provision via keystone.os.agents (rule 5).
     - Do we need a new archetype or role? Update archetypes.yaml.
     - Do we need new conventions? Create per conventions/AGENTS.md.
  5. Seed the first milestone for each initiative:
     - Create milestones and project boards (process.project-board).
     - Assign the product agent to produce user stories
       per process.product-engineering-handoff.
     - Start any long-running DeepWork research workflows (process.deepwork-job).
  6. Commit quarterly plan to project repo. This is the authoritative record —
     not a slide deck, not a notes file.

  -- Agents begin executing on the new quarter's milestones --
```

## References

- [Agent Cronjobs](./process.agent-cronjobs.md) — Timer-driven autonomous execution
- [Blocker Escalation](./process.blocker.md) — How agents report and recover from blockers
- [Code Review Ownership](./process.code-review-ownership.md) — Reviewer assignment via CODEOWNERS
- [DeepWork Job Design](./process.deepwork-job.md) — Job and workflow design rules
- [Feature Delivery](./process.feature-delivery.md) — End-to-end code delivery lifecycle
- [Issue Journal](./process.issue-journal.md) — Structured issue comments for visibility
- [Product-Engineering Handoff](./process.product-engineering-handoff.md) — Press release to milestone pipeline
- [Project Board](./process.project-board.md) — Board column conventions and transitions
- [Task Tracking](./process.task-tracking.md) — TASKS.yaml schema and agent-internal state
