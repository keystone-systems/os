# Plan

## Objective

Create a git worktree branch off main, analyze the user's goal, and produce a concrete implementation plan with validation criteria defined up front.

## Task

Take the user's goal and translate it into an actionable implementation plan. The plan must be specific enough that another agent (or yourself in the next step) can execute it without ambiguity.

### Process

1. **Understand the goal**
   - Read the user's goal input carefully
   - Ask structured questions if the goal is ambiguous or underspecified
   - Identify which keystone modules/packages are likely affected

2. **Create the worktree**
   - Derive a branch name from the goal (e.g., `feat/add-ollama-module`, `fix/tpm-unlock-race`)
   - Follow conventional branch naming: `feat/`, `fix/`, `refactor/`, `chore/`, `docs/`
   - Create the worktree: `git worktree add .claude/worktrees/<branch-name> -b <branch-name>`

3. **Analyze the scope**
   - Read the relevant source files to understand the current state
   - Determine if changes are **OS-level** (modules/os/, modules/server/, flake.nix) or **home-manager-only** (modules/terminal/, modules/desktop/home/)
   - This distinction matters for the build step — OS changes require full nix build, home-manager-only changes can use the fast `ks build` path

4. **Define validation criteria**
   - For every change, define how to verify it works BEFORE starting implementation
   - Include: what commands to run, what output to expect, what "success" looks like
   - Validation criteria must be concrete and testable — not "it should work"

5. **Write the plan**
   - List specific files to create or modify
   - Order steps logically (dependencies first)
   - Note any risks or things that could go wrong

## Output Format

### plan.md

```markdown
# Implementation Plan

## Goal

[Restate the user's goal in precise terms]

## Branch

- **Name**: `<branch-name>`
- **Worktree**: `.claude/worktrees/<branch-name>`

## Scope

- **Change type**: [OS-level | home-manager-only | both]
- **Build strategy**: [full nix build | ks build (home-manager only)]
- **Affected modules**: [list of module paths]

## Validation Criteria

These criteria MUST be satisfied before the work is considered complete:

1. [Concrete, testable criterion — e.g., "nix flake check --no-build passes"]
2. [Another criterion — e.g., "new option evaluates correctly in agent-evaluation.nix test"]
3. [Runtime criterion — e.g., "ks doctor shows no new warnings after deploy"]

## Steps

### 1. [First change]

- **File**: `path/to/file.nix`
- **Change**: [What to do and why]

### 2. [Second change]

- **File**: `path/to/other-file.nix`
- **Change**: [What to do and why]

[Continue for all changes...]

## Risks

- [Anything that could go wrong or needs extra care]
```

## Quality Criteria

- The plan has concrete, ordered implementation steps — not vague goals
- The plan identifies specific files that will be created or modified
- The plan includes clear validation criteria that are testable
- The change type (OS-level vs home-manager-only) is correctly identified
- A worktree branch has been created with a descriptive name

## Context

This is the first step in the keystone development lifecycle. A good plan prevents wasted cycles in later steps. The validation criteria defined here will be checked in the final validate step after deployment, so they must be precise enough to verify on a live system.
