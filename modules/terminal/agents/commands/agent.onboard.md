---
description: Start the agent_builder/onboard DeepWork workflow to onboard an agent to services
argument-hint: <agent name>
---

Start the agent_builder/onboard DeepWork workflow to onboard an agent to services.

Use the DeepWork MCP tools to start the workflow:

- job_name: "agent_builder"
- workflow_name: "onboard"
- goal: "$ARGUMENTS" (agent name to onboard)

Follow the workflow instructions returned by the MCP server. This signs into all configured services (Google, GitHub, Forgejo, Vaultwarden) and configures the agent's local CLIs.
