---
description: Start the keystone_system/update DeepWork workflow to deploy pending keystone changes to the fleet
argument-hint: <optional context>
---

Start the keystone_system/update DeepWork workflow to deploy pending keystone changes to the fleet.

Use the DeepWork MCP tools to start the workflow:

- job_name: "keystone_system"
- workflow_name: "update"
- goal: "$ARGUMENTS" (use the user's arguments as context, or "Survey fleet, triage pending changes, fix issues, build all hosts, and prepare for ks update --lock" if no arguments)

Follow the workflow instructions returned by the MCP server. This surveys the keystone revision gap, triages changes, applies ad-hoc fixes, runs preflight builds for all target hosts, then guides the human through `ks update --lock` and validates the fleet.
