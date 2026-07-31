# Presentation Job

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended workflows

- `presentation/presentation` - Full lifecycle: requirements, media, outline,
  deck, review, and delivery
- `presentation/slide_deck` - Build a Slidev deck from existing source content
- `deepwork_jobs/new_job` - Structural changes to this job
- `deepwork_jobs/learn` - Capture instruction improvements after running the job

## Directory structure

```
.
├── AGENTS.md
├── job.yml
└── steps/
    └── *.md
```

## Editing guidelines

1. Use workflows for structural changes such as adding steps or modifying
   `job.yml`.
2. Direct edits are fine for small instruction wording fixes.

## Job-specific context

- This job owns all presentation-specific DeepWork workflows. Do not add
  presentation workflows back into `executive_assistant`.
- The primary workflow is `presentation`. It handles requirements, optional
  Immich media search, Slidev generation, review, and notes-repo delivery.
- The `slide_deck` workflow is a narrower path for turning existing source
  material into a Slidev deck without running the full presentation workflow.
- Final presentation assets live under the configured notes dir `presentations/<slug>/` (`~/notes` for Keystone human users).
- Missing media or unresolved content MUST stay explicit as `TODO` comments in
  the deck and delivery artifacts.

## Last updated

- 2026-03-30: Split `presentation` and `slide_deck` out of
  `executive_assistant` into this standalone job to match `process.deepwork-job`
  capability boundaries.
