Route product management requests to the appropriate DeepWork workflow.

Use this skill for press releases, milestone planning, stakeholder
communication, competitive analysis, and product-engineering handoffs.

## Supporting references

Before starting product work, review the relevant convention files
(co-located in this skill directory) for standards and process:

- **Business analyst role**: [business-analyst.md](business-analyst.md) -- market analysis, competitor research, KPIs
- **Project lead role**: [project-lead.md](project-lead.md) -- prioritization, milestone planning, stakeholder communication
- **Product-engineering handoff**: [process.product-engineering-handoff.md](process.product-engineering-handoff.md) -- handoff format and requirements
- **Press release**: [process.press-release.md](process.press-release.md) -- Working Backwards press release format
- **Project board**: [process.project-board.md](process.project-board.md) -- board management and milestone tracking
- **Prose**: [process.prose.md](process.prose.md) -- writing standards for all communications
- **Diagrams**: [process.diagrams.md](process.diagrams.md) -- visual communication standards
- **Mermaid**: [tool.mermaid.md](tool.mermaid.md) -- diagram rendering
- **Forgejo**: [tool.forgejo.md](tool.forgejo.md) -- issue and project management on Forgejo

## Available workflows

- **project/press_release** -- draft a Working Backwards press release for a new initiative
- **project/milestone** -- plan milestones and user stories from an approved press release
- **project/milestone_engineering_handoff** -- hand off milestone to engineering with specs and acceptance criteria
- **project/onboard** -- onboard a new project into the Keystone tracking system
- **project/success** -- evaluate project success criteria and outcomes

## Routing rules

- Press release drafting or product vision --> `project/press_release`
- Milestone planning or user story breakdown --> `project/milestone`
- Engineering handoff or spec preparation --> `project/milestone_engineering_handoff`
- New project setup or onboarding --> `project/onboard`
- Success evaluation or retrospective --> `project/success`
- Market analysis or competitive research --> read `business-analyst.md`, then answer directly
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available project workflows.
2. Call `start_workflow` with `job_name: "project"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
