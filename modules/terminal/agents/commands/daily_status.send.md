---
description: Start the daily_status/send DeepWork workflow to send the daily digest
argument-hint: <optional focus>
---

Start the daily_status/send DeepWork workflow to send the daily digest.

Use the DeepWork MCP tools to start the workflow:

- job_name: "daily_status"
- workflow_name: "send"
- goal: "$ARGUMENTS" (optional, a specific topic or focus for today's status)

Follow the workflow instructions returned by the MCP server. This gathers status data across projects, composes a synthesized daily digest, and sends it as an email to the human operator.
