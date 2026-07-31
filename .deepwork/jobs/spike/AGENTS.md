# Job Management

This folder and its subfolders are managed using the `deepwork_jobs` slash commands.

## Recommended Commands

- `/deepwork_jobs.define` - Create or modify the job.yml specification
- `/deepwork_jobs.implement` - Generate step instruction files from the specification
- `/deepwork_jobs.learn` - Improve instructions based on execution learnings

## Directory Structure

```
.
├── AGENTS.md          # This file - project context and guidance
├── job.yml            # Job specification (created by /deepwork_jobs.define)
├── steps/             # Step instruction files (created by /deepwork_jobs.implement)
│   └── *.md           # One file per step
├── hooks/             # Custom validation scripts and prompts
│   └── *.md|*.sh      # Hook files referenced in job.yml
└── templates/         # Example file formats and templates
    └── *.md|*.yml     # Templates referenced in step instructions
```

## Editing Guidelines

1. **Use slash commands** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
3. **Run `/deepwork_jobs.learn`** after executing job steps to capture improvements
4. **Run `deepwork sync`** after any changes to regenerate commands

## Job-Specific Context

### Output Directory Pattern

Spikes use a top-level `spikes/` directory (git-tracked, excluded from zk indexing):

- Code artifacts and research: `spikes/[spike_name]/`
- zk report note (summary): `reports/` via `zk new`
- zk ADR (architectural decision): `decisions/` via `zk new`
- Symlink: `ln -s ../../../spikes/[spike_name] projects/[ProjectName]/spikes/[spike_name]`
- The project name is captured in scope.md metadata for use by the report step

### Project File Format

Next steps from spikes are scoped per spike entry in the project file, not in a global "Next Steps" section. See `steps/learn.md` for the output format template.

### Existing Spikes

Some older spikes exist directly in `projects/[project]/spikes/` (pre-v1.1.0) or in `spikes/` (pre-v1.4.0). These are not broken. New spikes should always use the top-level `spikes/` directory.

### zk Notes Repo Integration

When running spikes in a zk notes repo (`.zk/config.toml` present):

- `spikes/` MUST be in `ignore = [...]` under `[note]` in `.zk/config.toml` — code artifacts should not be indexed
- `spikes/` is **git-tracked**; do not add to `.gitignore`
- Report notes: `zk new --title "Spike: [name]" --no-input --print-path reports/`; set `report_kind: spike`, `source_ref`, project tag
- ADR notes: `zk new --title "[Decision]" --no-input --print-path decisions/`; fill Context/Decision/Consequences/Links
- ADRs are only created when the spike concluded with a clear architectural decision
- Add `project/<slug>` tag to both notes when a project was scoped
- Link both from the project hub note if one exists
- Run `zk index` after all notes are created

### Learnings from rpi-nixos-zfs-cluster (2026-02-03)

1. **Symlink link paths in learn.md**: The link in the project file must be relative to the project `.md` file location in `projects/`. Use `[project_folder]/spikes/[spike_name]/README.md`, not `spikes/[spike_name]/README.md` (which would resolve from repo root, not from the project file).

2. **Symlink validation in report hook**: Checking that a symlink "exists" is insufficient. Use `readlink -f` to verify it resolves to the actual spike directory containing files.

3. **Prototype step needs build guidance**: When prototypes involve Nix flakes or other build systems that produce large artifacts, the step should remind the agent to ensure outputs are gitignored and document build steps in a prototype README.

4. **Nix flakes require git-tracked files**: If the prototype uses a Nix flake, files must be git-tracked (at least `git add`) for `nix build` to see them. A temporary `git init` in the prototype dir or adding to the repo's staging area is needed.

5. **Cross-compilation via binfmt**: Building aarch64-linux images on x86_64-linux requires binfmt registration. The prototype step should note this dependency when targeting non-native architectures.

### Learnings from seed-starter-incubator-system (2026-02-07)

1. **Always capture iteration notes during prototyping**: Hands-on hardware spikes generate many observations about what to redesign (power, enclosure, wiring, sensor placement). These should be captured in real-time, not as an afterthought. The prototype step now includes an explicit "capture iteration notes" phase.

2. **Session logging for hardware spikes**: When prototyping physical hardware, record measurements, calibration values, wiring changes, and part swaps as they happen. A calibration log (e.g., `CALIBRATION.md`) in the prototype directory works well for this. See `spikes/seed-starter-incubator-system/prototype/CALIBRATION.md` for an example.

3. **Report template needs iteration notes section**: The README template now includes an "Iteration Notes" section between Evidence and Next Steps, ensuring design improvements are captured alongside findings.

4. **Grafana dashboards as spike artifacts**: When a spike involves Prometheus metrics, creating a Grafana dashboard and saving the JSON to the prototype directory makes the monitoring setup reproducible. See `spikes/seed-starter-incubator-system/prototype/grafana-dashboard.json`.

5. **ESPHome OTA flashing via Nix**: Use `nix develop -c esphome run/upload` when ESPHome is provided by a Nix dev shell. OTA uploads may fail on first attempt — retry is normal.

### Learnings from kicad-sensor-breakout (2026-03-03)

1. **Always include `.envrc` with `flake.nix`**: Every spike prototype that has a `flake.nix` must also have a `.envrc` containing `use flake`. Without it, users have to manually run `nix develop` and the dev shell doesn't activate automatically when entering the directory with direnv. The kicad spike was created without this and required manual `nix develop --command` invocations.

2. **Do not hand-author KiCad S-expression files**: KiCad's `.kicad_sch` and `.kicad_pcb` formats are text-based and git-friendly for diffing, but the parser is strict — no comments (`;;`), undocumented token ordering. Create empty templates and use the KiCad GUI for editing. Use `kicad-cli` only for automated export (Gerbers, ERC, DRC), not authoring.

3. **Spike prototype directories should be self-contained**: Users navigated to `spikes/kicad-sensor-breakout/` but the `flake.nix` was in `prototype/`. The Nix flake searched upward and found the vault root flake instead. Prototype directories with dev shells should be clearly documented as the entry point, or the `.envrc` should be at the spike root pointing into `prototype/`.

### Learnings from krpc-claude-pilot (2026-03-25)

1. **Symlink relative path requires 3 `..` segments**: The symlink lives at `projects/[Project]/spikes/[spike_name]` — that is 3 levels deep from the repo root (`projects/`, `[Project]/`, `spikes/`). To resolve back to the repo root you need `../../../`, not `../../`. The `../../` path was a carry-over error from an earlier layout. Both `report.md` and this file now use `../../../spikes/[spike_name]`. When writing the `ln -s` command, always count the path depth: `projects/X/spikes/` → 3 levels → `../../../`.

## Last Updated

- Date: 2026-03-25
- From conversation about: symlink depth bug — projects/[Project]/spikes/ is 3 levels deep, requires ../../../ not ../../ (v1.4.2)
