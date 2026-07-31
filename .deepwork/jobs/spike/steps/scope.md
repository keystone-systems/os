# Define Spike Scope

## Objective

Define the spike question or hypothesis, validate the project exists, derive a spike name, and create a scope document with constraints and success criteria.

## Task

### Process

1. **Gather inputs using structured questions**
   - Ask structured questions to collect:
     - **project**: Which project is this spike for? (must exist in `projects/`)
     - **question**: What technical question or hypothesis are we investigating?
     - **context**: Any constraints, existing code, links, or background?
   - Read `projects/README.md` to validate the project exists
   - If the project doesn't exist, stop and inform the user

2. **Derive the spike name**
   - Convert the question into a short, descriptive slug (lowercase, hyphens)
   - Example: "Can we use SQLite for offline sync?" → `sqlite-offline-sync`
   - Confirm with the user if ambiguous

3. **Create the output directory**

   ```bash
   mkdir -p spikes/[spike_name]
   ```

4. **Ensure spike directory is properly configured** (if working in a zk notes repo)
   - `spikes/` is **git-tracked** — do NOT add it to `.gitignore`
   - Check for `.zk/config.toml` at or above the working directory
   - If found, verify `spikes` appears in the `ignore` list under `[note]`
   - If not present, add it: `ignore = ["spikes"]` (or append if the key exists)
   - Common build artifacts (`.direnv/`, `result`, `result-*`, `.venv/`) should be covered by the repo-level `.gitignore`

5. **Write scope.md**
   - Summarize the question, context, constraints, and what "done" looks like
   - Include the project name in the scope metadata for symlink creation in later steps

## Output Format

### spikes/[spike_name]/scope.md

```markdown
# Spike: [Short Title]

## Metadata

- **Project**: [project_name]

## Question

[The specific question or hypothesis to investigate]

## Context

[Background, constraints, relevant code references, links]

## Success Criteria

- [ ] [What constitutes a sufficient answer]
- [ ] [What prototype would prove feasibility, if applicable]

## Out of Scope

- [What we are NOT investigating in this spike]
```

## Quality Criteria

- Project validated against `projects/README.md`
- Question is specific and answerable (not vague)
- Question targets ONE approach or layer, not a survey of multiple options
- Success criteria are concrete and verifiable
- Spike name is a concise slug derived from the question
- Output directory created at `spikes/[spike_name]/`
- If working in a zk notes repo, `spikes` is in the `ignore` list in `.zk/config.toml`
- Scope includes project metadata for symlink creation in later steps

## Scope Narrowing Guidance

A spike should answer **one focused question**, not survey every possible approach. When the user's request implies multiple competing approaches (e.g., "try Gemini and GPT-4o and grid overlay and direct OCR"), help narrow scope:

1. **Ask**: "Which approach do you most want to validate?" or "What's the riskiest assumption?"
2. **Suggest splitting**: If multiple approaches truly need evaluation, propose separate spikes — one per approach — rather than a single broad spike that tries everything.
3. **Prefer depth over breadth**: A spike that deeply validates one approach (with a working prototype) is more useful than one that shallowly surveys five.
4. **Decompose layered questions**: If the question has independent layers (e.g., "Can we extract bounding boxes AND render highlights?"), each layer is its own spike. The first spike's conclusion feeds the next.

The user may override this guidance — they're the domain expert. But proactively suggesting a tighter scope prevents wasted effort and produces clearer conclusions.

## Context

This step gates the entire spike. A well-scoped question prevents wasted effort in later steps. The spike name becomes the folder name for all outputs.
