---
description: Start the repo/doctor DeepWork workflow to audit existing repo state
argument-hint: <optional repo path or name>
---

Start the repo/doctor DeepWork workflow to audit existing repo state.

Use the DeepWork MCP tools to start the workflow:

- job_name: "repo"
- workflow_name: "doctor"
- goal: "$ARGUMENTS" (optional, a specific repo path or name to audit)

Follow the workflow instructions returned by the MCP server. This audits the repo's labels, milestones, branch protection, and project boards to identify and fix drift across team conventions.
