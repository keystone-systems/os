# Cross-Reference

## Objective

Scan every existing convention in `conventions/` to identify overlaps, redundancies, and cross-reference opportunities with the new convention draft. Produce a deduplication plan before any files are modified.

## Task

Read the convention draft from the previous step and systematically compare it against all existing conventions. For each overlap found, determine the correct resolution: keep in the new convention, keep in the existing one, merge, or add a cross-reference.

### Process

1. **Read the convention draft**
   - Read `.deepwork/tmp/convention_draft.md` from the draft step
   - Extract all rules and their RFC 2119 keywords
   - Note the convention's prefix and topic

2. **Inventory all existing conventions**
   - List all files in `conventions/` matching `*.md` (excluding `AGENTS.md` and `AGENTS_TEMPLATE.md`)
   - Read `conventions/archetypes.yaml` to understand how each convention is currently wired

3. **Systematic comparison**

   For each existing convention:
   - Read the file
   - Compare rule-by-rule against the new draft
   - Flag any of these overlap types:

   | Overlap Type              | Description                                                       | Example                                                                   |
   | ------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
   | **Duplicate**             | Same rule exists in both, word-for-word or near-identical         | Both say "scripts MUST use strict mode"                                   |
   | **Subsume**               | New convention's rule is a superset of an existing rule           | New has detailed ShellCheck rules; existing has a one-liner about linting |
   | **Conflict**              | Rules contradict each other                                       | New says MUST; existing says SHOULD for same behavior                     |
   | **Cross-ref opportunity** | Rules are related but complementary — should reference each other | New covers shell style; existing covers Nix `writeShellApplication`       |

4. **Build the deduplication plan**

   For each overlap found, propose a resolution:
   - **Keep in new**: The new convention is the authoritative home for this rule. Remove from existing.
   - **Keep in existing**: The existing convention is the better home. Remove from draft.
   - **Merge**: Combine the two rules into a stronger version in one location.
   - **Add cross-reference**: Add a "see `{prefix.topic}` for X" note in both directions.
   - **No action**: Overlap is superficial; both rules serve different contexts.

5. **Check for orphaned references**
   - If removing rules from an existing convention, verify no other conventions or archetypes reference those specific rule numbers
   - If an existing convention would become empty or trivially small after dedup, propose folding its remaining rules into another convention

## Output Format

### cross_reference_report.md

Written to `.deepwork/tmp/cross_reference_report.md`.

**Structure**:

```markdown
# Cross-Reference Report

## New Convention

- **File**: {prefix}.{topic}.md
- **Display Name**: {Display Name}
- **Rule Count**: {N}

## Conventions Scanned

| File                       | Rules | Overlaps Found |
| -------------------------- | ----- | -------------- |
| process.version-control.md | 12    | 2              |
| tool.nix-devshell.md       | 21    | 0              |
| ...                        | ...   | ...            |

## Overlaps

### Overlap 1: {Brief description}

- **New draft rule**: #{N} — "{rule text}"
- **Existing convention**: {filename} rule #{M} — "{rule text}"
- **Type**: {Duplicate|Subsume|Conflict|Cross-ref}
- **Resolution**: {Keep in new|Keep in existing|Merge|Add cross-reference|No action}
- **Rationale**: {Why this resolution}

### Overlap 2: {Brief description}

[repeat for each overlap]

## Proposed Changes

### Files to Modify

- `conventions/{existing}.md` — Remove rules #{M}, #{N}; add cross-reference to {new}
- `conventions/{other}.md` — Add cross-reference to {new} in section X

### Files to Create

- `conventions/{prefix}.{topic}.md` — The new convention (from draft, minus removed overlaps)

### Files to Delete

- (none, or list conventions that become empty after dedup)

### Archetypes Changes

- (what needs to change in archetypes.yaml — to be confirmed with user in the next step)

## No Overlaps Found With

[List conventions that were checked but had no overlaps — confirms thorough scan]
```

## Quality Criteria

- Every existing convention in `conventions/` was checked — the report lists all files scanned
- Identified overlaps cite specific rule numbers from both the draft and existing conventions
- Each overlap has a concrete resolution with rationale
- The proposed changes section is actionable — specific files, specific rules, specific edits
- No conventions were skipped in the scan

## Context

This step is the key differentiator of the convention workflow — it prevents rule duplication across the convention corpus. Without this step, conventions accumulate redundant rules that confuse agents and create conflicting guidance. The dedup plan produced here is consumed by the apply step, which makes the actual file changes. No files are modified in this step — it is analysis only.
