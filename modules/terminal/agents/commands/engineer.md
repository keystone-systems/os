---
description: Start a DeepWork engineer workflow to execute engineering work from issue through PR merge
argument-hint: <product issue URL or description>
---

Start the engineer DeepWork workflow.

Use the DeepWork MCP tools to start the workflow:
- job_name: "engineer"
- workflow_name: "implement"
- goal: "$ARGUMENTS" (product issue URL, issue identifier, or task description)

Before starting, verify the repo is ready:
1. Check that an agent context file (AGENTS.md, CLAUDE.md, or equivalent) exists at the repo root with domain declaration and build/test instructions
2. If missing or incomplete, run the doctor workflow first (workflow_name: "doctor") to diagnose and remediate, then resume implement

Follow the workflow instructions returned by the MCP server. The implement workflow handles: translate product issue, initialize branch, write failing tests, implement to green, finalize PR with artifacts, and sync back to product issue.
