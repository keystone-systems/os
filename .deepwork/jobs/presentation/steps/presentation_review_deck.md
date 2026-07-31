# Review Presentation Deck

## Objective

Run a structured review of the Slidev deck against the intended outline. Apply
all fixable issues. Produce a review report and the path to the revised slides.

## Task

Read `presentation_outline.md` to understand intended content, then read the slides.md
at the path in `presentation_slides_path.txt`. Review every slide, apply fixes, and
document findings.

### Process

1. **Read the deck** — open the slides.md at the path recorded in
   `presentation_slides_path.txt`.

2. **Per-slide review** — for each slide, check every item in this table:

   | Check | Pass criteria |
   |-------|--------------|
   | Title clarity | Specific and informative (not "Introduction" or "Overview") |
   | Bullet brevity | Short phrases, not full sentences or paragraphs |
   | Speaker notes | Tells the presenter what to say, not just what's on the slide |
   | Media relevance | Image/video is directly relevant and renders at a visible size |
   | TODO resolution | TODO comments are either resolved or explicitly left for human |
   | Narrative flow | Content flows logically from the previous slide |
   | Slidev syntax | No broken frontmatter, unclosed tags, or missing `---` separators |

3. **Narrative assessment** — after reviewing all slides:
   - Does the deck open with a compelling hook?
   - Does each section build toward the closing?
   - Is the call-to-action or closing message clear?

4. **Apply fixes** — correct everything you can without human input:
   - Tighten long bullets to phrases
   - Improve vague speaker notes
   - Fix Slidev syntax errors
   - Adjust layout choices if clearly wrong
   - Do NOT resolve `<!-- TODO: ... -->` media placeholders — leave those for the human

5. **Save the revised deck** to the same path.

6. **Write `presentation_review_report.md`** and **`presentation_slides_revised_path.txt`** — see
   Output Format below.

## Output Format

### presentation_review_report.md

```markdown
# Deck review report: Keystone infrastructure overview

## Overall narrative verdict
The deck tells a coherent story from the infrastructure problem to the Keystone
solution. The closing slide is strong. One section (slides 8–10) runs long and
could be tightened in a future iteration.

## Per-slide findings

### Slide 1
- ✅ Hook is compelling; no changes

### Slide 3
- ⚠️ Bullet was a full sentence — trimmed to "No SSH, no manual config"
- ✅ Speaker notes updated to be more specific

### Slide 5
- 🔲 TODO left for human: media placeholder for YubiKey photo

### Slide 8
- ⚠️ Layout was `default` — changed to `two-cols` to balance content
- ✅ Speaker notes were missing — added based on key message

## Fixes applied
- Slide 3: trimmed bullet, updated speaker notes
- Slide 8: changed layout to two-cols, added speaker notes

## Remaining open items (for human)
- Slide 5: `<!-- TODO: replace with photo of YubiKey -->`
- Slide 11: `<!-- TODO: add chart from Q1 dashboard -->`
```

### presentation_slides_revised_path.txt

Absolute path to the revised slides.md. If no changes were made, this equals
the path from `presentation_slides_path.txt`.

```
/home/ncrmro/notes/presentations/keystone-infrastructure-overview/slides.md
```

## Quality Criteria

- The report addresses every slide by number, even if just "no issues"
- Each issue entry includes the slide number, the problem, and the specific fix applied
- The report includes an overall narrative verdict (2–3 sentences on story arc)
- All identified issues are fixed in the revised slides.md before this step completes
- TODO comments (for human-only items like missing media) are listed in "Remaining
  open items" so the human has a complete checklist

## Context

This step is the final quality gate before delivery. The goal is a presentation the
human can step in front of immediately, with a clear list of the few items that still
need their personal attention (media, data, or decisions that require human judgment).
