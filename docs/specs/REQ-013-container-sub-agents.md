# REQ-013: Container Sub-Agent Management

Manage multiple AI sub-agents in Podman containers with dynamically
generated AGENTS.md files composed from archetype and role definitions.
Extends the existing `podman-agent` infrastructure.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Stories Covered

- US-005: Manage multiple sub-agents in containers

## Affected Modules

- `packages/podman-agent/podman-agent.sh` — extend with archetype-based AGENTS.md generation
- `modules/os/containers.nix` — Podman runtime configuration
- `modules/os/agents/` — sub-agent configuration options
- `modules/os/agents/` — archetype definitions and agent provisioning patterns (reference)
- `flake.nix` — updated overlay if new packages are needed

## Data Models

### Agent Archetype

Defines a reusable agent persona and configuration template.

| Field         | Type         | Required | Notes                                                             |
| ------------- | ------------ | -------- | ----------------------------------------------------------------- |
| name          | string       | yes      | Archetype identifier (e.g., `engineer`, `reviewer`, `researcher`) |
| description   | string       | yes      | One-line role description                                         |
| system_prompt | string       | yes      | Base system prompt for this archetype                             |
| conventions   | list[string] | no       | Convention files to include in AGENTS.md                          |
| tools         | list[string] | no       | MCP tools or CLI tools to enable                                  |
| model         | enum         | no       | Preferred model (`haiku`, `sonnet`, `opus`). Default: `sonnet`    |

### Agent Role

A project-specific instantiation of an archetype.

| Field           | Type         | Required | Notes                                                   |
| --------------- | ------------ | -------- | ------------------------------------------------------- |
| slug            | string       | yes      | Short identifier (e.g., `backend`, `frontend`, `tests`) |
| archetype       | string       | yes      | Reference to an archetype name                          |
| repos           | list[string] | no       | Subset of project repos this agent works on             |
| extra_context   | string       | no       | Additional context appended to AGENTS.md                |
| worktree_branch | string       | no       | Branch name for worktree isolation                      |

### Container Instance

Runtime state of a running sub-agent container.

| Field        | Type      | Source | Notes                                    |
| ------------ | --------- | ------ | ---------------------------------------- |
| container_id | string    | Podman | Container ID                             |
| name         | string    | Podman | Format: `{prefix}-{project}-{role_slug}` |
| status       | enum      | Podman | `running`, `exited`, `paused`            |
| project      | string    | Label  | Project slug                             |
| role         | string    | Label  | Role slug                                |
| archetype    | string    | Label  | Archetype name                           |
| created      | timestamp | Podman | Container creation time                  |

## CLI Contract

### `agentctl agent start <role_slug> [options]`

Launch a sub-agent in a Podman container.

**Options**:

- `--archetype <name>` — override the default archetype for this role
- `--model <model>` — override the model (haiku/sonnet/opus)
- `--branch <branch>` — worktree branch for isolation
- `--prompt <text>` — initial prompt to send to the agent
- `--detach` — run in background (default: interactive)

**Behavior**:

1. The command MUST resolve the current project from `$PROJECT_NAME` or error if not in a project session
2. The command MUST look up the role definition from the project configuration
3. The command MUST dynamically generate an AGENTS.md file by:
   a. Starting with the archetype's system prompt
   b. Appending relevant convention files
   c. Appending project-specific context from the role definition
   d. Appending aggregated repo AGENTS.md files
4. The command MUST launch a Podman container using the `podman-agent` script
5. The AGENTS.md MUST be volume-mounted into the container
6. The container MUST be labeled with `project={project}`, `role={role_slug}`, `archetype={name}`

**Exit codes**:

- `0` — container started (detach) or agent exited normally (interactive)
- `1` — configuration error (missing role, archetype, or project)
- Passthrough — agent exit code in interactive mode

### `agentctl agent list`

List running sub-agent containers for the current project.

**Behavior**:

1. The command MUST list Podman containers with label `project={current_project}`
2. Output MUST include: role slug, archetype, status, container name

**Output format** (stdout, tab-separated):

```
ROLE        ARCHETYPE    STATUS     CONTAINER
backend     engineer     running    obs-myapp-backend
frontend    engineer     running    obs-myapp-frontend
tests       reviewer     exited     obs-myapp-tests
```

### `agentctl agent stop <role_slug>`

