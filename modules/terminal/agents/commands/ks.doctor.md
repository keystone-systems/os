---
description: Start the keystone_system/doctor DeepWork workflow to check fleet health
argument-hint: <optional focus>
---

Start the keystone_system/doctor DeepWork workflow to check fleet health.

Use the DeepWork MCP tools to start the workflow:

- job_name: "keystone_system"
- workflow_name: "doctor"
- goal: "$ARGUMENTS" (use the user's arguments as context, or "Check all hosts are nominal" if no arguments)

Follow the workflow instructions returned by the MCP server. This runs ks doctor across all hosts and reports fleet health status.
