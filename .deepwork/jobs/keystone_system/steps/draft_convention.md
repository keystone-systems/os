# Draft Convention

## Objective

Take the user's topic description (and optionally their pre-written draft) and produce a complete convention document in the keystone RFC 2119 format, ready for cross-referencing against existing conventions.

## Task

Gather requirements about the convention topic, study existing conventions for format consistency, and write a well-structured convention draft. Ask structured questions to clarify the scope and rule set.

### Process

1. **Parse the user's input**
   - The `convention_topic` input may contain just a topic name ("shell scripts") or a full draft with proposed rules
   - If the user provided a draft, extract the proposed rules and identify gaps
   - If the user provided only a topic, proceed to structured questioning

2. **Determine the convention identity**

   Ask structured questions to pin down:
   - **Domain prefix**: `code` (language/style), `process` (operational procedure), `tool` (CLI/tool manual), or `os` (system requirements)
   - **Topic slug**: lowercase-hyphenated (e.g., `shell-scripts`, `nix-devshell`)
   - **Display name**: human-readable (e.g., "Shell Scripts", "Nix Dev Shell")
   - The resulting filename is `{prefix}.{topic}.md` and dotted name is `{prefix}.{topic}`

3. **Study existing conventions**
   - Read `conventions/AGENTS.md` for format rules
   - Read 2-3 existing conventions in `conventions/` that are similar in domain to understand structure and level of detail
   - Pay attention to: H1 title format, rule numbering, section organization, golden examples

4. **Gather the rules**

   Ask structured questions to understand:
   - What are the MUST rules? (hard requirements, violations are bugs)
   - What are the SHOULD rules? (strong recommendations, exceptions require justification)
   - What are the MAY rules? (optional practices, mentioned for awareness)
   - Group rules into logical sections (e.g., "Execution Environment", "Static Analysis", "Style")

   If the user provided a draft, review it against these categories and ask about gaps.

5. **Ask about a golden example**
   - If the convention covers a pattern with non-trivial application, propose including a golden example section
   - The golden example should show the rules applied to a realistic scenario

6. **Write the convention draft**
   - Follow the exact format from `conventions/AGENTS.md`
   - Write the file to `.deepwork/tmp/convention_draft.md` (NOT to `conventions/` yet — that happens in the apply step)

## Output Format

### convention_draft.md

The drafted convention file. Written to `.deepwork/tmp/convention_draft.md`.

**Structure**:

```markdown
<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: {Display Name} ({prefix.topic})

{One-paragraph description of what this convention covers and why it exists.}

## {Section 1 Name}

1. {Subject} MUST {do something specific}.
2. {Subject} SHOULD {do something recommended}.
3. {Subject} MUST NOT {do something prohibited}.

## {Section 2 Name}

4. {Subject} MUST {rule continues from previous section numbering}.
5. {Subject} MAY {optional practice}.

## Golden Example

{Realistic scenario demonstrating the rules applied together. Include code blocks
where appropriate. This section is optional but recommended for non-trivial conventions.}
```

**Filled example** (for a hypothetical `code.shell-scripts` convention):

```markdown
<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Shell Scripts (code.shell-scripts)

Standards for authoring fault-tolerant, succinct shell scripts within keystone
and related repositories.

## Execution Environment

1. All bash scripts MUST begin with `#!/usr/bin/env bash` followed by `set -euo pipefail`.
2. Scripts MUST use `#!/usr/bin/env bash` rather than hardcoded paths like `#!/bin/bash`.

## Static Analysis

3. All scripts MUST pass ShellCheck with zero warnings or errors.
4. If a ShellCheck rule must be bypassed, it SHALL be disabled inline with a justification comment.

## Golden Example

End-to-end example of a script following all rules:

    #!/usr/bin/env bash
    set -euo pipefail

    main() {
        local target="${1:?Usage: script.sh <target>}"
        echo "Processing ${target}"
    }

    main "$@"
```

## Quality Criteria

- The convention follows the required H1 title format: `# Convention: {Display Name} ({prefix.name})`
- Rules are numbered consecutively across all sections
- Every rule uses at least one RFC 2119 keyword (MUST, SHOULD, MAY, etc.)
- Rules are specific and actionable — no vague aspirational statements
- Rules are grouped into coherent sections with clear H2 headings
- If the convention covers a non-trivial pattern, a golden example section is included
- The file is written to `.deepwork/tmp/convention_draft.md`, NOT directly to `conventions/`

## Context

This is the first step in the convention workflow. The draft produced here will be cross-referenced against all existing conventions in the next step to identify overlaps and redundancies. Writing to a temp location first allows the cross-reference step to analyze the draft before any existing files are modified. The convention identity (prefix, topic, display name) chosen here determines the final filename in `conventions/`.
