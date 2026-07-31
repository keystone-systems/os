---
description: Start the agent_builder/issue DeepWork workflow to file an infrastructure issue
argument-hint: <problem description>
---

Start the agent_builder/issue DeepWork workflow to file an infrastructure issue.

Use the DeepWork MCP tools to start the workflow:

- job_name: "agent_builder"
- workflow_name: "issue"
- goal: "$ARGUMENTS" (description of the infrastructure problem, e.g., 'scheduler permission denied')

Follow the workflow instructions returned by the MCP server. This drafts a GitHub issue with title, body, labels, and assignee for the admin's ks-config repo to address agent-space blockers.
