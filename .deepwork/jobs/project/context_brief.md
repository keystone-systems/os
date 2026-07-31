# Context Brief: Keystone Project Agent

## Project

- **Name**: Keystone Project Agent
- **Mission**: Give Keystone users a project-aware AI operator that can pick up the right repo, notes, session, and desktop context without forcing the user to manually reconstruct working state every time.

## Customer

- **Segment**: Technical operators and developers who run their own infrastructure with Keystone
- **Role/Context**: They work across multiple active projects, switch between terminal and desktop flows, and use AI tools inside project-scoped repos, notes, and sessions
- **Primary Need**: Reliable project context continuity so they can hand work to an agent or resume work themselves without losing the current project, repo, or session state

## Problem

Keystone already introduced strong building blocks for project context, but they are still experienced as separate systems. `pz` made terminal sessions project-aware and became the source of truth for project/session state, while the desktop context menus were later reshaped to delegate to that terminal-first model instead of keeping parallel logic. Even with that progress, a user who wants an agent to help on a live project still has to remember the project slug, pick the right session, choose the correct repo or worktree, and then launch the AI tool in that exact surface. The result is friction at the moment work should start: too many manual context decisions, too many ways to land in the wrong repo or session, and no single project-aware agent entry point.

## Solution

Keystone Project Agent turns those earlier systems into a direct operator experience. It uses the note-backed project model, `pz` session semantics, and desktop context entry points as one continuous workflow, so the user can start or resume a project-aware agent with the right project, repo, worktree, and session already attached. Instead of treating `pz`, desktop context switching, and agent launch as separate tools to coordinate by hand, the agent makes them feel like one project surface that opens in the right place and stays aligned with the same source of truth.

## Key Claims

- Start an AI agent inside the correct Keystone project context without re-entering project metadata by hand
- Reuse the existing `pz` project/session model as the source of truth for terminal and agent workflows
- Carry project context cleanly across terminal and desktop entry points instead of maintaining parallel state systems
- Support repo- and worktree-scoped execution so the agent operates in the same working surface a human would use

## Call to Action

Launch Keystone Project Agent from your project context and let it open the right session, repo, and worktree for the task already in front of you.

## Scope Notes

This implies building or tightening: a project-aware launch path on top of `pz` and `agentctl`; explicit project, session, repo, and worktree selection rules for agent startup; environment and context-file propagation so AI tools inherit the same project metadata a human session gets; attach-or-create behavior that respects existing Zellij sessions; and a desktop launcher path that reuses the same terminal-first discovery and state model instead of inventing separate desktop-only project state.
