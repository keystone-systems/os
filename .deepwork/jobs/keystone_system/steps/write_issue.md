# Write Issue

## Objective

Produce a GitHub issue for `ncrmro/keystone` whose body serves as the plan of
record: RFC 2119 requirements, user stories, affected modules, architecture
diagrams, and an implementation checklist that can later be mirrored in the PR.

## Task

Take the user's feature description and research the keystone codebase to
produce a well-structured issue. Ask structured questions if the description is
ambiguous.

### Process

1. **Understand the feature**
   - Parse the user's feature description
   - Ask structured questions to clarify scope, affected hosts, and integration points
   - Identify which existing keystone modules are involved

2. **Research the codebase**
   - Read the relevant modules in `modules/` to understand current architecture
   - Check if similar patterns exist (e.g., how other server services are structured)
   - Review `AGENTS.md` / `CLAUDE.md` for the module file tree and conventions
   - Look at existing specs in `specs/` for format reference — especially the most recent ones

3. **Draft the issue**
   - Follow the established format (see Output Format below)
   - Use RFC 2119 keywords: MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT, MAY, REQUIRED, OPTIONAL
   - Every requirement MUST be numbered under a temporary issue-local prefix such as `ISSUE-REQ-1`, `ISSUE-REQ-2`, or another unambiguous sequential format
   - Include at least one ASCII diagram showing module architecture or data flow
   - Identify all affected files in `modules/`, `packages/`, and `flake.nix`
   - Include a checklist of deliverables or implementation tasks derived from the requirements
   - The issue body MUST be sufficient for a future PR description to reuse directly

4. **Create the GitHub issue**
   - Choose a Conventional-Commit-style issue title: `type(scope): subject`
   - Use `gh issue create --repo ncrmro/keystone --title "..." --body-file <file>`
   - If a closely matching issue already exists, do NOT create a duplicate. Update the output file with the existing issue URL and explain why it matches.
   - Save the final issue body to a temporary local markdown file under `.deepwork/tmp/` before creating the issue, using a unique slug-based name so multiple issues in a session don't overwrite each other (e.g., `.deepwork/tmp/keystone-issue-agent-assets-fallback.md`). Do NOT place this draft under `.deepwork/jobs/`, because the local file is only a staging artifact for `gh issue create`.
   - After creation, append the created issue URL to the output file.

5. **Archive to notes (if notes are enabled)**
   - Check if `keystone.notes` is enabled: `nix eval ~/.keystone/repos/nixos-config#homeConfigurations.<user>.config.keystone.notes.enable --json 2>/dev/null`
   - If enabled, use `NOTES_DIR="${NOTES_DIR:-$HOME/notes}"` and create a brief note there via `zk --notebook-dir "$NOTES_DIR" new notes/ --title "keystone issue: <title>" --no-input`. Write the issue URL, one-paragraph summary, and the GitHub link. On Keystone systems, `NOTES_DIR` resolves to the configured notebook root (`~/notes` for human users).
   - If notes are not enabled or the command fails, skip silently.

## Output Format

### issue.md

Use a file path under `.deepwork/tmp/`, for example `.deepwork/tmp/keystone-issue.md`. The GitHub issue is the canonical source of record; the local markdown file is temporary workflow output.

```markdown
# <Conventional issue title>

<One paragraph summary of what this feature does and why it matters.>

## User stories

- As a [role], I want [capability] so that [benefit].
- As a [role], I want [capability] so that [benefit].

## Architecture
```

[ASCII diagram showing module relationships, data flow, or system topology]

```

## Affected Modules
- `modules/path/to/file.nix` — [what changes]
- `modules/path/to/other.nix` — [what changes]

## Requirements

### <Section Name>

**ISSUE-REQ-1** <Module/feature> MUST <do something specific>.

**ISSUE-REQ-2** <Module/feature> SHOULD <do something recommended>.

**ISSUE-REQ-3** When <condition>, <module> MUST <behavior>.

[Continue with numbered requirements grouped by logical section...]

## Deliverables

- [ ] Deliverable derived from the requirements
- [ ] Deliverable derived from the requirements

## Acceptance criteria

- [ ] Requirement coverage is complete
- [ ] Build/test/validation path is identified

## Issue metadata

- Repository: `ncrmro/keystone`
- Suggested labels: `<optional labels>`
- Created issue: `<issue URL after creation>`
```

## Quality Criteria

- Requirements use RFC 2119 keywords correctly and consistently
- Each requirement is numbered and specific enough to verify
- At least one ASCII diagram illustrates the architecture
- All affected keystone modules and files are identified
- A user stories section explains why this feature matters for the relevant actors
- The issue body can be reused as the foundation for the eventual PR description
- A GitHub issue was created or an existing matching issue was linked with justification

## Context

Keystone issues are the plan of record for implementation. The issue body
should contain the requirements and checklist that will later be reflected in
the PR description. Avoid creating a standalone `specs/REQ-XXX/...` file unless
the user explicitly asked for a committed spec in addition to the issue.
