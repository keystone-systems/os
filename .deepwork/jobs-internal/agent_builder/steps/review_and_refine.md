# Review and Refine

## Objective

Present the complete agent-space to the user for review. Offer to refine any files,
add missing content, or create new roles/conventions in the shared library.

## Task

Walk the user through what was created, verify everything works, and make adjustments.

### Process

1. **Present the file tree**

   Show the user the complete directory listing of the new agent-space. For each
   file, give a one-line summary of what it contains.

2. **Verify compose.sh works**

   Run `compose.sh` with the new manifest to confirm the system prompt assembles
   correctly:

   ```bash
   cd .repos/{owner}/{repo}
   .agents/compose.sh manifests/modes.yaml {first_mode}
   ```

   If this fails, debug the `agents_repo` path in the manifest.

3. **Verify symlinks**

   Confirm both symlinks resolve:
   - `ls -la CLAUDE.md` → should point to AGENTS.md
   - `ls -la .deepwork` → should point to .agents/.deepwork
   - `ls .deepwork/job.schema.json` → should succeed

4. **Offer refinements**

   Ask structured questions using the AskUserQuestion tool to determine which
   refinements the user wants. Present options such as:
   - Edit SOUL.md (adjust personality, add accounts)
   - Modify the manifest (add/remove modes, change role assignments)
   - Update PROJECTS.yaml (add/remove projects, change priorities)
   - Edit AGENTS.md (add tool conventions, update operational rules)
   - Create new roles or conventions in the shared library
   - No changes needed

   Use multiSelect so the user can pick multiple refinements at once.

   If the user wants new roles or conventions, guide them through creating the
   files in the ncrmro/agents repo following the conventions in CLAUDE.md:
   - Roles: H1 title → description → `## Behavior` → `## Output Format`
   - Conventions: RFC 2119 preamble comment → `# Convention: {Name} ({dotted.name})` → numbered rules

5. **Generate summary**

   Write a summary file documenting what was created and any next steps.

## Output Format

### summary.md

```markdown
# Agent-Space Created: {Agent Name}

## Files Created

| File                 | Purpose                                        |
| -------------------- | ---------------------------------------------- |
| SOUL.md              | Agent identity and accounts                    |
| AGENTS.md            | Operational rules and tool conventions         |
| CLAUDE.md            | Symlink to AGENTS.md                           |
| PROJECTS.yaml        | {N} projects, priority-ordered                 |
| TASKS.yaml           | Empty task queue                               |
| SCHEDULES.yaml       | {N} scheduled tasks                            |
| ISSUES.yaml          | Empty issues list                              |
| manifests/modes.yaml | {N} modes mapped to shared roles               |
| .agents/             | Git submodule (ncrmro/agents shared library)   |
| .mcp.json            | MCP server config (deepwork + chrome-devtools) |
| .deepwork            | Symlink to shared DeepWork config              |

## Modes Available

| Mode   | Roles   | Conventions   |
| ------ | ------- | ------------- |
| {mode} | {roles} | {conventions} |

## Compose.sh Verification

{Pass/fail result of running compose.sh}

## Next Steps

- [ ] Push to Forgejo: `cd .repos/{owner}/{repo} && git add -A && git commit -m "feat: bootstrap agent-space" && git remote add origin ssh://forgejo@git.ncrmro.com:2222/{owner}/{repo}.git && git push -u origin main`
- [ ] Add NixOS agent config in keystone modules/os/agents.nix
- [ ] Create agenix secrets for SSH key, mail password, etc.
- [ ] Set up systemd task loop timer

## Refinements Made

{List any changes made during review, or "None"}
```

## Quality Criteria

- Summary accurately lists all created files
- compose.sh verification was attempted and result documented
- Next steps are actionable and specific to this agent

## Context

This is the final step — a chance to catch issues before the user pushes the repo.
The compose.sh verification is critical because a broken manifest means the agent
can't assemble its system prompt at runtime. The next steps checklist bridges the
gap between this job (agent-space files only) and the full deployment (NixOS config,
secrets, systemd services).
