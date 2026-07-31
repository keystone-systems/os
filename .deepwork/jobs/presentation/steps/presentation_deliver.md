# Deliver Presentation to Notes Repo

## Objective

Ensure the final Slidev deck and all media assets are committed to the notes repo
with git LFS tracking for binaries. Produce a delivery summary the human can use
to preview, export, and finish any remaining TODO items.

## Task

Read `presentation_requirements.md` (for the slug and title) and `presentation_slides_revised_path.txt`
(for the deck location). Configure git LFS, stage files, commit, and write the
delivery summary.

### Process

1. **Confirm the notes repo**:

   ```bash
   NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
   git -C "$NOTES_DIR" status
   ```

   If not a git repo or the path doesn't exist, stop and alert the user.

2. **Configure git LFS** (idempotent — safe to re-run):

   ```bash
   NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
   git -C "$NOTES_DIR" lfs install
   git -C "$NOTES_DIR" lfs track \
     "presentations/**/*.jpg" "presentations/**/*.jpeg" \
     "presentations/**/*.png" "presentations/**/*.gif" \
     "presentations/**/*.webp" "presentations/**/*.mp4" \
     "presentations/**/*.mov" "presentations/**/*.pdf"
   git -C "$NOTES_DIR" add "$NOTES_DIR/.gitattributes"
   ```

3. **Stage the presentation directory**:

   ```bash
   NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
   git -C "$NOTES_DIR" add presentations/<slug>/
   ```

4. **Verify LFS objects** — run `git -C "$NOTES_DIR" lfs status` and confirm binary
   assets show up as LFS objects (not plain files). If not, re-run the `lfs track`
   commands and re-stage.

5. **Commit** using a conventional commit message:

   ```bash
   NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
   git -C "$NOTES_DIR" commit -m "docs(presentations): add <slug> presentation"
   ```

6. **Write `presentation_delivery_summary.md`** — see Output Format below.

## Output Format

### presentation_delivery_summary.md

```markdown
# Delivery summary: Keystone infrastructure overview

## Location
`<notes-dir>/presentations/keystone-infrastructure-overview/slides.md`

## Git LFS assets
| File | Tracked as LFS |
|------|----------------|
| presentations/keystone-infrastructure-overview/_dataroom/media/a1b2c3_rack.jpg | ✅ yes |
| presentations/keystone-infrastructure-overview/_dataroom/media/d4e5f6_terminal.png | ✅ yes |

## Commit
`docs(presentations): add keystone-infrastructure-overview presentation`
**Status**: committed ✅

## Preview
```bash
cd <notes-dir>/presentations/keystone-infrastructure-overview
slidev
```
Open: http://localhost:3030

## Export to PDF
```bash
cd <notes-dir>/presentations/keystone-infrastructure-overview
slidev export --format pdf
```

## Open TODO items (review before presenting)
- [ ] Slide 5: `<!-- TODO: add photo of YubiKey — not found in Immich search -->`
- [ ] Slide 11: `<!-- TODO: add Q1 dashboard chart -->`
```

## Quality Criteria

- The summary shows the exact configured notes-dir `presentations/<slug>/` path where the deck
  was saved
- All binary assets (images, videos) are confirmed as git LFS tracked objects
- A git commit was made with a conventional-commit message, and the summary confirms
  the commit status
- The summary includes the exact commands to preview with Slidev and export to PDF
- All remaining `<!-- TODO: ... -->` comments from the deck are listed so the human
  has a complete checklist before presenting

## Context

This is the final step of the `presentation` workflow. After this step, the deck
lives in the notes repo (tracked by git with LFS for binary assets) and the human
has everything they need to preview, iterate, and present. The TODO checklist is
the handoff from agent to human — keep it complete and specific.
