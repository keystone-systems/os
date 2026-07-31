---
description: Start the task_loop/ingest DeepWork workflow to ingest tasks from source files
argument-hint: <optional task source>
---

Start the task_loop/ingest DeepWork workflow to ingest tasks from source files.

Use the DeepWork MCP tools to start the workflow:

- job_name: "task_loop"
- workflow_name: "ingest"
- goal: "$ARGUMENTS" (optional, a specific task source JSON file or directory)

Follow the workflow instructions returned by the MCP server. This parses pre-fetched source JSON and creates or updates tasks in the agent-space TASKS.yaml.
