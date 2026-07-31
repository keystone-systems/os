---
description: Start the notes/process_inbox DeepWork workflow to review and promote fleeting notes
argument-hint: <optional note ID or query>
---

Start the notes/process_inbox DeepWork workflow to review and promote fleeting notes.

Use the DeepWork MCP tools to start the workflow:

- job_name: "notes"
- workflow_name: "process_inbox"
- goal: "$ARGUMENTS" (optional, a specific fleeting note ID or query)

Follow the workflow instructions returned by the MCP server. This reviews all fleeting notes in inbox/, classifies each for promotion or discard, promotes them to permanent/literature notes with proper frontmatter and links, and syncs via repo-sync.
