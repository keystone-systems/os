# Review Convention

## Objective

Check the newly drafted convention for duplication, conflicts, or inconsistencies with existing conventions in the library.

## Task

Read the new convention file and compare it against related existing conventions to ensure it adds value without creating confusion or contradictions.

### Process

1. **Read the new convention file** from the draft step.

2. **Identify related conventions**

   List all existing conventions in `.agents/conventions/` (or `conventions/` if in the agents repo). Identify the ones most likely to overlap:
   - Same domain (e.g., all `ops.*` conventions if the new one is `ops.*`)
   - Same topic area (e.g., if the new convention is about Docker, check `tool.nix-devshell` for container-related rules)

3. **Read the related conventions** (at least 2-3 of the most relevant ones).

4. **Check for issues**
   - **Rule duplication**: Does any rule in the new convention duplicate a rule already in an existing convention? If so, note which convention and rule number.
   - **Contradictions**: Does any rule contradict an existing rule? (e.g., new convention says "MUST use X" but existing says "MUST NOT use X")
   - **Scope overlap**: Does the new convention cover territory that another convention already owns? If so, is the boundary clear?
   - **Missing cross-references**: Should the new convention reference another convention for related concerns? (e.g., a `code.go` convention might reference `process.pull-request` for PR practices)

5. **Write the review report**

   If issues are found, provide specific remediation for each. If no issues, confirm the convention is clean.

## Output Format

### review_report.md

A markdown report on the review findings.

**Structure (clean)**:

```markdown
# Convention Review: {dotted.name}

## Summary

No conflicts or duplication found. The convention is ready for use.

## Conventions Checked

- {dotted.name.1} — no overlap
- {dotted.name.2} — no overlap

## Recommendation

Proceed to wire the convention into modes.yaml.
```

**Structure (issues found)**:

```markdown
# Convention Review: {dotted.name}

## Summary

Found {N} issue(s) that should be addressed before wiring.

## Issues

### 1. {Issue title}

- **Type**: duplication | contradiction | scope overlap | missing cross-reference
- **Related convention**: {dotted.name}
- **Details**: {Specific description}
- **Remediation**: {What to change}

## Conventions Checked

- {dotted.name.1} — {overlap noted / no overlap}
- {dotted.name.2} — {overlap noted / no overlap}

## Recommendation

{Fix the issues above before proceeding / Proceed with minor notes}
```

## Quality Criteria

- At least the most related existing conventions were checked (same domain + any topically related)
- Any issues found include specific remediation suggestions
- The report clearly states whether it is safe to proceed

## Context

This review prevents the convention library from accumulating conflicting or redundant rules over time. A clean library is easier for agents to follow and for compose.sh to assemble into coherent system prompts.
