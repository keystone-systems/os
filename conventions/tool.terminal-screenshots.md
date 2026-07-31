## Terminal Screenshots

## Pipeline Overview

Screenshots for TUI applications are a natural output of testing, not a manual step.
The pipeline is: **test → text snapshot → PNG → PR demo**.

1. **Tests produce snapshots** — `cargo test` with `insta` generates `.snap` files via `ratatui::TestBackend`. Each screen has a corresponding snapshot under `tests/snapshots/`.
2. **Render PNGs** — `charm-freeze` converts each `.snap` file's text content to a PNG image. Strip the insta frontmatter (first 4 lines) before piping to freeze.
3. **Commit to assets/** — Rendered PNGs are stored in `assets/{package}/` and committed alongside the code.
4. **PR Demo section** — Changed PNGs are referenced in the PR body using raw GitHub URLs.

This parallels the `cadeng` pipeline where tests render OpenSCAD → STL → PNG for visual review.

## charm-freeze Command

```bash
# Extract snapshot text (skip insta frontmatter) and render to PNG
tail -n +5 tests/snapshots/render__render_welcome_screen.snap | freeze \
  --output assets/tui/welcome.png \
  --theme catppuccin-mocha \
  --language txt \
  --window=false \
  --padding "10" \
  --margin "0" \
  --font.size 14
```

### Flag Rationale

1. `--font.size 14` — Default produces oversized images. 14 gives proportional output for GitHub rendering.
2. `--window=false` — No macOS-style window chrome; keeps images clean and compact. Note: must use `=` syntax, not space-separated.
3. `--padding "10"` / `--margin "0"` — Minimal whitespace around the terminal content.
4. `--theme catppuccin-mocha` — Dark theme matching typical terminal appearance.
5. `--language txt` — Plain text rendering; no syntax highlighting that would miscolor TUI output.

## When to Use charm-freeze vs VHS

6. charm-freeze MUST be used for ratatui TUI applications. It renders static text to PNG without requiring a real TTY.
7. VHS (by Charm) MAY be used for simple CLI tools that produce sequential stdout output.
8. VHS MUST NOT be used for ratatui-based TUIs — ratatui requires a real TTY with cursor addressing, which VHS cannot provide reliably.

## Image Storage

9. Rendered PNGs MUST be stored in `assets/{package}/` (e.g., `assets/tui/welcome.png`).
10. File names SHOULD match the screen name from the snapshot (e.g., `render__render_welcome_screen.snap` → `welcome.png`).

## PR Demo Format

11. The PR Demo section MUST use `## Demo` with an image per changed screen:

```markdown
## Demo

### Welcome Screen

![Welcome Screen](https://raw.githubusercontent.com/{owner}/{repo}/{sha}/assets/tui/welcome.png)

### Dashboard

![Dashboard](https://raw.githubusercontent.com/{owner}/{repo}/{sha}/assets/tui/dashboard.png)
```

12. Raw URLs SHOULD use a commit SHA for stability rather than a branch name.
13. For PRs where the branch has not merged yet, the branch name MAY be used temporarily.

## Batch Rendering Script

To re-render all snapshots in a package:

```bash
SNAP_DIR="packages/keystone-tui/tests/snapshots"
OUT_DIR="assets/tui"
mkdir -p "$OUT_DIR"

for snap in "$SNAP_DIR"/render__render_*.snap; do
  name=$(basename "$snap" .snap | sed 's/render__render_//')
  tail -n +5 "$snap" | freeze \
    --output "$OUT_DIR/$name.png" \
    --theme catppuccin-mocha \
    --language txt \
    --window=false \
    --padding "10" \
    --margin "0" \
    --font.size 14
done
```
