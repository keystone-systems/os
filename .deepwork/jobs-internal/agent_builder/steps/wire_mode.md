# Wire into Mode

## Objective

Add the new convention to the appropriate mode(s) in `manifests/modes.yaml` so that agents operating in those modes will load the convention.

## Task

Read the convention file and the current modes.yaml, determine which mode(s) the convention belongs in, and update the manifest.

### Process

1. **Read the convention file** to confirm its dotted name (from the H1 title).

2. **Read the review report** from the previous step. If it flagged issues, verify they have been addressed (the convention file should already reflect fixes from the quality review loop). If unresolved issues remain, note them but proceed — wiring can happen independently of content fixes.

3. **Read `manifests/modes.yaml`** to understand the current mode structure.

4. **Determine placement**

   Ask structured questions if the correct mode is ambiguous. Common mappings:
   - `ops.*` conventions → modes that involve infrastructure or tool operation
   - `code.*` conventions → modes that involve writing code in that language/framework
   - `biz.*` conventions → modes that involve business analysis or strategy

   If no existing mode is a good fit, ask the user whether to:
   - Add it to an existing mode anyway
   - Create a new mode for it
   - Skip wiring for now

5. **Update modes.yaml**

   Add the convention's dotted name to the `conventions` list of the selected mode(s). Maintain alphabetical order within the conventions list. Preserve all existing entries — do not remove or reorder other conventions.

6. **Validate the YAML**

   Ensure the updated file is valid YAML with correct indentation (2 spaces). Read it back after writing to confirm.

## Output Format

### updated_modes_yaml

The updated `manifests/modes.yaml` file.

**Example change** (before/after):

```yaml
# Before
modes:
  ops:
    roles:
      - operator
    conventions:
      - tool.bitwarden
      - tool.forgejo

# After
modes:
  ops:
    roles:
      - operator
    conventions:
      - tool.bitwarden
      - ops.docker        # newly added
      - tool.forgejo
```

7. **Sync to keystone repo**

   Conventions are maintained in both `.agents/conventions/` (agent-space submodule) and
   `.repos/ncrmro/keystone/conventions/` (upstream shared library). After creating a new
   convention, copy it to the keystone repo so both locations stay in sync:

   ```bash
   cp .agents/conventions/{domain}.{topic}.md .repos/ncrmro/keystone/conventions/
   ```

   Then commit in the keystone repo with a conventional commit message:

   ```bash
   cd .repos/ncrmro/keystone
   git add conventions/{domain}.{topic}.md
   git commit -m "feat(conventions): add {domain}.{topic}"
   ```

   If the convention was also wired into `archetypes.yaml`, sync that file too.

## Quality Criteria

- The convention is added to the mode(s) that logically match its domain and topic
- The modes.yaml file remains valid YAML with correct indentation
- Existing entries are preserved — no conventions removed or reordered beyond alphabetical insertion
- The dotted name in modes.yaml matches the convention file's H1 title exactly
- The convention file is synced to `.repos/ncrmro/keystone/conventions/`

## Context

This is the final step. Without wiring, the convention exists as a file but is never loaded into any agent's system prompt. Proper wiring ensures that agents operating in the relevant mode automatically follow the new convention.

Conventions currently live in two places:

- `.agents/conventions/` — the agent-space submodule (used by compose.sh)
- `.repos/ncrmro/keystone/conventions/` — the upstream shared library

Both must be kept in sync. The keystone repo is the canonical upstream source.
