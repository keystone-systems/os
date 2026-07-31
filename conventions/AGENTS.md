# AGENTS.md — Conventions for Editing This Repo

## Purpose

This repo is a **shared, agent-agnostic** library. It provides composable role templates,
RFC 2119 convention docs, a composition tool, and an eval framework. It does NOT contain
agent-specific context (identity, schedules, tasks).

## File Conventions

### Role Templates (`roles/*.md`)

1. Every role file MUST follow the structure: H1 title → description → `## Behavior` → `## Output Format`.
2. Behavior rules MUST use `-` dashes and RFC 2119 keywords (MUST, SHOULD, MAY, etc.).
3. Role files MUST NOT reference specific agents, people, or organizations.
4. Output Format sections MUST include a template showing the expected structure.

### Convention Docs (`conventions/*.md`)

1. Convention files MUST NOT contain the RFC 2119 header comment.
2. The H1 title MUST follow the format `# Convention: {Display Name} ({prefix.name})`.
3. Naming: `{prefix}.{topic}.md` — prefixes are `process` (for operational procedures) and `tool` (for CLI/tool manuals).
4. Rules MUST be numbered within each section.
5. System-level requirements handled by Keystone (signing, SSH, email, MCP) MUST be documented in `os.requirements.md`.

### Archetypes (`archetypes.yaml`)

1. Every archetype (e.g., `engineer`, `product`) MUST be defined in `archetypes.yaml`.
2. `inlined_conventions`: Critical operational processes (`process.*`) whose full text is printed into `AGENTS.md`.
3. `referenced_conventions`: Manuals and background info (`tool.*` or advanced `process.*`) provided as standard markdown links `[name](path)` for on-demand context.

### Manifest Schema

1. Manifests MUST declare `agents_repo` — the path to the shared agents repo.
2. Manifests MUST declare `archetype` — the role-based archetype for `AGENTS.md` generation.
3. Manifests MUST declare `defaults.shared` — list of shared fragment filenames.
4. Manifests MUST declare `modes` — map of mode names to `roles` and `conventions` lists for prompt composition.

### Composition (`compose.sh`)

1. `compose.sh` takes exactly two positional arguments: `<manifest> <mode>`.
2. `agents_repo` is resolved from the manifest YAML, not passed as a flag.
3. Changes to `compose.sh` MUST preserve the output order: shared → roles → conventions.
4. `compose.sh` MUST remain POSIX-compatible (no bashisms beyond what `yq` requires).

### Evals (`evals/`)

1. `evals/run.sh` takes two positional arguments: `<manifest> <case>` with optional `--dry-run`.
2. Mode is read from the case YAML, not passed separately.
3. Test cases MUST be YAML files in `evals/cases/`.
4. Each case MUST have `name`, `mode`, and `cases[]` with `id`, `input`, and `assertions`.
5. Assertions support: `contains`, `not_contains`, `starts_with`, `matches` (regex).

## Git Conventions

- Branch naming: `feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `test/`
- Commit messages: semantic style (`feat: add architect role`, `fix: compose.sh path resolution`)
- All work happens on feature branches, merged via PR

## Adding New Content

- **New role**: Create `roles/{name}.md`, add an eval case, update README if needed.
- **New convention**: Create `conventions/{prefix}.{topic}.md`, update README if needed.
- **New shared fragment**: Create `shared/{name}.md`, reference in compose.sh if auto-included.
