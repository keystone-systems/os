# REQ-023: Executive Assistant + Perception Layer

Adds document, voice, and visual perception capabilities to Keystone OS agents,
then exposes those capabilities through a unified `/ks.assistant` slash command
that routes natural-language requests to the correct `executive_assistant`
DeepWork workflow. Agents gain the ability to parse PDFs, transcribe voice
locally, search photos and screenshots, sync screenshots to Immich for ML
indexing, link recognized people to CardDAV contacts, and reconstruct activity
summaries that auto-sync into notes. The executive assistant layer wraps these
tools in orchestrated workflows accessible from a single command.

Press release: https://github.com/ncrmro/keystone/issues/259
User stories: https://github.com/ncrmro/keystone/issues/181
Plan: https://github.com/ncrmro/keystone/issues/184

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a Keystone operator, I want my OS agents to process documents, voice
recordings, and photos on my local hardware, and I want a single `/ks.assistant`
command to orchestrate those capabilities on my behalf, so that I can search,
extract, summarize, and act on unstructured data without manual tool
orchestration or sending anything to cloud services.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Operator Terminal                                │
│                                                                          │
│  /ks.assistant "summarize my standup recording"                          │
│        │                                                                 │
│        ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  executive_assistant DeepWork Job                           │        │
│  │                                                             │        │
│  │  summarize_audio ──► whisper.cpp ──► Ollama ──► zk note    │        │
│  │  review_photos   ──► ks photos ─────────────► terminal    │        │
│  │  start_recording ──► OBS WebSocket ──────────► daily note  │        │
│  │  task_loop, plan_event, … (existing)                       │        │
│  └─────────────────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────────────────┘
                                │
                                │ CLI tools / local services
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Agent Desktop                                    │
│  labwc + wayvnc                                                         │
│                                                                         │
│  ┌──────────────┐    inotify/timer    ┌───────────────────────┐         │
│  │  Screenshots  │ ─────────────────► │  screenshot-sync      │         │
│  │  (PNG files)  │                    │  (systemd user svc)   │         │
│  └──────────────┘                     └───────────┬───────────┘         │
│                                                   │ Immich API          │
│  ┌──────────────┐    ┌──────────────┐             │                     │
│  │  Voice        │───►│  whisper.cpp  │             │                     │
│  │  recordings   │    │  (local STT) │             │                     │
│  └──────────────┘    └──────┬───────┘             │                     │
│                             │ .txt transcript      │                     │
│  ┌──────────────┐    ┌──────┴───────┐             │                     │
│  │  PDF files    │───►│  Docling     │             │                     │
│  │              │    │  (PDF→MD)    │             │                     │
│  └──────────────┘    └──────┬───────┘             │                     │
│                             │ .md + bbox metadata  │                     │
│                             ▼                      ▼                     │
│                     ┌─────────────────────────────────────┐             │
│                     │  perception-processor                │             │
│                     │  (systemd user service, timer)       │             │
│                     │  - Collects transcripts, PDFs, photo │             │
│                     │    search results                    │             │
│                     │  - Queries Immich for face/text      │             │
│                     │  - Links faces → cardamum contacts   │             │
│                     │  - Writes structured summaries       │             │
│                     │  - Syncs into notes/ via repo-sync   │             │
│                     └─────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                │ Tailscale
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Server (ocean)                                   │
│                                                                         │
│  ┌───────────────────────────┐    ┌────────────────────────────┐       │
│  │  Immich (photos.domain)   │    │  Stalwart (mail.domain)    │       │
│  │  port 2283                │    │  CardDAV contacts           │       │
│  │  ML worker:               │    │  cardamum CLI reads/writes  │       │
│  │  - Face recognition       │    │  vCards                    │       │
│  │  - OCR text extraction    │    └────────────────────────────┘       │
│  │  - CLIP image search      │                                         │
│  └───────────────────────────┘                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Affected Modules

### Perception layer (existing scaffolding)
- `modules/os/agents/types.nix` — `perception` option group in agent submodule ✓
- `modules/os/agents/perception.nix` — systemd service skeletons for screenshot-sync and perception-processor ✓
- `modules/os/agents/scripts/screenshot-sync.sh` — **new**: inotify/timer watcher that uploads screenshots to Immich
- `modules/os/agents/scripts/perception-processor.sh` — **new**: collects outputs, queries Immich, links contacts, writes summaries
- `modules/os/agents/default.nix` — import perception.nix
- `modules/terminal/shell.nix` — installs `ks` into the normal terminal environment ✓
- `packages/ks/src/cmd/photos.rs` — `ks photos` Rust CLI for Immich search, people, download, and preview ✓
- `packages/ks/src/cmd/screenshots.rs` — `ks screenshots sync` Rust CLI for uploading local screenshots into Immich ✓
- `packages/perception-processor/` — **new**: activity summary builder
- `flake.nix` — add Docling, whisper.cpp packages; expose new packages

