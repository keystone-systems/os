# Apply Convention

## Objective

Execute the deduplication plan from the cross-reference step: write the final convention file, update or remove redundant rules in existing conventions, add cross-references, and wire the new convention into `archetypes.yaml`.

## Task

Read both the convention draft and the cross-reference report, then make all the file changes. Ask structured questions to determine which archetypes and roles should include the new convention.

### Process

1. **Read inputs**
   - Read `.deepwork/tmp/convention_draft.md` (the draft)
   - Read `.deepwork/tmp/cross_reference_report.md` (the dedup plan)
   - Read `conventions/archetypes.yaml` (current wiring)

2. **Apply draft modifications**
   - If the cross-reference report says to remove rules from the draft (keep in existing), remove them
   - If the report says to merge rules, write the merged version
   - Renumber rules if removals create gaps — rules MUST be numbered consecutively within each section

3. **Write the final convention file**
   - Write to `conventions/{prefix}.{topic}.md`
   - Verify the H1 title matches the format: `# Convention: {Display Name} ({prefix.topic})`
   - Verify the RFC 2119 comment header is present

4. **Update existing conventions**
   - For each "Remove from existing" action in the report:
     - Edit the existing convention file
     - Remove the specified rules
     - Renumber remaining rules to stay consecutive
     - Add a cross-reference comment where the removed rules were, e.g., "See `{prefix.topic}` for {topic} rules."
   - For each "Add cross-reference" action:
     - Add a brief note in the relevant section pointing to the other convention

5. **Handle empty or trivially small conventions**
   - If an existing convention is reduced to fewer than 3 rules after dedup, consider folding its remaining rules into a related convention
   - If folding, update all references in `archetypes.yaml` accordingly

6. **Wire into archetypes**

   Before asking, read `conventions/archetypes.yaml` and present the user with context:
   - List which archetypes exist and their descriptions
   - Show which roles within each archetype already reference related conventions (e.g., if the new convention is about shell scripts, show which roles already have `tool.nix-devshell` or `tool.nix`)
   - This helps the user make an informed decision about placement

   Ask structured questions to determine:
   - Which archetypes should include this convention? (engineer, product, both, neither)
   - Should it be **inlined** (always in context — use for critical operational rules) or **referenced** (on-demand — use for manuals and guides)?
   - Should it be added to any specific roles within the archetype?

   Then edit `conventions/archetypes.yaml`:
   - Add to `inlined_conventions` or `referenced_conventions` as determined
   - If adding to roles, add to the `conventions` list under the appropriate roles

7. **Verify consistency**
   - Read the modified `archetypes.yaml` to confirm valid YAML
   - Spot-check that cross-references are bidirectional (if A references B, B references A)
   - Confirm no rule numbers are duplicated or skipped in any modified file

## Output Format

### change_summary.md

Written to `.deepwork/tmp/change_summary.md`.

**Structure**:

```markdown
# Convention Change Summary

## Convention Created

- **File**: `conventions/{prefix}.{topic}.md`
- **Display Name**: {Display Name}
- **Final Rule Count**: {N}

## Existing Conventions Modified

### `conventions/{existing}.md`

- **Rules removed**: #{M}, #{N} (moved to new convention)
- **Cross-reference added**: "See `{prefix.topic}` for {topic}."
- **Rules renumbered**: Yes/No

[Repeat for each modified file]

## Existing Conventions Deleted

- (none, or list with rationale)

## Archetypes Updated

### {archetype_name}

- **Added to**: {inlined_conventions|referenced_conventions}
- **Added to roles**: {role1, role2} (or "none")

[Repeat for each archetype]

## Files Changed (for commit)

- `conventions/{prefix}.{topic}.md` (created)
- `conventions/{existing}.md` (modified)
- `conventions/archetypes.yaml` (modified)
```

## Quality Criteria

- All redundancies from the cross-reference report are resolved — no duplicate rules remain across conventions
- The new convention appears in the correct archetypes (inlined or referenced) and roles
- Cross-references between conventions are bidirectional and accurate
- Rules removed from existing conventions were moved to the new convention or confirmed truly redundant — nothing silently dropped
- All modified convention files have consecutive rule numbering with no gaps
- `archetypes.yaml` is valid YAML after edits

## Context

This is the action step — it makes all the actual file changes. The draft and cross-reference steps were analysis; this step commits to the changes. After this step, the convention corpus should be internally consistent with no duplicated rules and proper cross-references. The next step (commit) will commit all these changes to main.
