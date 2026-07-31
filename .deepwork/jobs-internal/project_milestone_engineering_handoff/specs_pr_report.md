# Specs PR Report: Projctl Terminal Session Management

## Platform

- **Platform**: github
- **Repository**: ncrmro/keystone
- **Branch**: docs/specs-projctl-terminal-session-management

## Draft PR

- **Number**: 107
- **Title**: docs(specs): functional requirement specs for projctl terminal session management
- **URL**: https://github.com/ncrmro/keystone/pull/107
- **Reviewers**: ncrmro (Nicholas Romero), luce-ncrmro (Luce)

## Spec Files Created

| File                                      | Boundary                                 | Stories Covered        |
| ----------------------------------------- | ---------------------------------------- | ---------------------- |
| `specs/REQ-011-project-sessions.md`       | Project Discovery + Zellij Session Layer | US-001, US-002, US-003 |
| `specs/REQ-012-pclaude-agent-launcher.md` | Agent + Worktree Integration             | US-004                 |
| `specs/REQ-013-container-sub-agents.md`   | Container Sub-Agent Management           | US-005                 |

## Spec Summary

### specs/REQ-011-project-sessions.md

- **Boundary**: Project Discovery Layer + Zellij Session Layer + Home Manager Module
- **Key requirements**: `pz` CLI MUST create/attach Zellij sessions named `{prefix}-{slug}`, MUST discover projects from `{notes_path}/projects/*/README.md`, MUST provide shell completions for Zsh and Bash
- **Data contracts**: Project model (slug, path, readme, repos), Session model (name, slug, status, created), CLI commands (`pz <slug>`, `pz list`, `pz kill`), environment variables (PROJECT_NAME, PROJECT_PATH, etc.)

### specs/REQ-012-pclaude-agent-launcher.md

- **Boundary**: Agent + Worktree Integration
- **Key requirements**: `pclaude` MUST launch Claude Code with project-scoped config directory, MUST render system prompt via `envsubst`, MUST support `--resume` and `--worktree` flags, MUST aggregate AGENTS.md from declared repos
- **Data contracts**: Claude config directory structure, agent environment variables, CLI commands (`pclaude [slug]`, `pclaude list`), system prompt template rendering

### specs/REQ-013-container-sub-agents.md

- **Boundary**: Container Sub-Agent Management
- **Key requirements**: Sub-agents MUST run in Podman containers with dynamically generated AGENT.md, MUST support concurrent containers per project, container names MUST follow `{prefix}-{project}-{role}` pattern, MUST extend existing `podman-agent` infrastructure
- **Data contracts**: Agent Archetype model, Agent Role model, Container Instance model, CLI commands (`pz agent start/list/stop/remove/logs`)

## Notes

- All three specs reference and extend the existing REQ-010 (Projects) requirements document, which already defines core project discovery and session management behavior.
- REQ-013 (Container Sub-Agents) has open design questions around archetype storage format (files vs Nix options) flagged in the scope analysis ambiguities. These should be resolved during PR review.
- The Home Manager Module boundary (boundary 3 from scope analysis) is distributed across all three specs since `modules/terminal/projects.nix` serves as the integration point for all features.
- The Nix Overlay boundary (boundary 5) is infrastructure work covered implicitly by each spec's "Affected Modules" section — no dedicated spec is needed.
