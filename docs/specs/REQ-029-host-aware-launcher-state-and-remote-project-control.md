# REQ-029: Host-aware launcher state and remote project control

Requirements for the synced launcher state shared by Walker and `agentctl`,
plus the host-aware remote project and agent control flows built on
top of it.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Scope

This spec defines:

- a synced persisted state model for desktop and terminal launcher defaults,
- host-aware project launching through terminal-first project tooling,
- desktop and terminal editing of interactive provider and model defaults, and
- the agent control surface used by the Alt+Escape menu.

This spec does not redefine task-loop execution defaults. Task-loop provider and
model selection remain governed by existing task and agent config.

## Functional requirements

### Source of truth (hla-state-001)

- **hla-state-001.1**: Interactive launcher state MUST be stored in a synced notes-backed file under `NOTES_DIR`.
- **hla-state-001.2**: The state file MUST remain machine-readable and reviewable.
- **hla-state-001.3**: Missing state files MUST be created lazily with valid default structure.
- **hla-state-001.4**: Missing keys or partial state MUST degrade gracefully.

### Project target hosts (hla-project-001)

- **hla-project-001.1**: The system MUST support a default project target host per origin host.
- **hla-project-001.2**: Walker and terminal-first project tooling MUST resolve the effective project target host from synced state before falling back to the local host.
- **hla-project-001.3**: Walker MUST show all declared hosts from the Keystone host inventory.
- **hla-project-001.4**: Project launches to a remote host MUST delegate to terminal-first project tooling.

### Remote transport (hla-remote-001)

- **hla-remote-001.1**: Remote project opens initiated from Walker or terminal-first project tooling MUST use Eternal Terminal as the interactive transport.
- **hla-remote-001.2**: The local desktop MUST open a local terminal window for the remote session rather than relying on remote desktop focus.
- **hla-remote-001.3**: The selected remote host MUST own the actual Zellij session attach or create behavior.
- **hla-remote-001.4**: Non-interactive host queries MAY use a different transport, provided they remain terminal-first.

### Interactive model defaults (hla-model-001)

- **hla-model-001.1**: The system MUST support project-scoped interactive provider, model, and fallback model overrides.
- **hla-model-001.2**: The system MUST support agent-scoped interactive preferred host, provider, model, and fallback model overrides.
- **hla-model-001.3**: Walker and `agentctl` SHOULD expose the same effective interactive defaults for a given project or agent.
- **hla-model-001.4**: These interactive defaults MUST NOT change task-loop execution defaults.

### Agent menu behavior (hla-agent-001)

- **hla-agent-001.1**: The Alt+Escape menu MUST include an `Agents` section.
- **hla-agent-001.2**: The agent list MUST show each declared agent and its effective preferred host.
- **hla-agent-001.3**: The agent actions view MUST support pause and resume.
- **hla-agent-001.4**: The agent actions view MUST support editing interactive preferred host, provider, model, and fallback model.
- **hla-agent-001.5**: Agent actions MUST remain terminal-first and delegate to `agentctl`.