### Executive assistant layer (new)
- `modules/terminal/claude-code-commands/ks.assistant.md` — **new**: `/ks.assistant` slash command
- `modules/terminal/ai-extensions.nix` — add `assistantCommand.enable` option
- `.deepwork/jobs/executive_assistant/job.yml` — add `summarize_audio`, `review_photos`, `start_recording` workflows
- `.deepwork/jobs/executive_assistant/steps/` — step instruction files for new workflows

## Requirements

### PDF Processing

**REQ-023.1** The terminal module MUST provide a `docling` package capable of
converting PDF files to markdown.

**REQ-023.2** The PDF-to-markdown conversion MUST preserve document structure
(headings, tables, lists) in the output markdown.

**REQ-023.3** The conversion MUST produce bounding box metadata alongside the
markdown output so that each extracted element (paragraph, table cell, line)
can be traced to a specific page and region in the source PDF.

**REQ-023.4** The bounding box metadata MUST be stored in a sidecar JSON file
with the same basename as the output markdown (e.g., `document.md` and
`document.bbox.json`).

**REQ-023.5** Scanned PDFs (image-only pages) MUST be processed with OCR
before markdown conversion. Native text PDFs MUST be parsed directly without
OCR.

**REQ-023.6** The `docling` package SHOULD support GPU acceleration when
available but MUST fall back to CPU-only processing.

### Voice Recording and Transcription

**REQ-023.7** The terminal module MUST provide a `whisper.cpp` (or equivalent
local speech-to-text) package for audio transcription.

**REQ-023.8** Transcription MUST run entirely on local hardware. Audio data
MUST NOT be sent to any external service.

**REQ-023.9** The transcription tool MUST accept common audio formats (WAV,
MP3, OGG, M4A) as input and produce a plain text transcript as output.

**REQ-023.10** The transcription tool SHOULD produce timestamped segments
(e.g., `[00:01:23] sentence text`) to enable linking transcript sections
to audio positions.

**REQ-023.11** The transcription tool SHOULD support GPU acceleration when
available but MUST fall back to CPU-only processing.

**REQ-023.12** A voice recording helper script MAY be provided that uses
PipeWire to capture microphone input and save to a timestamped WAV file in
a configurable directory.

### Screenshot Syncing to Immich

**REQ-023.13** Each agent with `perception.enable = true` and
`desktop.enable = true` MUST run a `screenshot-sync` systemd user service
that watches the agent's screenshot directory for new PNG files.

**REQ-023.14** New screenshots MUST be uploaded to the Immich instance via
its API within the sync interval.

**REQ-023.15** The sync service MUST use a configurable timer interval,
defaulting to `*:0/5` (every 5 minutes).

**REQ-023.16** Uploaded screenshots MUST be tagged in Immich with the agent
name and host name for filtering.

**REQ-023.17** The sync service MUST track which files have been uploaded
(e.g., via a state file) to avoid duplicate uploads.

**REQ-023.18** The Immich API key MUST be managed as an agenix secret
(`agent-{name}-immich-api-key`).

### Photo and Screenshot Search

**REQ-023.19** The terminal module MUST provide `ks photos` as part of the
main `ks` CLI, and that command MUST query the Immich API for assets and
people.

**REQ-023.20** `ks photos search` MUST support structured search by:

- Face/person name, including multiple people filters
- Album name, including multiple album filters
- Tag value, including multiple tag filters
- Date range
- Asset type (image/photo, screenshot, video)
- Country, state, and city
- Camera make, camera model, and lens model
- File name and description metadata

**REQ-023.21** `ks photos search` MUST support text search across
Immich's smart-search surface, including generic context text and OCR-focused
queries.

**REQ-023.22** The tool MUST output results as structured JSON containing, at
minimum, asset ID, filename, date, type, original path, thumbnail URL, and
matched metadata.

**REQ-023.23** The tool MUST provide a `people` listing command so operators
can inspect discoverable Immich person names before issuing person-filtered
searches.

**REQ-023.24** The tool MUST authenticate via the Immich API key from the
agent's agenix secret.

