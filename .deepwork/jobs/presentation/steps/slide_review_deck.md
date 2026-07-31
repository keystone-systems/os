# Review Deck

## Objective

Perform a structured editorial and technical review of the Slidev deck. Identify and fix
all content, structure, and presenter-readiness issues before delivery.

## Task

Read the generated `slides.md`, audit it against the content plan, apply fixes, and
produce a review report that documents every finding and the resolution taken.

### Process

1. **Load inputs**

   - Read `slide_content_plan.md` for the intended content and structure.
   - Read the path from `slides_md_path.txt`, then read the `slides.md` file at that path.

2. **Count and index slides**

   Parse the slide separators (`---`) to establish a slide index. Confirm the count
   matches `slide_content_plan.md`. Log any discrepancy.

3. **Run the editorial checklist per slide**

   For every slide, check:

   | Check                   | Pass criteria                                                  |
   | ----------------------- | -------------------------------------------------------------- |
   | **Title present**       | Slide has a `#` or `##` heading                                |
   | **Bullet count**        | ≤ 4 bullets; no bullets longer than 12 words                   |
   | **Speaker notes**       | `<!-- ... -->` block is present and has ≥ 2 sentences          |
   | **Layout correct**      | Per-slide layout matches the plan; no unnecessary `default`    |
   | **Placeholder images**  | TODO image comments are flagged as open items                  |
   | **No walls of text**    | No paragraph longer than 3 sentences on a single slide         |

4. **Run the narrative checklist**

   Review the deck as a whole:

   - Does the opening slide immediately communicate the topic and value?
   - Is there a logical flow from context → body → close?
   - Is the closing slide action-oriented (call-to-action, next steps, or contact)?
   - Are there section-divider slides between major topic shifts?
   - Is the tone consistent with the target audience?

5. **Apply fixes**

   For every issue found, apply the fix directly to `slides.md` in place. Do not
   produce a separate corrected file — edit the file at the path from `slides_md_path.txt`.

   Common fixes:
   - Split overlong bullets into two shorter bullets.
   - Add missing speaker notes.
   - Replace wrong layout with the correct Slidev layout name.
   - Reorder slides to restore narrative flow.
   - Add a closing call-to-action slide if none is present.

6. **Write review report**

   Document findings and fixes in `slide_review_report.md`.

7. **Record revised path**

   After all edits, write the (potentially unchanged) path to `slides_revised_path.txt`:

   ```bash
   echo "<absolute_path_to_revised_slides.md>" > slides_revised_path.txt
   ```

   This MUST be the same absolute path as in `slides_md_path.txt` (edits are in-place).

## Output Format

### slide_review_report.md

```markdown
# Slide Deck Review Report

## Parameters

- **Deck**: [path to slides.md]
- **Planned slide count**: [N]
- **Actual slide count**: [N]
- **Reviewed on**: [date]

## Narrative Verdict

[2–3 sentences: does the deck tell a clear, audience-appropriate story?]

## Per-Slide Findings

### Slide 1 — [title]

[No issues] OR

- **Issue**: [description]
  **Fix applied**: [what was changed]

### Slide 2 — [title]

...

## Open Items

Items that require human input or assets not available to the agent:

- [ ] [description] (slide N)

## Summary

- **Issues found**: [N]
- **Issues fixed**: [N]
- **Open items remaining**: [N]
```

### slides_revised_path.txt

Absolute path to the revised `slides.md` (same file, edited in place):

```
/home/ncrmro/.keystone/repos/.../<output_dir>/slides.md
```

## Quality Criteria

- The report addresses every slide by number, even if just "no issues."
- Each issue entry includes the slide number, the problem, and the specific fix applied.
- The report includes an overall narrative verdict.
- All identified issues are fixed in `slides.md` before this step completes.
- The `slides_revised_path.txt` file contains a valid, accessible file path.

## Context

This review step is designed to catch what automated generation misses: narrative gaps,
overloaded slides, missing speaker notes, and audience-tone mismatches. The agent acts
as both a content editor and a technical reviewer.

If the deck is based on output from the `presentation` workflow,
cross-reference the original presentation outline to ensure no key messages were lost
during slide conversion.
