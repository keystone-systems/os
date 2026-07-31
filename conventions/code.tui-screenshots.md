<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: TUI Screenshots (code.tui-screenshots)

Standards for capturing reproducible screenshots and demo recordings of ratatui-based TUI applications. Screenshots serve as both PR review artifacts and long-term documentation assets.

## Screenshot Mode

1. TUI binaries MUST support a `--screenshot <screen>` CLI flag that renders a single named screen to stdout as ANSI without entering alternate screen or raw mode.
2. The `--screenshot` mode MUST call `terminal.clear()` before drawing to force ratatui to write every cell, ensuring sparse screens render fully for capture tools.
3. The `--screenshot` mode MUST exit after rendering — it MUST NOT enter the event loop.
4. Every user-facing screen SHOULD be registered as a valid `--screenshot` target.

## VHS Tape Files

5. Each screenshot MUST have a corresponding vhs tape file in `docs/tapes/<screen>.tape`.
6. Tape files MUST declare `Require <binary>` to fail fast if the TUI binary is not on `$PATH`.
7. Tape files MUST set consistent visual parameters: `Set FontSize 14`, `Set Width 1200`, `Set Height 600`, `Set Theme "Catppuccin Mocha"`, `Set Padding 20`, `Set WindowBar Colorful`.
8. Tape files MUST use `Set TypingSpeed 0` to eliminate recording delays.
9. Tape files MUST use `Screenshot docs/screenshots/<screen>.png` to write output to the canonical location.
10. Tape files SHOULD include a regeneration comment at the top: `# Regenerate: nix run nixpkgs#vhs -- docs/tapes/<screen>.tape`.

## Demo Requirement

11. PRs that change any desktop or TUI screen rendering MUST include demo screenshots in the PR description's `# Demo` section — this is a hard requirement, not optional.
12. Each visually distinct screen affected by the PR MUST have its own screenshot.

## Screenshot Storage

13. Screenshots MUST NOT be committed as regular git objects — binary files bloat the repo history permanently.
14. For PR demos, screenshots MUST be uploaded inline to the PR description or comments (GitHub and Forgejo accept drag-drop image uploads).
15. For long-term documentation, screenshots MUST be stored in git LFS on Forgejo — this is the preferred storage for all internal documentation images.
16. For public-facing documentation (ks.systems website, press releases), screenshots MUST be uploaded to R2 Cloudflare object storage and referenced by URL.
17. Generated screenshots in `docs/screenshots/` MUST be listed in `.gitignore` — they are ephemeral build artifacts, not tracked files.
18. Screenshots MUST be regenerated before marking a PR ready for review if the PR changes any TUI screen rendering.

## Accidental Image Commits

19. If screenshots or other binary images are accidentally committed as regular git objects, they MUST be removed from history using `git lfs migrate` or `git filter-repo`:

```bash
# Option 1: Migrate existing committed images to LFS
git lfs migrate import --include="*.png,*.gif,*.jpg" --everything

# Option 2: Remove images from history entirely (if not needed in LFS)
git filter-repo --path assets/tui/ --invert-paths
# Then force-push (requires team coordination):
git push --force-with-lease
```

20. After rewriting history, all collaborators MUST re-clone or run `git fetch --all && git reset --hard origin/main`.

## Dev Shell

21. `vhs` SHOULD be included in the project's Nix devshell for screenshot generation.
22. A `make screenshots` target SHOULD be provided that regenerates all screenshots by running all tape files in `docs/tapes/`.

## Known Limitations

23. vhs MUST NOT be used to capture screens rendered in crossterm's alternate screen buffer — the `--screenshot` flag exists specifically to work around this limitation.
24. Screens that produce sparse ANSI output (few positioned cells) MAY fail with vhs's `Screenshot` command. In such cases, the tape file SHOULD document the limitation and offer a `GIF` Output as fallback.

## Golden Example

End-to-end workflow for adding a screenshot of a new TUI screen:

```bash
# 1. Add --screenshot support for the new screen in main.rs
#    (inside the run_screenshot_mode match block)
"my-screen" => {
    let mut screen = MyScreen::new();
    terminal.draw(|frame| {
        screen.render(frame, frame.area());
    })?;
}

# 2. Create the tape file
cat > docs/tapes/my-screen.tape << 'TAPE'
# My screen — description of what it shows
#
# Regenerate: nix run nixpkgs#vhs -- docs/tapes/my-screen.tape

Require keystone-tui

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 20
Set WindowBar Colorful
Set TypingSpeed 0

Type "keystone-tui --screenshot my-screen"
Enter
Sleep 2s
Screenshot docs/screenshots/my-screen.png
TAPE

# 3. Build the binary and run the tape
cargo build --release
PATH="$PWD/target/release:$PATH" nix run nixpkgs#vhs -- docs/tapes/my-screen.tape

# 4. Verify the screenshot (local only — not committed)
ls -la docs/screenshots/my-screen.png

# 5. Upload to PR as inline image (drag-drop or gh CLI)
# The PNG is NOT committed — upload it to the PR description instead.

# 6. Commit only the tape file (the recipe, not the artifact)
git add docs/tapes/my-screen.tape
git commit -m "docs(tui): add my-screen vhs tape"
```
