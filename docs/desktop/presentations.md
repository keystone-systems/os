---
title: Demos & Presentations
description: Choosing the right tool for screen recordings, slide decks, and video post-processing
---

# Demos & Presentations

Keystone supports several approaches to creating demos and presentations. Each targets a different scenario — pick the one that fits your use case.

## Decision Matrix

| Scenario                         | Tool                    | Audio              | Slides    | Effort |
| -------------------------------- | ----------------------- | ------------------ | --------- | ------ |
| Quick PR demo / bug report       | `keystone-screenrecord` | Optional           | No        | ~1 min |
| Slide-based presentation         | Slidev                  | Built-in           | Yes       | Medium |
| Complex multi-source recording   | OBS Studio              | Full mixer         | Optional  | High   |
| Convert existing video to slides | `video-slidev`          | Preserves original | Generated | Medium |

## Quick PR / Bug Demos (keystone-screenrecord)

For short screen captures attached to PRs, issues, or Slack messages. This is the fastest path from "I need to show something" to a shareable video.

**When to use:** Bug reproductions, feature demos under 5 minutes, code walkthroughs.

```bash
# Silent demo (most common for PRs)
keystone-screenrecord

# With voiceover narration
keystone-screenrecord --with-microphone-audio

# With app sounds + narration
keystone-screenrecord --with-desktop-audio --with-microphone-audio
```

Click the red Waybar indicator to stop recording. Output lands in `~/Videos/`.

For full details, see [Screen Recording](screen-recording.md).

## Slide-Based Presentations (Slidev)

[Slidev](https://sli.dev) is a markdown-powered slide framework built on Vue. It supports presenter notes, live coding, recording, and PDF/PNG export — all from markdown files.

**When to use:** Conference talks, team presentations, project demos with structured narrative.

### Setup

Slidev is pre-installed on all keystone desktop and agent profiles via `pkgs.keystone.slidev`. The `slidev` command is available immediately — no npm install needed.

To create a new presentation:

```bash
# Create a slides.md in your project and start presenting
slidev slides.md

# Or initialize a full Slidev project with themes
npm init slidev@latest my-presentation
```

### Creating Slides

Write slides in `slides.md`:

```markdown
---
theme: default
title: My Presentation
---

# Slide Title

Content goes here.

---

# Second Slide

- Bullet points
- Code blocks work natively

\`\`\`python
def hello():
print("Hello from the presentation")
\`\`\`

---

## layout: presenter

# Live Demo

Use presenter mode to show your screen alongside slides.
```

### Presenting and Recording

```bash
# Start dev server with hot reload
npx slidev

# Open presenter mode (separate window with notes + timer)
# Navigate to http://localhost:3030/presenter

# Record your presentation (screen + camera)
npx slidev --record

# Export to PDF
npx slidev export

# Export to PNG images
npx slidev export --format png
```

Slidev's built-in recording captures both the slide view and presenter view simultaneously. The output is a WebM file saved to the project directory.

### Presenter Mode

Presenter mode (`/presenter` route) shows:

- Current slide + next slide preview
- Speaker notes
- Timer and progress
- Drawing tools

This is useful for live presentations where you have a secondary display, or for recording where you want both the audience view and your notes captured.

## Long-Form Tutorials / Streaming (OBS Studio)

[OBS Studio](https://obsproject.com) is a full-featured recording and streaming application. Use it when you need scene switching, overlays, webcam compositing, or multi-source audio mixing.

**When to use:** YouTube tutorials, live streams, multi-camera setups, recordings requiring post-production editing, picture-in-picture layouts.

### Setup

OBS is available in nixpkgs:

```nix
# In your NixOS or home-manager config
environment.systemPackages = [ pkgs.obs-studio ];

# Or run directly
nix run nixpkgs#obs-studio
```

### Basic Recording Workflow

1. **Add sources:** Display Capture (full screen), Window Capture (single app), or Video Capture Device (webcam)
2. **Configure audio:** Desktop audio is captured automatically. Add your microphone as an Audio Input Capture source
3. **Set output format:** Settings → Output → Recording → MP4 or MKV container, hardware encoder if available
4. **Record:** Click "Start Recording" or use the hotkey (default: unset, configure in Settings → Hotkeys)

### OBS vs keystone-screenrecord

| Feature         | keystone-screenrecord | OBS Studio                  |
| --------------- | --------------------- | --------------------------- |
| Setup time      | Zero (built-in)       | Requires config             |
| Scene switching | No                    | Yes                         |
| Webcam overlay  | No                    | Yes                         |
| Audio mixing    | Basic (mic + desktop) | Full mixer                  |
| Streaming       | No                    | Yes (Twitch, YouTube, etc.) |
| GPU encoding    | Yes                   | Yes                         |
| Wayland support | Native (portal)       | Via PipeWire                |

**Rule of thumb:** If `keystone-screenrecord` can do it, use that. Reach for OBS when you need features it doesn't have.

## Video-to-Slidev Post-Processing (video-slidev)

The `video-slidev` tool converts an existing screen recording into a Slidev presentation by detecting scene changes and generating slides with timestamps.

**When to use:** You already have a recording and want to create a navigable slide deck from it, or you want to add chapter markers and annotations after recording.

### Setup

The tool is located at `~/Downloads/video-slidev`. To use:

```bash
cd ~/Downloads/video-slidev
npm install
```

### Usage

```bash
# Convert a recorded video to a Slidev project
npx video-slidev convert ~/Videos/screenrecording-2026-03-23_14-30-45.mp4 \
  --output ./my-presentation

# This generates:
# - slides.md with timestamps and auto-detected scene breaks
# - Embedded video references for each slide
# - A Slidev project you can edit and re-export
```

### Workflow

1. Record your demo using `keystone-screenrecord` or OBS
2. Run `video-slidev convert` on the recording
3. Edit the generated `slides.md` — add titles, notes, clean up scene breaks
4. Present or export with `npx slidev` / `npx slidev export`

This is particularly useful for creating after-the-fact presentations from ad-hoc recordings, or for adding structure to long tutorial videos.

## Choosing Your Workflow

```
Need to show something quickly?
  └── keystone-screenrecord (+ attach to PR/issue)

Giving a talk or structured presentation?
  └── Slidev (write slides.md → present → export)

Need webcam, scene switching, or streaming?
  └── OBS Studio

Already have a video, want slides from it?
  └── video-slidev convert
```

## See Also

- [Screen Recording](screen-recording.md) — full `keystone-screenrecord` reference
- [Slidev Documentation](https://sli.dev) — upstream Slidev docs
- [OBS Studio Wiki](https://obsproject.com/wiki/) — upstream OBS docs
