# Draft Convention

## Objective

Write the convention file in RFC 2119 format, following the structure and rules established by the agents library.

## Task

Read the requirements summary from the previous step and produce the convention markdown file at the correct location (see shared job context for file location logic).

### Process

1. **Read requirements**

   Read the `requirements.md` file from the gather step. Extract the identity fields and all sections with their rules.

2. **Read 2-3 existing conventions** in the same domain for style reference. Match their tone, rule density, and section structure.

3. **Write the convention file**

   Follow the convention format rules from the shared job context. Additional writing guidance:
   - Keep rules concise — one sentence per rule where possible
   - End each rule with a period
   - Each rule should contain exactly one RFC 2119 keyword
   - Use `{placeholder}` syntax when referencing agent-specific values from `SOUL.md`

4. **Add golden example** (if requested in requirements.md)

   Append a `## Golden Example` section at the end of the convention. Show a realistic, minimal code or config snippet that demonstrates the rules in practice. Annotate with comments pointing back to rule numbers where helpful.

5. **Self-check** before completing:
   - All rules from requirements.md are covered
   - Style is consistent with the existing conventions you read in step 2
   - No hardcoded agent-specific values

## Output Format

### convention_file

The convention markdown file written to its final path.

**Example** (showing the expected structure):

```markdown
# Convention: Docker (ops.docker)

## Images

1. Base images MUST use pinned versions, not `latest`.
2. Multi-stage builds SHOULD be used to minimize image size.

## Compose

3. Services MUST define health checks.
4. Volumes SHOULD be named, not anonymous.
```

## Quality Criteria

- Convention format rules from the shared job context are followed exactly
- All rules from requirements.md are addressed
- Style is consistent with existing conventions in the same domain
- No hardcoded agent-specific values

## Context

This step produces the actual convention file that will live in the shared agents library. It must be format-perfect because other tools (compose.sh, mode manifests) depend on the naming and structure conventions.
