# Write Press Release

## Objective

Draft a working-backwards press release following the `process.press-release` convention, using the structured context brief as source material.

## Task

Read the context brief from the previous step and the conventions at `.agents/conventions/process.press-release.md` and `.agents/roles/press-release-writer.md`. Then write a complete press release that announces the feature as if it has already launched.

### Process

1. **Read the conventions**
   - Read `.agents/conventions/process.press-release.md` for structural rules
   - Read `.agents/roles/press-release-writer.md` for tone and behavior guidance
   - These are the authoritative source — follow them precisely

2. **Read the context brief**
   - Review `context_brief.md` from the gather_context step
   - Identify: customer, problem, solution, key claims, quote direction, CTA

3. **Write the headline**
   - State the customer benefit in plain language
   - Do NOT lead with the feature name or technical capability
   - Bad: "Project X Launches New S3-Compatible Storage API"
   - Good: "Developers Now Store and Retrieve Any Amount of Data Without Managing Servers"

4. **Write the opening paragraph**
   - Answer: who is the customer, what can they now do, why does it matter
   - Present tense, as if the product is launched
   - Do NOT include a city dateline (e.g., "San Francisco, CA —") unless the user explicitly requests one

5. **Draft the body using the internal structure**
   Use the **current state → why this → how → what** flow as an internal organizing device while drafting. These labels help ensure the arc is complete. Do NOT carry these labels into the published press release — they are for the agent's internal draft only, not for the audience.
   - **Current state**: What the customer struggles with today (the problem)
   - **Why this**: Why this matters now — the motivation for building it
   - **How**: How the product solves the problem (customer outcomes, not technical implementation)
   - **What**: Key features at a high level, staying within the claims from the context brief
   - Keep each section to 1-3 sentences. Be direct. No filler.

   When converting to the audience-facing press release (step 12), rewrite these sections as flowing narrative paragraphs without labels. The published press release is for readers, not for agents.

6. **Include ASCII art mockup**
   - If the product has a UI (TUI, GUI, CLI output, web page), include an ASCII art mockup showing the key interaction
   - The mockup should show the product in use with realistic data — not empty states
   - Use box-drawing characters (`┌ ─ ┐ │ └ ┘ ├ ┤ ┬ ┴ ┼`) for structure
   - Place the mockup between the body and the call to action
   - If the product has no visual interface (e.g., a library or API), omit the mockup

7. **Write the call to action**
   - How the customer gets started
   - Be specific — a URL, a signup flow, a command

8. **Optional: Write FAQ**
   - Anticipate 2-3 objections or questions
   - Keep answers concise

9. **Final check**
   - Verify word count is 300-500 words (aim for concise)
   - Verify present tense throughout
   - Verify no jargon, internal metrics, or implementation details
   - Verify claims match the context brief's key claims
   - Verify NO fictional customer quotes are included
   - Verify NO city dateline is included (unless user requested one)
   - Write the local workflow artifacts under `.deepwork/tmp/`, not ad hoc `/tmp/` paths
   - Use unique artifact filenames derived from the project slug or headline slug so repeated runs do not overwrite each other

10. **Stage the local outputs**
    - Derive a stable unique basename from the project slug when available, otherwise from the headline slug
    - Write the press release draft to `.deepwork/tmp/<slug>-press-release.mdx`
    - Write the issue URL to `.deepwork/tmp/<slug>-press-release-issue-url.md`
    - These files are transient workflow artifacts for DeepWork output handoff

