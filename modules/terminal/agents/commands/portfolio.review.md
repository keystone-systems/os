---
description: Start the portfolio/review DeepWork workflow for a holistic portfolio health assessment
argument-hint: <optional focus>
---

Start the portfolio/review DeepWork workflow for a holistic portfolio health assessment.

Use the DeepWork MCP tools to start the workflow:

- job_name: "portfolio"
- workflow_name: "review"
- goal: "$ARGUMENTS" (optional, a specific focus area or project subset)

Follow the workflow instructions returned by the MCP server. This performs a full review of all active projects, gathering milestone status and git activity to produce a synthesized health report and Eisenhower matrix delivered via pull request to the notes repo.
