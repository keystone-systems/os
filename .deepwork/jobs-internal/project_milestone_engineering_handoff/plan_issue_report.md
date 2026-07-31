# Plan Issue Report: Projctl Terminal Session Management

## Platform

- **Platform**: github
- **Repository**: ncrmro/keystone

## Plan Issue

- **Number**: #108
- **Title**: Plan: Projctl Terminal Session Management
- **URL**: https://github.com/ncrmro/keystone/issues/108
- **Milestone**: Projctl Terminal Session Management
- **Assignee**: kdrgo (Drago)
- **Labels**: engineering, plan

## References

- **Milestone Issue**: #102
- **Specs PR**: #107 (https://github.com/ncrmro/keystone/pull/107)

## Stories Included

| Story                                              | Happy Path | Tests | Mockup | Demo |
| -------------------------------------------------- | ---------- | ----- | ------ | ---- |
| US-001: Create named terminal sessions per project | yes        | yes   | yes    | yes  |
| US-002: Resume existing terminal sessions          | yes        | yes   | yes    | yes  |
| US-003: List terminal sessions by project          | yes        | yes   | yes    | yes  |
| US-004: Launch sub-agent sessions in worktrees     | yes        | yes   | yes    | yes  |
| US-005: Manage multiple sub-agents in containers   | yes        | yes   | yes    | yes  |

## Implementation Order

- **Phase 1** (Foundation): Home-manager module + project directory convention — no dependencies, parallel
- **Phase 2** (Core Sessions): US-001, US-002, US-003 via `pz` CLI — parallel, depends on Phase 1
- **Phase 3** (Agent Launcher): US-004 split into 3 sub-tasks (basic, worktree, system prompt) — depends on Phase 1
- **Phase 4** (Container Agents): US-005 split into 3 sub-tasks (archetypes, CLI, multi-container) — depends on Phase 3, lower priority

## Feature Flags

None required. All features gated behind `keystone.projects.enable` module option.

## Notes

- US-004 and US-005 were split per the scope analysis recommendations: US-004 into 3 parts (basic pclaude, worktree integration, system prompt rendering) and US-005 into 3 parts (archetype definitions, CLI subcommands, multi-container support).
- All design mockups are ASCII-based terminal interactions since the feature is CLI-only (no GUI components).
- Test expectations follow TDD red/green patterns describing what should fail before and pass after each implementation.
