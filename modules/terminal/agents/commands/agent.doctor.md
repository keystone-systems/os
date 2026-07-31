---
description: Start the agent_builder/doctor DeepWork workflow to diagnose agent health
argument-hint: <agent name>
---

Start the agent_builder/doctor DeepWork workflow to diagnose agent health.

Use the DeepWork MCP tools to start the workflow:

- job_name: "agent_builder"
- workflow_name: "doctor"
- goal: "$ARGUMENTS" (the name of the agent to diagnose, e.g., 'drago' or 'luce')

Follow the workflow instructions returned by the MCP server. This runs status checks on all agent timers (notes-sync, task-loop, scheduler), analyzes recent logs for errors, and produces a diagnosis with actionable fix commands.
