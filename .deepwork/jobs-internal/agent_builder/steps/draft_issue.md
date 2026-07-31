# Draft Issue

## Objective

Draft a GitHub issue for the admin's nixos-config repo (ncrmro/keystone) documenting an infrastructure problem that the agent cannot fix itself.

## Inputs

- `issue_description` — description of the infrastructure problem from the user or from a doctor workflow diagnosis

## Task

### 1. Gather issue context

If the description is vague, ask structured questions to clarify:

- Which agent is affected?
- What service or component is broken?
- What error message or symptom was observed?
- When did the problem start?
- Is the agent partially operational or fully broken?

If a doctor workflow was recently run, read the diagnosis and prescription files from `.deepwork/tmp/` for evidence.

### 2. Determine issue category

Classify the issue to select the right label:

| Category            | Label    | Examples                                              |
| ------------------- | -------- | ----------------------------------------------------- |
| NixOS agent config  | `agent`  | Missing timer, wrong schedule, service unit error     |
| Secrets/credentials | `agenix` | Missing SSH key secret, mail password not provisioned |
| Nix store/packages  | `nix`    | Permission denied on store path, missing package      |
| Infrastructure      | `infra`  | DNS, firewall, service down                           |

### 3. Draft the issue

Write `issue_draft.md` with the complete issue ready to file.

## Output Format

Write `issue_draft.md`:

```markdown
# Issue Draft

## Metadata

- **Repo:** ncrmro/keystone
- **Assignee:** ncrmro
- **Labels:** {comma-separated labels from category above}
- **Title:** {concise title: "[agent-{name}] {problem summary}"}

## Body

### Problem

{1-2 sentences describing what's wrong}

### Affected Agent

- **Agent:** agent-{name}
- **Service:** {timer/service name or component}
- **Status:** {operational / degraded / down}

### Evidence

{Exact error messages, log lines, or status output. Use code blocks.}
```

{error output}

```

### Expected Behavior

{What should happen instead}

### Suggested Fix

{If known — e.g., "regenerate store path", "add agenix secret for agent-luce"}

### Context

{Any additional context: when it started, what changed, link to doctor output if available}
```

## Quality Criteria

- The issue title clearly states the problem and affected agent/component
- The issue body includes the agent name, affected service, error evidence, and expected vs actual behavior
- The draft specifies ncrmro as assignee
- Evidence includes actual error output, not paraphrased descriptions