11. **Store in the configured notes dir (zk)**
    - Use `NOTES_DIR="${NOTES_DIR:-$HOME/notes}"`. On Keystone systems this resolves to the configured notebook root (`~/notes` for human users).
    - Create a permanent note in `$NOTES_DIR` using the project slug:
      ```bash
      NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
      zk --notebook-dir "$NOTES_DIR" new notes/ --title "<Headline>" --no-input --print-path \
        --extra project="<slug>"
      ```
    - Write the full press release content into the created note
    - Set the following frontmatter fields:
      - `type: note`
      - `project: <slug>`
      - `tags`: `project/<slug>`, `source/agent`, `source/deepwork`
      - `repo_ref`: `gh:<owner>/<repo>` or `fj:<owner>/<repo>` (the project's primary repo)
    - After the issue is created in step 12, update the note with:
      - `issue_ref: gh:<owner>/<repo>#<number>` (or `fj:` for Forgejo)
    - If a milestone exists or is created downstream, update the note with:
      - `milestone_ref: gh:<owner>/<repo>#<milestone_number>`
    - Link the note from the project's hub note in `$NOTES_DIR/index/` if one exists

12. **Publish the canonical copy**
    - After the press release file is written and passes the final check, create an issue on the project's repo
    - Use `gh issue create` (GitHub) or `fj issue create` (Forgejo) depending on where the project is hosted
    - The issue title MUST be `Press Release: <Product Label>` (e.g., "Press Release: KS Project Agent"). The product label is a short name for the feature or product, not the headline.
    - The issue body MUST be the **audience-facing press release** rendered inside a Markdown blockquote (`>` prefix on each content line)
    - The `>` blockquote is what readers see — it must be high-level narrative prose, NOT the internal `**Current state** / **Why this** / **How** / **What**` labeled structure. Convert the internal draft into flowing paragraphs before publishing.
    - Label the issue with `press-release` (create the label if it doesn't exist)
    - Record the **full URL** of the created issue in `.deepwork/tmp/<slug>-press-release-issue-url.md`
    - Update the zk note's `issue_ref` frontmatter field with the created issue URL
    - If the project repo already stores press releases as tracked content, publish the finalized draft there as a separate explicit step after the issue is created
    - If the project does not store press releases in-repo, keep `.deepwork/tmp/press_release.mdx` as the transient local artifact and treat the issue as the canonical published record

## Output Format

### press_release.mdx

The finished press release in MDX format. Write the local workflow artifact to a
unique path under `.deepwork/tmp/`, such as `.deepwork/tmp/keystone-project-agent-press-release.mdx`.

If the project already stores press releases in-repo, publish the finalized draft
to the project's designated directory, typically `posts/press_releases/`, as a
separate explicit publication step.

### zk note in the configured notes dir

A permanent note in the configured notes dir `notes/` containing the full press release content.
The note MUST include:
- `type: note`
- `project: <slug>`
- `tags`: `project/<slug>`, `source/agent`, `source/deepwork`
- `repo_ref`: normalized `gh:` or `fj:` repo reference
- `issue_ref`: set after the issue is created (e.g., `gh:<owner>/<repo>#42`)

Follow `process.notes` and `tool.zk-notes` for the authoritative tagging standard.

### press_release_issue_url.md

A single-line file at a unique path under `.deepwork/tmp/`, such as
`.deepwork/tmp/keystone-project-agent-press-release-issue-url.md`, containing the full
URL of the issue created for the press release (e.g.,
`https://github.com/owner/repo/issues/42`). This URL is required for traceability —
downstream workflows like `milestone/setup` link back to the press release via this URL.

The issue body has five parts, in order:

1. **Context header** (plain text) — a short human-readable summary of what this feature does. Written for someone who has never heard of the project. No jargon, no internal tool names, no pipeline notation. 1-3 sentences max.

2. **`---` separator** before the press release.

3. **`>` blockquote** — the audience-facing press release. Clean narrative prose readable by anyone. No internal labels. Just headline, paragraphs, ASCII mockup (if applicable), and CTA.

4. **`---` separator** after the press release.

5. **Below the second `---`** — user stories (with unique IDs), internal context (current state / why / how / what), FAQ, and scope notes.

**Issue body structure**:

```
[1-3 sentence human-readable summary — no jargon, no internal tool names]

---

> ## [Headline: Customer Benefit in Plain Language]
>
> [Opening paragraph — who the customer is, what they can now do]
>
> [Problem paragraph — what the customer struggles with today]
>
> [Solution paragraph — how this solves it, customer outcomes]
>
> [Feature/benefit paragraph — what they can now do at high level]
>
> ```
> [ASCII art mockup if applicable]
> ```
>
> [Call to action]

---

**Current state**: [What the customer struggles with today]

**Why this**: [Why it matters now — motivation for building it]

**How**: [How the product solves the problem — customer outcomes]

**What**: [Key features and scope — what must be built]

### User Stories

- **US-1**: As a [persona], I want to [goal] so that [benefit]
- **US-2**: As a [persona], I want to [goal] so that [benefit]
- **US-3**: As a [persona], I want to [goal] so that [benefit]

### FAQ

- **Q: [Anticipated question]**
  A: [Answer]
```

**Do NOT include inside the `>` blockquote:**

- The `**Current state**` / `**Why this**` / `**How**` / `**What**` labels — these go outside the blockquote
- City dateline (e.g., "San Francisco, CA —") — omit unless user explicitly requests
- Fictional customer quotes — no fabricated testimonials

## Quality Criteria

- The headline and opening paragraph state the customer benefit, not the feature name
- The press release narrative covers the problem, solution, and customer benefit arc
- The entire release is written in present tense
- Succinct and semi-terse — no filler, no verbose marketing prose
- No jargon, buzzwords, or internal terminology — a non-technical reader can understand it
- The press release clearly implies what must be built to deliver the promise
- Word count is 300-500 words
- Includes a specific call to action
- No internal metrics or implementation details appear
- Claims do not exceed what the context brief defines as deliverable
- ASCII art mockup included for products with a UI (TUI, GUI, CLI, web) — shows realistic usage
- No fictional customer quotes
- No city dateline (unless user explicitly requested one)
- Local `.deepwork/tmp/` artifact filenames are unique to the run topic and do not reuse generic shared basenames
- The `>` blockquote in the published issue is audience-facing narrative prose — no `**Current state**` / `**Why this**` / `**How**` / `**What**` labels visible to readers
- The issue body (outside the blockquote) includes the `**Current state**` / `**Why this**` / `**How**` / `**What**` context sections for the development team
- The issue body includes a user stories section with 3-5 stories, each with a unique identifier (US-1, US-2, etc.)
- The issue title follows the `Press Release: <Product Label>` format
- The issue body has a human-readable context header above the first `---` — no jargon or internal tool names
- The press release blockquote is enclosed between two `---` separators

## Next Steps

After this workflow completes, suggest the following to the user:

> The press release is done. The natural next step is to run **`milestone/setup`** to create a milestone with user stories derived from this press release. The press release issue URL output feeds directly into milestone setup as the scope source.
>
> After milestone setup, run **`milestone/engineering_handoff`** to create functional requirement specs and a plan issue.

The full pipeline is: `project/press_release` → `milestone/setup` → `milestone/engineering_handoff`.

## Context

This press release is a working-backwards document in the Amazon tradition. It serves two audiences: customers (who should understand the value immediately) and the development team (who should understand what needs to be built). The quality of this document determines whether the team invests in building the feature — so clarity and honesty about what is being promised are essential.