**REQ-023.25** Immich's ML features (face recognition, CLIP, OCR) MUST be
enabled on the server. The `immich.nix` service module SHOULD emit a warning
if `perception` is enabled on any agent but Immich ML is not configured.

### Contact Linking

**REQ-023.26** The perception processor MUST be able to query Immich for
recognized face clusters and match them against CardDAV contacts via the
`cardamum` CLI.

**REQ-023.27** Matching SHOULD use the contact's display name and any
photo-tagged name from Immich. Exact matching MUST be tried first; fuzzy
matching MAY be used as a fallback.

**REQ-023.28** When a face cluster matches a contact, the perception
processor SHOULD update the Immich person name to match the contact's
canonical display name.

**REQ-023.29** The contact linking step MUST NOT create or modify CardDAV
contacts automatically. It MUST only read contacts for matching and update
Immich person labels.

### Activity Reconstruction and Notes Sync

**REQ-023.30** Each agent with `perception.enable = true` MUST run a
`perception-processor` systemd user service on a configurable timer,
defaulting to `*:0/30` (every 30 minutes).

**REQ-023.31** The perception processor MUST scan for new inputs since the
last run:

- PDF markdown outputs and their bounding box metadata
- Voice transcripts
- Immich search results (recent screenshots, tagged photos)

**REQ-023.32** The processor MUST produce a structured activity summary in
markdown format, suitable for inclusion in the agent's notes directory.

**REQ-023.33** The activity summary MUST include citations. For PDF-sourced
data, citations MUST reference the source file, page number, and line or
bounding box region. For voice transcripts, citations MUST reference the
audio file and timestamp.

**REQ-023.34** The activity summary MUST be written to the agent's notes
directory (e.g., `notes/perception/YYYY-MM-DD.md`) and synced via the
existing `repo-sync` service.

**REQ-023.35** The processor MAY use the local Ollama instance (if
`keystone.os.services.ollama.enable = true`) to generate natural-language
summaries from structured extraction outputs.

### Configuration

**REQ-023.36** The agent submodule MUST expose options at
`keystone.os.agents.<name>.perception`.

```nix
keystone.os.agents.drago = {
  perception = {
    enable = false;               # Enable perception layer

    pdf = {
      enable = true;              # PDF parsing (requires docling)
      inputDir = null;            # Watch directory (default: ~/documents/inbox)
      outputDir = null;           # Markdown output (default: ~/documents/parsed)
    };

    voice = {
      enable = true;              # Voice transcription (requires whisper.cpp)
      inputDir = null;            # Watch directory (default: ~/voice/inbox)
      outputDir = null;           # Transcript output (default: ~/voice/transcripts)
      model = "base";             # Whisper model size (tiny, base, small, medium, large)
    };

    screenshots = {
      enable = true;              # Screenshot sync to Immich
      syncOnCalendar = "*:0/5";   # Sync interval
    };

    contacts = {
      enable = true;              # Face → contact linking
    };

    processor = {
      enable = true;              # Activity reconstruction
      onCalendar = "*:0/30";      # Processing interval
      useOllama = false;          # Use Ollama for natural-language summaries
    };
  };
};
```

**REQ-023.37** When `perception.enable` is true, the sub-options (`pdf`,
`voice`, `screenshots`, `contacts`, `processor`) MUST default to
enabled. Individual sub-options MAY be disabled to exclude specific
capabilities.

**REQ-023.38** The terminal module MUST install `ks` when
`keystone.terminal.enable = true`, and `ks photos` MUST be available through
that normal CLI surface without a separate perception-specific terminal option.

### Integration

**REQ-023.39** The screenshot-sync service MUST coexist with the existing
screenshot tool (`keystone-screenshot`). Screenshots are produced by the
existing tool; the sync service only handles upload.

**REQ-023.40** The perception-processor MUST coexist with the existing
`agent-{name}-task-loop` service. They are complementary — the task loop
executes tasks, the perception processor ingests media.

**REQ-023.41** The perception module MUST integrate with the existing
`repo-sync` notes service for syncing activity summaries to the notes
repository.

**REQ-023.42** The PDF and voice processing tools MUST be available as
standalone CLI commands so that agents can invoke them from task loop
scripts, not only via the background processor.

### Security

**REQ-023.43** All media processing (PDF parsing, OCR, voice transcription,
image search) MUST run on local hardware. Data MUST NOT be transmitted to
external services.

**REQ-023.44** Immich API keys MUST be stored as agenix secrets and MUST NOT
appear in Nix store paths or configuration files.

