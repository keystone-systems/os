# Build Slidev Deck

## Objective

Convert the approved outline into a working Slidev markdown presentation. Embed
media, speaker notes, and TODO comments. Save the deck to the notes repo.

## Task

Read `presentation_outline.md` and `presentation_media_manifest.md`, then generate a complete
`slides.md` in Slidev format. Write the file to the configured notes dir `presentations/<slug>/`
using `NOTES_DIR="${NOTES_DIR:-$HOME/notes}"`.

### Process

1. **Determine the output path**:
   - Derive `<slug>` from the topic in `presentation_requirements.md`: lowercase, kebab-case,
     max 40 chars (e.g., `keystone-infrastructure-overview`).
   - If `$NOTES_DIR/presentations/<slug>/` already exists, append `-2`.
   - Create the directory: `mkdir -p "$NOTES_DIR/presentations/<slug>"`.

2. **Write the Slidev frontmatter header** at the top of `slides.md`:

   ```yaml
   ---
   theme: default
   title: <Presentation title>
   info: |
     <One-line description>
   class: text-center
   highlighter: shiki
   drawings:
     persist: false
   transition: slide-left
   ---
   ```

3. **Write each slide** from `presentation_outline.md`, separated by `---`.

   **Layout options**:
   - `cover` — title slide
   - `default` — standard text slide
   - `center` — centered content
   - `two-cols` — use `::left::` / `::right::` markers
   - `image-right` / `image-left` — image beside text

   **Speaker notes** — add after a `<!--` comment block:

   ```markdown
   ---
   layout: default
   ---

   # Slide title

   - Bullet

   <!-- Speaker note text goes here -->
   ```

   **Media** — use `<img>` for layout control:

   ```markdown
   <img src="./_dataroom/media/abc123_rack.jpg" class="h-60 rounded shadow" />
   ```

   **TODO placeholders**:

   ```markdown
   <!-- TODO: replace with screenshot of ks build output -->
   ```

4. **Copy media assets** to sit next to `slides.md`:

   ```bash
   NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
   cp -r presentations/<slug>/_dataroom "$NOTES_DIR/presentations/<slug>/_dataroom"
   ```

   Skip if already in the configured notes dir.

5. **Write `presentation_slides_path.txt`** — the absolute path to the slides.md file:

   ```
   <notes-dir>/presentations/keystone-infrastructure-overview/slides.md
   ```

## Output Format

### presentation_slides_path.txt

A single line containing the absolute path to slides.md. No trailing newline.

**Example**:
```
<notes-dir>/presentations/keystone-infrastructure-overview/slides.md
```

### slides.md (referenced by the path above)

```markdown
---
theme: default
title: Keystone infrastructure overview
info: |
  How Keystone turns hardware into a fully declared, encrypted fleet.
class: text-center
highlighter: shiki
drawings:
  persist: false
transition: slide-left
---

# Keystone: your infrastructure, fully declared

*One diff to rule them all*

---
layout: two-cols
---

## What Keystone manages

::left::
- OS, secrets, users, services

::right::
- Dev tooling, agents, monitoring

<!-- Keep this fast — 60 seconds. Goal is scope, not deep explanation. -->

---
layout: image-right
image: ./_dataroom/media/a1b2c3_rack.jpg
---

## Hardware is commodity; config is code

- No SSH, no manual config, no Ansible
- One `git push` deploys to the fleet

<!-- Point out that none of these machines have been SSHed into manually. -->

---
layout: default
---

## Hardware key unlock

- Secrets released by TPM + YubiKey at boot
- Physical disk access alone cannot expose secrets

<!-- TODO: replace with photo of YubiKey — not found in Immich search -->

<!-- Emphasize: attacker with disk access is still locked out without the key. -->
```

## Quality Criteria

- The file uses correct Slidev frontmatter and `---` slide separators with no
  syntax errors
- Every slide from `presentation_outline.md` is represented in the deck
- Slides use appropriate Slidev layouts rather than bare `default` throughout
- Every slide has a `<!-- speaker note -->` block with presenter guidance
- Slides with unresolved media have `<!-- TODO: ... -->` comments so the human
  knows what to fill in before presenting

## Context

This step converts the plan into code. Keep slides brief — one idea per slide,
short bullets. The speaker notes carry the explanation, not the slide content.
The resulting deck goes into the configured notes dir and will be committed with
git LFS in `presentation_deliver`.
