# Gather Presentation Content

## Objective

Collect, structure, and validate the source material for a Slidev slide deck. Produce a
slide-by-slide content plan that the build step can convert directly into Slidev markdown.

## Task

Determine the presentation's purpose, audience, and constraints, then organize the raw
content into a numbered slide plan with titles, key points, and speaker notes.

### Process

1. **Determine the content source**

   Inspect the `presentation_source` input:

   - **File path** — read the file (e.g., `presentation_outline.md` from the
     `presentation` workflow). Extract sections as slides.
   - **Topic/goal string** — treat it as the presentation brief. Research the topic using
     available tools (web search, notes repos, project files) to build the content.
   - **`ask`** — prompt the operator for the presentation topic, goal, and key points
     interactively before proceeding.

2. **Establish presentation parameters**

   Record the following from the inputs (use sensible defaults when not provided):

   | Parameter          | Default                     |
   | ------------------ | --------------------------- |
   | Audience           | General professional        |
   | Duration (minutes) | 20                          |
   | Slide count target | `ceil(duration / 1.5)`      |
   | Output directory   | `./slide-deck`              |

3. **Structure the narrative arc**

   Every deck MUST follow this arc:

   - **Opening** (1–2 slides): hook, title, who is speaking and why this matters
   - **Context** (1–3 slides): problem statement or background — why now?
   - **Body** (bulk of slides): main argument, evidence, examples, data
   - **Close** (1–2 slides): summary, call-to-action or next steps, contact/links

4. **Build or check the media manifest**

   Before planning slides, check whether `_media/index.yaml` exists in the output directory:

   - If it exists, read it — it is the canonical source of image descriptions for this presentation.
   - If images are being added that aren't in the index, add an entry for each with `file` and `description`.
   - **If the purpose of an image on a specific slide isn't obvious from its description alone, use
     the `AskUserQuestion` tool to ask a clarifying question before assigning it.** Do not infer intent
     when the connection could be interpreted multiple ways. For example: "You have
     `esp32-c3-ascii-pinout.png` — what is the key point this image is making on the Early Mistakes
     slide?" Batch multiple unclear images into a single `AskUserQuestion` call rather than asking one
     at a time.
   - Images are not just decoration. Some serve as long-term context (e.g., a pinout tells the agent
     exactly which hardware is in use, reducing hallucination risk). The plan should record *why* each
     image is present, not just *what* it shows.

5. **Plan each slide**

   For every slide in the plan, specify:

   - `slide_number`: integer starting at 1
   - `title`: short, punchy title (≤ 8 words)
   - `layout`: recommended Slidev layout (`cover`, `intro`, `default`, `center`,
     `two-cols`, `image-right`, `image-left`, `fact`, `quote`, `section`, `end`)
   - `key_points`: bullet list of 2–4 points to appear on the slide
   - `visual_hint`: description of the image/diagram to include AND why it belongs on this slide
     (use `none` if the slide is text-only)
   - `speaker_notes`: 2–5 sentences the presenter should say while on this slide; if an image is
     present and its relevance isn't self-evident, speaker notes MUST include a sentence explaining
     why that image is there

6. **Validate calibration**

   - Total slide count MUST be between `floor(duration / 2)` and `ceil(duration / 1)`.
   - No more than 4 bullet points per slide.
   - Opening and closing slides MUST be present.

## Output Format

### slide_content_plan.md

```markdown
# Slide Content Plan

## Presentation Parameters

- **Title**: [presentation title]
- **Audience**: [audience description]
- **Duration**: [N] minutes
- **Target slide count**: [N]
- **Output directory**: [path]
- **Source**: [file path or brief description of source]

## Narrative Arc

[2–3 sentence summary of the story the deck tells]

## Slides

### Slide 1 — [title]

- **Layout**: cover
- **Key points**:
  - [point]
- **Visual hint**: [description or "none"]
- **Speaker notes**: [notes]

### Slide 2 — [title]

...
```

## Quality Criteria

- The number of slides is proportional to the target duration (roughly 1–2 minutes per slide).
- Slides follow a coherent story: opening hook, body, and closing call-to-action or summary.
- Content depth and vocabulary match the stated audience.
- Every slide has speaker notes summarizing what to say.
- No slide has more than 4 key points.
- A layout is specified for every slide.
- Every image assignment has a stated reason in `visual_hint` — not just what the image shows, but why it belongs on this slide.
- Any image whose relevance was unclear was resolved via `AskUserQuestion` before finalizing the plan.

## Context

This is the planning step for the slide_deck workflow. The output is consumed by
`slide_build_deck`, which translates the plan directly into Slidev markdown. Invest time
here to produce a complete, well-structured plan — it is much cheaper to fix the outline
than to rewrite rendered slides.

If the `presentation` workflow has already run, its output file
(typically `presentation_outline.md` or `presentation_script.md`) should be passed as
`presentation_source`. The workflow is designed so this step can ingest that output
without additional research.
