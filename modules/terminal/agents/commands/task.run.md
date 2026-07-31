---
description: Start the task_loop/run DeepWork workflow to execute a single pending task
argument-hint: <optional task ID or context>
---

Start the task_loop/run DeepWork workflow to execute a single pending task.

Use the DeepWork MCP tools to start the workflow:

- job_name: "task_loop"
- workflow_name: "run"
- goal: "$ARGUMENTS" (optional, a specific task name from TASKS.yaml or user prompt)

Follow the workflow instructions returned by the MCP server. This executes a single pending task, updating its status in TASKS.yaml and creating a worktree for the task if necessary.
