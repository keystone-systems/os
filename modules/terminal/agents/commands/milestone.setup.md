---
description: Create a milestone from scope or press release
argument-hint: <milestone description or issue reference>
---

You MUST use the DeepWork MCP tools to execute this workflow.

1. Call `get_workflows` to confirm the workflow is available
2. Call `start_workflow` with:
   - goal: "$ARGUMENTS"
   - job_name: "milestone"
   - workflow_name: "setup"
3. Follow the step instructions returned by DeepWork
4. Call `finished_step` with your outputs when each step is complete
5. Continue until the workflow reaches `workflow_complete`
