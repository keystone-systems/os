---
description: Start the notes/report DeepWork workflow to capture a standardized project report note
argument-hint: <project and report context>
---

Start the notes/report DeepWork workflow to capture a standardized project report note.

Use the DeepWork MCP tools to start the workflow:

- job_name: "notes"
- workflow_name: "report"
- goal: "$ARGUMENTS" (the project plus report context, such as "keystone fleet health")

Follow the workflow instructions returned by the MCP server. This creates a
report note in `reports/`, applies canonical project and report tags, links to
the latest prior report in the chain, and updates the project hub.
