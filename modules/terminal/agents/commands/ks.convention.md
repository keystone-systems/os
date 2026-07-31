---
description: Start the keystone_system/convention DeepWork workflow
argument-hint: <goal>
---

Start the keystone_system/convention DeepWork workflow.

Use the DeepWork MCP tools to start the workflow:

- job_name: "keystone_system"
- workflow_name: "convention"
- goal: "$ARGUMENTS" (use the user's arguments as the goal)

Follow the workflow instructions returned by the MCP server. This workflow creates or updates a keystone convention: draft in RFC 2119 format → cross-reference existing conventions for overlap → apply changes and wire archetypes → commit to main.
