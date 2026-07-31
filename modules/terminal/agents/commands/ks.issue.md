---
description: Start the keystone_system/issue DeepWork workflow to create a GitHub issue
argument-hint: <feature description>
---

Start the keystone_system/issue DeepWork workflow to create a GitHub issue.

Use the DeepWork MCP tools to start the workflow:

- job_name: "keystone_system"
- workflow_name: "issue"
- goal: "$ARGUMENTS" (use the user's arguments as the feature description)

Follow the workflow instructions returned by the MCP server. This researches the codebase and creates or identifies a GitHub issue whose body contains the context, affected modules, RFC 2119 requirements, diagrams, and deliverables that should later be reflected in the PR. A local draft file may be used as a staging artifact for `gh issue create`.
