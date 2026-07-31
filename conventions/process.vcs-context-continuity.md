<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: VCS Context Continuity (process.vcs-context-continuity)

Standards for maintaining real-time visibility and state tracking on issues and
pull requests to ensure that any agent or human can seamlessly resume
in-flight work.

## Real-Time Progress Tracking

1. The `# Tasks` checklist in the PR body (or Issue body) MUST be updated
   immediately as each sub-task is completed.
2. If the implementation plan changes or a sub-task is found to be
   unnecessary, the checklist MUST be updated to reflect the new path.
3. If a task is skipped or pivoted, a brief comment MUST explain why the
   change was made.

## Environmental and Technical Blockers

4. Any difficulties encountered with the development environment (e.g.,
   missing dependencies, flakey tests, Nix evaluation errors) MUST be
   documented as a comment on the tracking Issue or PR. See `process.blocker`
   for the authoritative standard on escalating blockers.
5. If a "workaround" or temporary hack is required to proceed, it MUST be
   explicitly noted so the next agent understands the non-standard setup.
6. System-level issues that affect the developer experience (DX) SHOULD be
   reported as separate infrastructure issues while referencing the current
   task.

## Observable Evidence

7. Every PR MUST provide observable evidence of progress (screenshots for
   UI, terminal output code blocks for CLI, or video for complex interactions).
   See `tool.terminal-screenshots` for specific PNG rendering standards.
8. Evidence MUST be updated if subsequent changes significantly alter the
   observable behavior of the feature.
9. For backend or library changes, the demo MUST include logs or test output
   demonstrating the code working in a realistic scenario. See `process.pull-request`
   for structural PR requirements.

## Resumability and State

10. The PR/Issue history MUST provide enough context for another agent to
    understand the current delta between the stated Goal and the current
    branch state. See `process.task-tracking` for internal state standards.
11. Before pausing work, the agent MUST ensure all local changes are pushed
    to the remote branch and the platform (Issue/PR) accurately reflects
    the current progress.

## Golden Example

An agent is implementing a new UI component but hits a build issue:

### PR Body Update:

    # Tasks
    - [x] Create component scaffold
    - [x] Implement theme support
    - [ ] Add interaction tests
    - [ ] Update documentation

### Comment on PR:

    ## Technical Note: Build Environment

    The local `node_modules` required a manual `pnpm install --force` due to
    a version conflict in the shared archetype. I have noted this in the
    `# Tasks` for anyone picking up the next sub-task.

    ## Progress Demo
    ![Screenshot of the component in light and dark mode](https://example.com/demo.png)

    The interaction tests are currently failing because the test-runner cannot
    find the new fonts; I have pushed my WIP fixes to the branch.
