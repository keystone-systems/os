# Write Findings Report

## Objective

Synthesize the spike's research and prototype results into a README.md with a clear conclusion, evidence, and next steps. Create a project symlink if a project was specified.

## Task

### Process

1. **Read all spike artifacts**
   - `spikes/[spike_name]/scope.md` — the question, success criteria, and project metadata
   - `spikes/[spike_name]/research.md` — gathered findings
   - `spikes/[spike_name]/prototype/` — code and results

2. **Evaluate the spike question**
   - Was the question answered? Fully, partially, or not at all?
   - Which success criteria were met?
   - What evidence supports the conclusion?

3. **Write the README.md**
   - Lead with the conclusion (answered/not answered/partially)
   - Reference specific research findings and prototype results
   - List concrete next steps

4. **Create project symlink (if applicable)**

   If scope.md specifies a project:

   ```bash
   # Create the project's spikes directory if it doesn't exist
   mkdir -p projects/[ProjectName]/spikes

   # Create a relative symlink (3 levels: projects/[Project]/spikes/ → repo root)
   ln -s ../../../spikes/[spike_name] projects/[ProjectName]/spikes/[spike_name]
   ```

   Use the project name as it appears in `projects/README.md` (matching the folder name under `projects/`). Verify the symlink resolves correctly.

## Output Format

### spikes/[spike_name]/README.md

```markdown
# Spike: [Short Title]

## Question

[The original spike question from scope.md]

## Conclusion

[One paragraph: Was the question answered? What's the recommendation?]

## Evidence

### Research Findings

- [Key finding 1 with source reference]
- [Key finding 2 with source reference]

### Prototype Results

- [What the prototype demonstrated]
- [What worked / what didn't]

## Recommendation

[Clear recommendation: proceed, don't proceed, or investigate further with specifics]

## Iteration Notes

[What to change in the next revision — design improvements, pain points, things that were annoying or fragile. Group by category (e.g., Power, Wiring, Enclosure, Software).]

## Next Steps

- [ ] [Concrete action item 1]
- [ ] [Concrete action item 2]
- [ ] [Concrete action item 3]

## Graduation Notes

[If prototype code will move to a repo, note what must change for production readiness. Prototypes should already use the project's established tooling, so graduation is about integration (registering parts, adding tests, wiring into CI) rather than rewriting from scratch.]
```

## Quality Criteria

- README.md summarizes the spike question and conclusion
- References research sources and prototype code where applicable
- Includes a clear recommendation or decision
- Lists concrete next steps
- If prototype produced code, includes graduation notes about what must be refactored when moving to a repo
- If a project was specified in scope.md, a symlink exists at `projects/[ProjectName]/spikes/[spike_name]` and resolves correctly (verify with `readlink -f` and confirm the target directory contains the spike files)

## Context

This is the primary deliverable of the spike. Someone reading only this README should understand what was investigated, what was found, and what to do next. The learn step will pull key takeaways from this report into the project file. The project symlink ensures the spike is discoverable from the project directory.
