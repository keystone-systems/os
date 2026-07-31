---
description: Start the notes/doctor DeepWork workflow to repair and normalize a zk notebook
argument-hint: <optional scope>
---

Start the notes/doctor DeepWork workflow to repair and normalize a zk notebook.

Use the DeepWork MCP tools to start the workflow:

- job_name: "notes"
- workflow_name: "doctor"
- goal: "$ARGUMENTS" (use the user's arguments as scope or default to "Repair the configured notes dir")

Follow the workflow instructions returned by the MCP server. This audits the
notebook, normalizes frontmatter and tags, repairs project hubs and report
chains, and archives completed project material into the zk-managed archive.
