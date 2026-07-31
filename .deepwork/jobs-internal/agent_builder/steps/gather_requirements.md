# Gather Requirements

## Objective

Collect all the information needed to write a new convention document: the domain, topic, display name, and the specific rules to codify.

## Task

Ask structured questions to understand what convention the user wants to create, then produce a requirements summary that the next step can use to draft the convention file.

### Process

1. **Determine the convention identity**

   The user provides a `convention_topic` input (e.g., "Docker", "Go", "Slack"). Use this as a starting point, then ask structured questions to pin down the domain, topic slug, display name, and dotted name. Refer to the convention format rules in the shared job context for naming conventions.

2. **Inventory existing conventions**

   Read the list of files in `.agents/conventions/` (or `conventions/` if in the agents repo) and check whether a convention for this topic already exists. If it does, ask the user whether they want to update the existing one or create a new, more specific variant.

3. **Gather the rules**

   Ask structured questions to understand what rules should be in the convention:
   - What are the key practices or constraints for this tool/language/process?
   - Are there things agents MUST do? MUST NOT do?
   - Are there recommended practices (SHOULD) vs. optional ones (MAY)?
   - Group rules into logical sections (e.g., "Authentication", "Usage", "Style")

   If the user is unsure, suggest common sections based on the domain:
   - `ops.*`: Authentication, Configuration, Usage, Error Handling
   - `code.*`: Type Safety, Style, Imports, Error Handling, Testing
   - `biz.*`: Process, Deliverables, Quality, Stakeholders

4. **Ask about a golden example**

   If the convention covers an architectural pattern or a tool with a non-trivial usage flow, ask the user whether they want a "Golden Example" section showing the rules applied to a real file or component. This is optional but valuable for conventions like MVC controllers, API route handlers, or data model definitions.

5. **Confirm the requirements**

   Summarize what you've gathered and confirm with the user before writing the output file.

## Output Format

### requirements.md

A markdown file summarizing the convention to be created.

**Structure**:

```markdown
# Convention Requirements: {Display Name}

## Identity

- **Domain**: {ops|code|biz}
- **Topic**: {topic-slug}
- **Dotted name**: {domain}.{topic}
- **Display name**: {Display Name}
- **Filename**: {domain}.{topic}.md

## Sections and Rules

### {Section 1 Name}

1. {Rule description with RFC 2119 keyword}
2. {Rule description with RFC 2119 keyword}

### {Section 2 Name}

3. {Rule description with RFC 2119 keyword}
4. {Rule description with RFC 2119 keyword}

## Golden Example

{yes/no — if yes, describe what the example should show}

## Notes

{Any additional context, edge cases, or references the user mentioned}
```

**Example** (filled in):

```markdown
# Convention Requirements: Docker

## Identity

- **Domain**: ops
- **Topic**: docker
- **Dotted name**: ops.docker
- **Display name**: Docker
- **Filename**: ops.docker.md

## Sections and Rules

### Images

1. Base images MUST use pinned versions, not `latest`.
2. Multi-stage builds SHOULD be used to minimize image size.

### Compose

3. Services MUST define health checks.
4. Volumes SHOULD be named, not anonymous.

## Golden Example

Yes — show a minimal Dockerfile following these rules.

## Notes

Focus on development workflows. Production deployment conventions are out of scope.
```

## Quality Criteria

- Convention identity is fully specified (domain, topic, dotted name, display name, filename)
- Rules use RFC 2119 keywords (MUST, SHOULD, MAY, etc.)
- Rules are grouped into logical sections
- No overlap with existing conventions was confirmed
- User has confirmed the requirements before output was written

## Context

This is the first step in the convention creation workflow. The requirements gathered here directly drive the draft in the next step. Incomplete or vague requirements will produce a weak convention, so invest the time to get specifics from the user.
