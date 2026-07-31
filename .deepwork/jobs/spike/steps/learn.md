# Capture Learnings

## Objective

Update the project file with key takeaways from the spike, and — when a zk notes repo is present — create a report note and an ADR capturing the outcome.

## Task

### Process

1. **Read the spike report**
   - Read `spikes/[spike_name]/README.md`
   - Extract the conclusion, recommendation, and next steps

2. **Read the project file**
   - Read `projects/[project]/[project].md` (or the project's main file)
   - Understand where spike references belong in the existing structure

3. **Update the project file**
   - Add a spike reference under an appropriate section (e.g., "## Spikes" or "## Research")
   - Include: spike name, date, one-line conclusion, link to spike README, and next steps
   - Next steps belong **under the spike entry**, not in a separate global section
   - Link format: `[spike_name]([project_folder]/spikes/[spike_name]/README.md)`
     (relative to the project `.md` file; resolves via symlink `projects/[project]/spikes/[spike_name]/` → `../../../spikes/[spike_name]`)

4. **Create zk notes** (if working in a zk notes repo)
   - Check for a `.zk/` directory at or above the working directory — skip this step if absent

   **4a. Report note** — spike summary in `reports/`

   ```bash
   zk new --title "Spike: [spike_name]" --no-input --print-path reports/
   ```

   Edit the created file to fill in:
   - `report_kind: spike`
   - `source_ref: spikes/[spike_name]/README.md`
   - `tags`: `[report/spike, source/deepwork]` plus `project/<slug>` if a project was scoped
   - Body: one-paragraph summary of the question, conclusion, and recommendation; link to `spikes/[spike_name]/README.md`

   **4b. Decision note (ADR)** — only if the spike concluded with a clear architectural decision

   ```bash
   zk new --title "[Decision Title]" --no-input --print-path decisions/
   ```

   Fill in the template sections:
   - **Context**: spike question and motivation
   - **Decision**: what was decided
   - **Consequences**: trade-offs and next steps
   - **Links**: link to the report note and `spikes/[spike_name]/README.md`
   - Add `project/<slug>` tag if a project was scoped

   **4c. Link from hub** — if a project hub note exists (`index/` with tag `project/<slug>` and `status/active`), add links to both the report note and ADR in the hub's report ledger section

   Run `zk index` after all notes are created.

## Output Format

### projects/[project]/[project].md

Add a section like this (create the Spikes section if it doesn't exist):

```markdown
## Spikes

### [spike_name] (YYYY-MM-DD)

**Conclusion**: [One-sentence summary of the finding]
**Link**: [spike_name]([project_folder]/spikes/[spike_name]/README.md)

- [ ] [Next step 1]
- [ ] [Next step 2]
```

**Important**: Next steps are scoped per spike, nested under the spike heading — do NOT add them to a separate global "Next Steps" section.

## Quality Criteria

- Project file updated with spike reference including date and conclusion
- Link to spike README is correct relative path (resolves via symlink)
- Entry is concise (not duplicating the full report)
- Next steps added under the spike entry if applicable
- If working in a zk notes repo: report note exists in `reports/` with `type: report`, `report_kind: spike`, and project tag if applicable; ADR exists in `decisions/` if spike concluded with a clear architectural decision

## Graduation Warning

If the spike produced prototype code that will graduate to a repo, the project file entry should note what integration work remains. Prototypes already use the project's established tooling (per the prototype step), so graduation is about registering parts, adding tests, wiring into CI, and production hardening — not a full rewrite.

## Context

This closes the loop — the spike's findings are captured where they'll be found during regular project work. Without this step, spikes get forgotten in subdirectories.
