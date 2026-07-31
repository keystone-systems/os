Route project management requests to the appropriate DeepWork workflow.

Use this skill for task decomposition, milestone tracking, board management,
blocker escalation, and issue triage.

## Supporting references

Before starting project management work, review the relevant convention files
(co-located in this skill directory) for standards and process:

- **Project lead role**: [project-lead.md](project-lead.md) -- prioritization, milestone planning, stakeholder communication
- **Task decomposer role**: [task-decomposer.md](task-decomposer.md) -- chunking work into sequential, shippable PRs
- **Feature delivery**: [process.feature-delivery.md](process.feature-delivery.md) -- end-to-end lifecycle from issue through merged PR
- **Project board**: [process.project-board.md](process.project-board.md) -- board management and milestone tracking
- **Task tracking**: [process.task-tracking.md](process.task-tracking.md) -- task state management and progress reporting
- **Blockers**: [process.blocker.md](process.blocker.md) -- blocker escalation and resolution
- **Issue journal**: [process.issue-journal.md](process.issue-journal.md) -- issue comment standards and work-started/work-update format
- **VCS context continuity**: [process.vcs-context-continuity.md](process.vcs-context-continuity.md) -- PR progress tracking and resumability
- **Forgejo**: [tool.forgejo.md](tool.forgejo.md) -- issue and project management on Forgejo
- **GitHub**: [tool.github.md](tool.github.md) -- issue and PR management on GitHub

## Available workflows

- **project/milestone** -- plan milestones and user stories
- **project/milestone_engineering_handoff** -- prepare engineering handoff with specs and acceptance criteria
- **project/doctor** -- diagnose project health and fix tracking issues
- **project/wrap_up** -- close out a project milestone with status and retrospective

## Routing rules

- Task breakdown or decomposition requests --> read `task-decomposer.md`, then decompose directly or start `project/milestone`
- Milestone planning or story mapping --> `project/milestone`
- Engineering handoff preparation --> `project/milestone_engineering_handoff`
- Project health checks or tracking issues --> `project/doctor`
- Milestone wrap-up or retrospective --> `project/wrap_up`
- Blocker escalation --> read `process.blocker.md`, then escalate following the convention
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available project workflows.
2. Call `start_workflow` with `job_name: "project"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
