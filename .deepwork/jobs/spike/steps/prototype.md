# Build Prototype

## Objective

Build a minimal proof-of-concept or code sketch that validates the spike's feasibility question based on research findings.

## Task

### Process

1. **Read inputs**
   - Read `spikes/[spike_name]/scope.md` for success criteria
   - Read `spikes/[spike_name]/research.md` for approach guidance

2. **Plan the prototype**
   - Identify the minimum code needed to answer the spike question
   - Keep it small: a single script, a config file, or a few focused files
   - **Use the project's established tooling and patterns.** A spike prototype is minimal, but it must use the same libraries, frameworks, and code patterns as the repo it will graduate into. Never reinvent or bypass existing infrastructure (e.g., never generate OpenSCAD via string concatenation when AnchorSCAD exists, never write raw SQL when an ORM is available, never hand-roll HTTP when the project has an API client). Check the project's repo for existing patterns before writing any code.

3. **Build it**
   - Create files under `spikes/[spike_name]/prototype/`
   - Include comments explaining what's being tested
   - If the prototype requires setup steps, add a brief `README.md` in the prototype directory

4. **Evaluate against success criteria**
   - Check each success criterion from scope.md
   - Note what worked, what didn't, and any surprises

5. **Capture iteration notes**
   - After prototyping, always reflect on what to change in the next revision
   - Document in a session log or CALIBRATION.md (for hardware) within the prototype directory
   - Categories to cover: what worked, what didn't, what was annoying, what needs redesign
   - For hardware prototypes: record measurements, calibration values, wiring changes, and part swaps as they happen — don't rely on memory after the session

## Output Format

### spikes/[spike_name]/prototype/

A directory containing prototype code. Structure depends on the spike, but typically:

```
prototype/
├── README.md          # (optional) Setup/run instructions
├── main.py            # or whatever language is appropriate
├── flake.nix          # (if Nix dev shell needed) Dev environment
├── .envrc             # (required if flake.nix exists) Contains: use flake
├── .gitignore         # (if build artifacts) Ignore result/, .direnv/, etc.
└── ...                # supporting files as needed
```

Each file should include a header comment:

```
# Spike: [spike_name]
# Testing: [what this file validates]
```

## Quality Criteria

- Prototype directly tests the spike question from scope.md
- Code is minimal — only what's needed to validate feasibility
- **Prototype uses the project's established tooling** — no raw/ad-hoc code generation when a framework or library already exists in the repo (e.g., AnchorSCAD for CAD, ORM for database, project API client for HTTP)
- Files include comments explaining what's being tested
- Results (what worked/didn't) are observable from running or reading the code
- Iteration notes captured: what to improve, redesign, or change for the next revision

## When to Build vs. Skip

Not every spike needs a full prototype:

- **Build** when the question is about feasibility — "can this work?" needs running code to answer
- **Demonstrate** when research already answers the question — create a minimal config or script showing the approach
- **Skip building** is never an option — always produce _something_ in `prototype/`, even if it's a single config file or annotated code sketch

If the prototype involves Nix flakes, infrastructure, or build outputs: ensure build artifacts are gitignored and document build/run steps in a prototype `README.md`. **Always include a `.envrc` with `use flake` alongside any `flake.nix`** so that direnv automatically activates the dev shell when entering the prototype directory.

## Context

The prototype exists to answer the spike question with evidence, not to build a feature. It's disposable. If the research step's findings already answer the question definitively, the prototype can be a minimal demonstration rather than an exploration.
