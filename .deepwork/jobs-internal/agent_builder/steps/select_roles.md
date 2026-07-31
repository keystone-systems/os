# Select Roles and Conventions

## Objective

Present the available roles and conventions from the shared agents library (ncrmro/agents)
and help the user select which ones apply to this agent. Produce a manifest (modes.yaml)
mapping agent modes to shared roles and conventions.

## Task

Read the shared library's roles and conventions, present them to the user, and build
a manifest file. If the user needs roles or conventions that don't exist yet, capture
those as recommendations.

### Process

1. **Read available roles**

   Scan `roles/*.md` in the ncrmro/agents repo. For each role, extract:
   - Filename (without `.md`)
   - The H1 title
   - The description paragraph after the title

   Present these as a list to the user.

2. **Read available conventions**

   Scan `conventions/*.md` in the ncrmro/agents repo. For each convention, extract:
   - Filename (without `.md`)
   - The H1 title (which includes the dotted name)

   Group by domain prefix (`biz.`, `code.`, `ops.`).

3. **Ask structured questions about modes**

   Based on the agent's purpose from SOUL.md, suggest relevant modes. Use the
   AskUserQuestion tool with multiSelect to let the user pick roles per mode.

   Example for an engineering agent:
   - `architecture` mode → roles: architect; conventions: tool.typescript, tool.nix
   - `implementation` mode → roles: software-engineer; conventions: tool.typescript, process.version-control
   - `code-review` mode → roles: code-reviewer; conventions: tool.typescript, process.pull-request

   Example for a business agent:
   - `business-analysis` mode → roles: business-analyst; conventions: process.competitive-analysis
   - `project-planning` mode → roles: project-lead, task-decomposer; conventions: []

4. **Check for gaps**

   Ask: "Are there any capabilities this agent needs that aren't covered by the
   existing roles or conventions?" If yes, document these as recommendations for
   new content to add to the shared library.

5. **Generate manifest**

   Write the manifest to `.repos/{owner}/{repo}/manifests/modes.yaml`.

## Output Format

### manifests/modes.yaml

```yaml
agents_repo: ../.agents

defaults:
  shared:
    - rfc2119-preamble.md
    - output-format-rules.md

modes:
  architecture:
    roles:
      - architect
    conventions:
      - tool.typescript
      - tool.nix
  implementation:
    roles:
      - software-engineer
    conventions:
      - tool.typescript
      - process.version-control
  code-review:
    roles:
      - code-reviewer
    conventions:
      - tool.typescript
      - process.pull-request
```

### new_content_recommendations.md (optional)

```markdown
# Recommended New Content for ncrmro/agents

## New Roles Needed

- **{role_name}**: {description of what this role would do}

## New Conventions Needed

- **{domain}.{topic}**: {description of what this convention would cover}

## Rationale

{Why existing roles/conventions don't cover this agent's needs}
```

## Quality Criteria

- All role and convention filenames in the manifest correspond to existing files in ncrmro/agents
- The manifest declares `defaults.shared` with `rfc2119-preamble.md` and `output-format-rules.md`
- At least one mode is defined with at least one role
- `agents_repo` path is `../.agents` (relative from manifests/ to .agents/)
- If the user identified gaps, a recommendations file is created

## Context

The manifest is how the agent's system prompt gets composed at runtime. `compose.sh`
reads this file and assembles: shared fragments → role templates → convention docs.
The `agents_repo` path must be relative from the manifest's location to the submodule
directory. Getting this path wrong means `compose.sh` can't find the shared content.