**REQ-023.45** The perception processor MUST NOT modify or delete source
files (PDFs, audio recordings, screenshots). It operates read-only on
inputs and write-only to output directories.

**REQ-023.46** The contact linking step MUST NOT create, modify, or delete
CardDAV contacts. It MUST only read contacts for matching purposes.

### Executive Assistant: `/ks.assistant` Command

**REQ-023.47** A `/ks.assistant` slash command MUST be provided in the
Keystone Claude Code terminal module.

**REQ-023.48** The command MUST accept a natural-language request and route
it to the appropriate `executive_assistant` DeepWork workflow via the
DeepWork MCP server.

**REQ-023.49** Routing MUST cover all workflows in the `executive_assistant`
job: `plan_event`, `manage_calendar`, `clean_inbox`, `discover_events`,
`task_loop`, `portfolio_review`, `portfolio_review_one`, `summarize_audio`,
`review_photos`, and `start_recording`. Presentation requests MUST route to the
standalone `presentation` job instead, including its `presentation` and
`slide_deck` workflows.

> **Implementation note**: `summarize_audio`, `review_photos`, and
> `start_recording` are Phase 2 additions — they do not yet exist in
> `job.yml` and are tracked in plan issue #184 (Phase 5 tasks). The command
> MUST handle routing to a workflow that does not yet exist by informing
> the user it is not yet available.

**REQ-023.50** When the request does not match a known workflow, the command
MUST list available workflows and ask the user to clarify. It MUST NOT
silently fail or produce an empty response.

**REQ-023.51** The command MUST be enabled via a dedicated Nix option
(`keystone.terminal.assistantCommand.enable`). It MUST default to disabled.

### Executive Assistant: Audio Summarization

**REQ-023.52** The `executive_assistant` job MUST provide a `summarize_audio`
workflow with steps: `locate_recording`, `transcribe`, `summarize`,
`write_note`.

**REQ-023.53** The workflow MUST invoke `whisper.cpp` (REQ-023.7) for
transcription. It MUST NOT send audio to an external service.

**REQ-023.54** The workflow MUST summarize the transcript using the local
Ollama instance when available, falling back to structured extraction only.

**REQ-023.55** The workflow MUST write a zk note to the operator's notes
notebook with `source_ref` frontmatter linking to the source audio file.

### Executive Assistant: Photo Review

**REQ-023.56** The `executive_assistant` job MUST provide a `review_photos`
workflow with steps: `parse_query`, `search_immich`, `present_results`.

**REQ-023.57** The workflow MUST invoke `ks photos` (REQ-023.19) to
query Immich. It MUST support natural-language date ranges and person names
as query inputs.

**REQ-023.58** Results MUST be presented as a formatted list in the terminal
with filenames, dates, and asset identifiers. The workflow MAY optionally
write a zk note with the curation result.

### Executive Assistant: Recording Session

**REQ-023.59** The `executive_assistant` job MUST provide a `start_recording`
workflow with steps: `check_obs`, `start_session`, `log_note`.

**REQ-023.60** The workflow MUST connect to OBS via its WebSocket API to
start a recording on the active scene.

**REQ-023.61** OBS WebSocket credentials (host, port, password) MUST be
read from agenix-managed secrets. They MUST NOT be hardcoded.

**REQ-023.62** The workflow MUST write the session name and start timestamp
to the operator's active daily zk note.

**REQ-023.63** When OBS is not running or the WebSocket connection fails, the
workflow MUST emit a clear error message and exit without crashing.

## Edge Cases

- **Immich offline**: Screenshot sync buffers locally and retries on next
  timer tick. The state file tracks pending uploads.
- **No Ollama available**: The processor and `summarize_audio` workflow fall
  back to structured extraction only — no natural-language summaries.
- **Large PDFs**: Docling processes pages sequentially. For PDFs over 100
  pages, the processor SHOULD split into batches to avoid memory pressure.
- **No faces recognized**: Contact linking is a no-op when Immich has no
  face clusters. The processor MUST NOT fail.
- **Agent without desktop**: If `desktop.enable = false`, screenshot sync is
  automatically disabled. PDF and voice processing still function.
- **Multiple agents on same host**: Each agent has its own screenshot
  directory, Immich API key, and processing state. No shared state.
- **OBS not running**: `start_recording` workflow emits a clear error and
  exits cleanly. Daily note is not updated on failure.
- **No recording found**: `summarize_audio` workflow emits a clear message
  listing where it searched. It MUST NOT proceed with an empty transcript.
