# Prescribe Fixes

## Objective

Produce an ordered list of actionable fix commands for each diagnosed issue. Fixes should be safe, reversible where possible, and include verification steps.

## Inputs

- `diagnosis.md` from `diagnose` — root cause analysis with severity and affected components

## Task

### 1. Order fixes by dependency and severity

- Fix upstream issues first (e.g., fix SSH keys before addressing notes-sync failures)
- Critical issues before warnings
- Quick wins before complex fixes

### 2. Write fix actions

For each diagnosed issue, produce:

- The exact commands to run (using `agentctl` patterns from common job info)
- What the commands do and why
- Expected output after the fix
- A verification command to confirm the fix worked
- Rollback instructions if the fix makes things worse

### 3. Apply fix patterns by category

For each failure category from the diagnosis, write the specific fix+verify+rollback triple:

- **Auth failures** — re-authenticate the specific service, verify with status command, note dependent services
- **Git/sync failures** — resolve conflicts or reset state, verify clean working tree
- **Lock contention** — identify and clear stale locks, restart service
- **Timer issues** — restart or re-enable, verify active state and next trigger
- **Config/YAML errors** — validate and fix syntax, re-trigger the service
- **Missing prerequisites** — install or configure the missing component

### 4. Flag dangerous operations

Any fix that involves killing processes, git reset, or credential changes must include:

- A clear warning about what could go wrong
- Confirmation that the operator should verify before proceeding
- Rollback commands

## Output Format

Write `prescription.md`:

````markdown
# Prescription: agent-{name}

**Date:** {timestamp}
**Issues to fix:** {N}
**Estimated time:** {rough estimate}

## Fix Order

1. {Issue title} (critical)
2. {Issue title} (warning)
3. ...

## Fixes

### Fix 1: {Issue title}

**Addresses:** Issue {N} from diagnosis — {root cause summary}
**Risk:** low / medium / high

**Commands:**

```bash
{exact commands}
```
````

**Expected result:** {what should happen}

**Verify:**

```bash
{verification command}
```

**Rollback:**

```bash
{rollback commands if applicable}
```

---

### Fix 2: {title}

...

## Post-Fix Verification

After applying all fixes, verify overall agent health by checking all three timer statuses, CLI auth, and git state.

## No Fixes Needed

{If the agent is healthy: "Agent is healthy. No fixes required."}

```

## Quality Criteria

- Each fix includes exact shell commands that can be executed directly
- Destructive actions are flagged with warnings and have rollback instructions
- Each fix includes a verification command to confirm it worked
- Every diagnosed issue has a corresponding fix action
- Fixes are ordered by dependency (upstream fixes first) and severity

## Context

This is the final step of the doctor workflow. The prescription should be immediately actionable — the operator should be able to copy-paste commands and fix the agent. Avoid vague advice like "check the configuration" — always provide the specific command.
```
