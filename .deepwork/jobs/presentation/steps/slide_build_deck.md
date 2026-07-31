# Build Slidev Deck

## Objective

Translate the slide content plan into a complete, runnable Slidev presentation. Scaffold
the project directory, write `slides.md`, and verify the file is syntactically valid.

## Task

Create the Slidev project on disk and populate it with every slide from the plan.

### Process

1. **Prepare the output directory**

   Read `slides_md_path.txt` output target path from the previous step inputs, or derive
   from the `output_dir` parameter supplied at workflow start (default: `./slide-deck`).

   ```bash
   mkdir -p <output_dir>
   ```

   Do NOT run `slidev init` — write `slides.md` directly to avoid interactive prompts.

2. **Write the global frontmatter**

   The first block of `slides.md` is the global Slidev configuration:

   ```markdown
   ---
   theme: default
   title: "<presentation title>"
   info: |
     <one-line description>
   class: text-center
   highlighter: shiki
   drawings:
     persist: false
   transition: slide-left
   mdc: true
   ---
   ```

   Adjust `theme` and `transition` based on the audience:
   - Formal/investor: `theme: seriph`, `transition: fade`
   - Technical/engineering: `theme: default`, `transition: slide-left`
   - Creative/marketing: `theme: apple-basic`, `transition: slide-up`

3. **Write each slide**

   Separate slides with `---`. For each slide in the content plan:

   - Add a per-slide frontmatter block with `layout:` and optional `class:` overrides.
   - Render `key_points` as a Markdown bullet list (`- item`).
   - For `two-cols` layout, split points across `::left::` and `::right::` dividers.
   - For `image-right` / `image-left` layouts:
     - If an asset exists, reference it with `image: /images/<filename>` and add
       `imageAlt: "<description from _media/index.yaml>"` on the next line.
     - If no asset exists yet, leave a TODO comment: `image: <!-- TODO: replace with actual image -->`
     - For `<img>` tags used inline, always include `alt="<description>"`.
     - Pull descriptions from `_media/index.yaml` rather than re-reading the image file.
   - For `fact` or `quote` layouts, use the largest key point as the featured text.
   - Add speaker notes as an HTML comment block at the end of each slide:
     ```markdown
     <!--
     Speaker notes go here.
     -->
     ```
   - **Speaker notes and image relevance**: When a slide has an image, the speaker notes MUST
     contain at least one sentence explaining *why* that image is on this slide — not just what
     it depicts. If the image serves a non-obvious purpose (e.g., providing the agent with precise
     hardware context to prevent hallucination, reinforcing credibility, or making an emotional
     point), state that purpose explicitly in the notes.

4. **Cover slide convention**

   The first slide MUST use `layout: cover` and include:

   ```markdown
   ---
   layout: cover
   background: https://cover.sli.dev
   ---

   # <Title>

   <Subtitle or speaker name>

   <div class="pt-12">
     <span @click="$slidev.nav.next" class="px-2 py-1 rounded cursor-pointer" hover="bg-white bg-opacity-10">
       Press Space to continue <carbon:arrow-right class="inline"/>
     </span>
   </div>
   ```

5. **Section dividers**

   Use `layout: section` slides to separate major sections of the deck (context, body, close).

6. **Write the path file**

   After writing `slides.md`, record its absolute path:

   ```bash
   echo "<absolute_path_to_slides.md>" > slides_md_path.txt
   ```

7. **Syntax check**

   Verify the file contains the expected number of `---` separators:

   ```bash
   grep -c "^---$" <slides.md path>
   # Expected: (slide_count * 2) - 1  (each slide opens and closes with ---)
   ```

   If the count is wrong, re-read the file and fix the structure before completing this step.

## Output Format

### slides_md_path.txt

A single line containing the absolute path to the generated `slides.md` file:

```
/home/ncrmro/.keystone/repos/.../<output_dir>/slides.md
```

### slides.md (the deck itself)

Complete Slidev presentation. Example structure for a 5-slide deck:

```markdown
---
theme: default
title: "My Presentation"
...
---

# My Presentation

Subtitle

<!--
Speaker notes for slide 1.
-->

---
layout: default
---

## Slide 2 Title

- Point one
- Point two
- Point three

<!--
Speaker notes for slide 2.
-->

---
layout: two-cols
---

## Slide 3 Title

::left::
- Left column point one
- Left column point two

::right::
- Right column point one
- Right column point two

<!--
Speaker notes for slide 3.
-->
```

## Quality Criteria

- The file uses correct Slidev frontmatter and `---` slide separators with no syntax errors.
- Every slide from `slide_content_plan.md` is present in the deck.
- Slides use appropriate Slidev layouts rather than blank `default` throughout.
- Each slide has a speaker notes comment block.
- Every `image:` frontmatter field is paired with an `imageAlt:` field containing the description from `_media/index.yaml`.
- Every `<img>` tag has an `alt` attribute with the description from `_media/index.yaml`.
- Speaker notes for any slide with an image include a sentence explaining *why* the image is on that slide.
- The `slides_md_path.txt` file contains a valid, accessible file path.

## Context

Slidev is available on this host at the system path. The deck is served with:

```bash
slidev <slides.md path>
```

And exported with:

```bash
slidev export <slides.md path>
```

Do not install Slidev or run `npm install` — it is pre-installed system-wide via the
Keystone NixOS package (`pkgs.keystone.slidev`). If `slidev` is not on `$PATH`, it is
available at `/etc/profiles/per-user/ncrmro/bin/slidev`.
