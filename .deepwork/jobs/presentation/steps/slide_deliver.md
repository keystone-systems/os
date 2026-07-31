# Deliver Deck

## Objective

Verify the deck builds cleanly with Slidev, confirm the final artifact, and hand off
clear serve and export instructions to the operator.

## Task

Run a build verification pass, confirm the slide count, list any remaining open items,
and produce a concise delivery summary.

### Process

1. **Read the revised deck path**

   Read `slides_revised_path.txt` to get the absolute path to the final `slides.md`.

2. **Verify the deck builds**

   Run a Slidev build in the output directory to confirm no parse or render errors:

   ```bash
   cd <output_dir>
   slidev build slides.md --out dist/ 2>&1 | tee slidev_build.log
   ```

   - If the build exits 0: note "Build: success" in the summary.
   - If the build exits non-zero: read `slidev_build.log`, identify the error, fix
     `slides.md`, re-run the build. Do not mark this step complete until the build passes.

   > **Note**: Slidev requires a Node.js runtime. If the build fails with a Node/npm
   > error, try: `cd <output_dir> && slidev slides.md --open false` to verify the
   > Markdown syntax instead. Document whichever verification method was used.

3. **Count final slides**

   ```bash
   grep -c "^---$" <slides.md path>
   ```

   Divide the separator count by 2 (each slide is bounded by two `---` lines, except the
   last). Compare to the target from `slide_content_plan.md`. Note any discrepancy.

4. **Collect open items**

   Scan the revised `slides.md` for outstanding placeholders:

   ```bash
   grep -n "TODO" <slides.md path>
   ```

   List each hit by line number and description in the delivery summary.

5. **Produce the delivery summary**

   Write `slide_delivery_summary.md` with serve command, export command, file location,
   slide count, build status, and open items.

## Output Format

### slide_delivery_summary.md

```markdown
# Slide Deck Delivery Summary

## Deck

- **File**: [absolute path to slides.md]
- **Output directory**: [path]
- **Slide count**: [N] (planned: [N])
- **Build status**: ✅ Success | ❌ Failed (see notes below)

## How to use

### Preview (live reload)

```bash
slidev [path/to/slides.md]
```

Opens the presenter view at http://localhost:3030

### Export to PDF

```bash
slidev export [path/to/slides.md] --format pdf
```

### Export to PNG (one file per slide)

```bash
slidev export [path/to/slides.md] --format png
```

### Build static site

```bash
slidev build [path/to/slides.md] --out dist/
```

## Open items

Items requiring human input before the deck is presentation-ready:

- [ ] Slide [N]: [description]

(Leave blank if none.)

## Notes

[Any build warnings, workarounds, or deviations from the standard process]
```

## Quality Criteria

- The summary confirms `slidev build` (or equivalent verification) completed without errors.
- The summary shows the exact command to preview the deck locally.
- The final slide count matches the planned count from `slide_content_plan.md` (or the
  discrepancy is explained).
- Any remaining TODOs (missing images, placeholder text, pending decisions) are listed.
- The deck file path in the summary is absolute and accessible.

## Context

Slidev is pre-installed on this Keystone host (`pkgs.keystone.slidev`). The binary is at
`/etc/profiles/per-user/ncrmro/bin/slidev`. The serve command opens a local dev server
with hot-reload — useful for final review before a presentation.

If the deck was generated from `presentation` workflow output, consider
committing the `slides.md` into the relevant project notes repo alongside the source
outline so the two artifacts stay linked.
