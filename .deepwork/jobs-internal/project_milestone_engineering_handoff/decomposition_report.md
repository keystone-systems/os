# Decomposition Report: Projctl Terminal Session Management

## Platform

- **Platform**: github
- **Repository**: ncrmro/keystone

## Plan Issue

- **Number**: #108
- **URL**: https://github.com/ncrmro/keystone/issues/108

## Child Issues Created

### Infrastructure (chore)

| #   | Issue | Title                                                     | Dependencies | Stories                        |
| --- | ----- | --------------------------------------------------------- | ------------ | ------------------------------ |
| 1   | #110  | chore: add keystone.projects home-manager module scaffold | None         | US-001, US-002, US-003, US-004 |
| 2   | #111  | chore: add pz package to overlay                          | None         | US-001, US-002, US-003         |
| 3   | #115  | chore: add pclaude package to overlay                     | None         | US-004                         |
| 4   | #114  | chore: add shell completions for pz                       | #110, #111   | US-001                         |

### Features (feat)

| #   | Issue | Title                                                     | Dependencies | Stories        | Feature Flag |
| --- | ----- | --------------------------------------------------------- | ------------ | -------------- | ------------ |
| 5   | #112  | feat: create and attach to project Zellij sessions via pz | #110, #111   | US-001, US-002 | —            |
| 6   | #113  | feat: list project sessions via pz list                   | #111         | US-003         | —            |
| 7   | #116  | feat: launch Claude Code with project context via pclaude | #110, #115   | US-004         | —            |
| 8   | #117  | feat: add worktree integration to pclaude                 | #116         | US-004         | —            |
| 9   | #118  | feat: add system prompt rendering and --resume to pclaude | #116         | US-004         | —            |
| 10  | #119  | feat: add dynamic AGENT.md generation from archetypes     | #118         | US-005         | —            |
| 11  | #120  | feat: add pz agent subcommands for container lifecycle    | #119, #111   | US-005         | —            |

## Phased Dependency Graph

### Phase 1: Infrastructure (parallel — no dependencies)

- #110 chore: projects module scaffold
- #111 chore: pz package
- #115 chore: pclaude package

### Phase 2: Core Sessions (parallel — depends on Phase 1)

- #112 feat: pz create/attach (depends on #110, #111)
- #113 feat: pz list (depends on #111)
- #114 chore: pz completions (depends on #110, #111)

### Phase 3: Agent Launcher (depends on Phase 1)

- #116 feat: pclaude basic (depends on #110, #115)
- #117 feat: pclaude worktree (depends on #116)
- #118 feat: pclaude prompt/resume (depends on #116)

### Phase 4: Container Agents (depends on Phase 3, lower priority)

- #119 feat: AGENT.md generation (depends on #118)
- #120 feat: pz agent subcommands (depends on #119, #111)

## Coverage Matrix

| User Story                              | Child Issues                 |
| --------------------------------------- | ---------------------------- |
| US-001: Create named terminal sessions  | #110, #111, #112, #114       |
| US-002: Resume existing sessions        | #110, #111, #112             |
| US-003: List sessions by project        | #111, #113                   |
| US-004: Launch sub-agent in worktrees   | #110, #115, #116, #117, #118 |
| US-005: Manage sub-agents in containers | #119, #120                   |

## Future Work (out of milestone scope)

- Desktop integration: Walker plugin and Hyprland menu for project launch (REQ-010.18–010.20)
- Inter-agent communication between container sub-agents
- GPU passthrough for ML-focused archetypes
- Archetype marketplace for sharing across projects

## Statistics

- **Total issues**: 11
- **Infrastructure (chore)**: 4
- **Features (feat)**: 7
- **Tests (test)**: 0 (tests are included within feat issues per acceptance criteria)
- **Avg files per issue**: 2-3

## Notes

- No separate `test:` issues were created because each feature issue includes testable acceptance criteria. Integration tests can be added as a follow-up if needed.
- US-004 was split into 3 issues (basic, worktree, prompt/resume) per the scope analysis recommendation, allowing incremental delivery.
- US-005 was split into 2 issues (AGENT.md generation, CLI subcommands) — the archetype system design (scope analysis ambiguity #1) should be resolved during #119 implementation.
- All features are gated behind `keystone.projects.enable` — no separate feature flags needed.
- Phase 2 and Phase 3 can run in parallel since they share no code dependencies (pz vs pclaude).