Stop a running sub-agent container.

**Behavior**:

1. The command MUST find the container matching `{prefix}-{project}-{role_slug}`
2. The command MUST stop the container gracefully (SIGTERM, then SIGKILL after timeout)
3. If the container is not running, the command MUST print a warning and exit `0`

### `agentctl agent remove <role_slug>`

Remove a sub-agent container.

**Behavior**:

1. The command MUST stop the container if running
2. The command MUST remove the container
3. The command SHOULD NOT remove worktrees (managed separately via `process.git-repos`)

### `agentctl agent logs <role_slug>`

View logs from a sub-agent container.

**Behavior**:

1. The command MUST show stdout/stderr from the container via `podman logs`
2. `--follow` flag SHOULD be supported for live tailing

## Behavioral Requirements

### Dynamic AGENTS.md Generation

1. The system MUST support archetype definitions stored in a discoverable location (e.g., `{notes_path}/archetypes/{name}.md` or declarative Nix options).
2. AGENTS.md MUST be assembled at container launch time, not pre-generated.
3. The generated AGENTS.md MUST include:
   - Archetype system prompt
   - Project-specific role context
   - Relevant convention files
   - Repository AGENTS.md files (from declared repos)
4. The AGENTS.md MUST use `{name}` and `{email}` placeholders matching SPEC-007 FR-009 patterns.
5. Generated AGENTS.md files SHOULD be cached in `{notes_path}/.claude-projects/{project}/agents/{role_slug}/AGENTS.md` for debugging.

### Sandbox Scope

6. Podman sandboxing MUST only apply to automated sub-agents launched via
   `agentctl agent start`. Interactive sessions launched via `agentctl <agent>
claude` (and other AI tool commands) MUST run directly as the agent
   user without Podman, since the human operator is present and the agent
   has its own OS-level user isolation.
7. `agentctl` AI tool commands (`claude`, `gemini`, `codex`, `opencode`)
   MUST default to direct execution. The `--sandbox` flag MAY be provided
   to opt into Podman sandboxing for interactive sessions.

### Container Isolation

8. Each sub-agent MUST run in its own Podman container.
9. Containers MUST use the existing `podman-agent` infrastructure (Nix store volume, git worktree mounts, SSH forwarding).
10. Multiple containers MUST be able to run concurrently for the same project.
11. Container names MUST follow the pattern `{prefix}-{project}-{role_slug}` to enable filtering.
12. Containers MUST be labeled with metadata for querying: `project`, `role`, `archetype`.

### Container Lifecycle

11. Container start MUST be idempotent — if a container with the same name exists and is running, the command MUST attach to it instead of creating a duplicate.
12. Container stop MUST be graceful with a configurable timeout (default: 30 seconds).
13. Container removal MUST NOT affect persistent data (worktrees, Nix store volumes, project files).
14. The system SHOULD support auto-cleanup of exited containers after a configurable period.

### Resource Limits

15. Containers MUST have configurable memory limits (default: 4GB, per `podman-agent` defaults).
16. Containers MUST have configurable CPU limits (default: 4 cores, per `podman-agent` defaults).
17. Resource limits MAY be overridden per-role in the project configuration.

## Edge Cases

- **Name collision**: If two projects have the same slug (shouldn't happen per REQ-010.2 uniqueness), container names will collide. The command MUST detect and error on container name conflicts.
- **Orphaned containers**: If the launching terminal session is killed while containers are running, containers MUST continue running (they're independent processes). `agentctl agent list` from a new session MUST still find them.
- **Missing archetype**: If a role references a non-existent archetype, the command MUST fail with a descriptive error listing available archetypes.
- **Network access**: Containers inherit the host's network namespace by default in `podman-agent`. Sub-agents SHOULD be restricted to the same network rules as OS agents (SPEC-007 FR-006 firewall rules) when possible.
- **Credential isolation**: Each container MUST only have access to credentials explicitly mounted. Containers MUST NOT share API keys or tokens between roles unless configured.

## Future Considerations

- **Archetype marketplace**: Archetypes could be shared across projects via a centralized repository.
- **Inter-agent communication**: Sub-agents may need to coordinate (e.g., reviewer reads engineer's PR). This is out of scope for the initial implementation.
- **GPU passthrough**: For ML-focused archetypes, GPU access may be needed. Out of scope initially.
