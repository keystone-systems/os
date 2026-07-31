# Gather Information

## Objective

Research the spike question using web search, codebase exploration, or both, and compile findings with source references.

## Task

### Process

1. **Read the scope document**
   - Read `spikes/[spike_name]/scope.md`
   - Understand the question, context, and success criteria

2. **Choose research approach**
   - **Web search**: For external libraries, APIs, patterns, or prior art
   - **Codebase exploration**: For understanding existing code, finding integration points
   - **Both**: When the question involves fitting external solutions into existing code

3. **Gather findings**
   - Consult at least 3 distinct sources
   - For each finding, record the source (URL, file path, or doc reference)
   - Note relevance to the spike question
   - Capture code snippets or examples where helpful

4. **Write research.md**
   - Organize findings by theme or approach
   - Include source references inline

## Output Format

### spikes/[spike_name]/research.md

```markdown
# Research: [Spike Title]

## Approach

[Brief description of research methods used: web search, codebase, both]

## Findings

### [Finding/Theme 1]

[Description of what was learned]

- Source: [URL or file path]

### [Finding/Theme 2]

[Description of what was learned]

- Source: [URL or file path]

### [Finding/Theme 3]

[Description of what was learned]

- Source: [URL or file path]

## Key Takeaways

- [Most important insight for answering the spike question]
- [Second insight]
- [Third insight]

## Open Questions

- [Anything that remains unclear and might need prototyping]
```

## Quality Criteria

- Directly addresses the question from scope.md
- At least 3 sources consulted (web, docs, or codebase)
- Each finding includes its source reference
- Key takeaways synthesize findings toward answering the spike question

## Context

Research feeds directly into the prototype step. Focus on findings that are actionable — things that inform what to build or try, not just background reading.
