---
description: Start the keystone_system/develop DeepWork workflow
argument-hint: <goal>
---

Start the keystone_system/develop DeepWork workflow.

Use the DeepWork MCP tools to start the workflow:

- job_name: "keystone_system"
- workflow_name: "develop"
- goal: "$ARGUMENTS" (use the user's arguments as the goal)

Follow the workflow instructions returned by the MCP server. This is the full keystone development lifecycle: plan in worktree → implement → review → build → merge → deploy (human-in-the-loop) → validate all hosts.
