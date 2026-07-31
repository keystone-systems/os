# REQ-007: OS Agents

Enable LLM-driven agents to operate as first-class OS users with their own
Wayland desktop, email, credentials, and SSH identity — all managed
declaratively through Keystone's NixOS module system.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Problem Statement

LLM-driven agents currently lack persistent OS-level identity. They cannot:

1. Browse the web with a real browser session
2. Send or receive email
3. Authenticate to third-party services with their own credentials
4. Sign git commits with a verifiable identity
5. Be observed in real-time by a human operator viewing their desktop

OS agents need a persistent identity and environment that survives reboots,
integrates with the host's service stack, and can be remotely observed over
the mesh network.

## Functional Requirements

### FR-001: Agent User Provisioning

- The system MUST create each agent as a standard NixOS user at `/home/agent-{name}`
- The system MUST expose a `keystone.os.agents.{name}` option parallel to `keystone.os.users`
- Agent users MUST NOT have interactive password login at the console
- Agent users MUST belong to a shared `agents` group
- The system MUST allocate agent UIDs from a reserved range (e.g., 4000+) to avoid collision with human users
- The system MUST create the home directory per storage backend (ZFS dataset or ext4 directory), matching existing `keystone.os.users` patterns
- Each agent MUST have a home-manager configuration managed at the OS level (NixOS module, not standalone home-manager)
- Agent and human user home-manager configs MUST share common modules (terminal, git, shell) to avoid duplicating configuration
- Agent-specific home-manager options (e.g., `desktop.compositor`, MCP tools) SHOULD be layered on top of the shared base
- The `keystone.os.agents.{name}.terminal.enable` option MUST reuse the same `keystone.terminal` home-manager module used by `keystone.os.users`

### FR-002: Headless Wayland Desktop

- Each agent MUST have its own Wayland compositor session
- The compositor MUST run as a systemd user service under the agent's account
- A VNC server MUST expose the desktop for remote viewing
- The human operator MUST be able to connect to the agent's desktop from the same machine or a remote machine over Headscale
- The desktop MUST auto-start on boot and restart on crash
- Resolution and display settings SHOULD be configurable per-agent

### FR-003: Chrome Browser with DevTools MCP

- The system MUST install Chrome/Chromium and auto-launch it on the agent's desktop
- Chrome MUST start with remote debugging enabled (`--remote-debugging-port={debugPort}`)
- The Chrome DevTools MCP server MUST use the `chrome-devtools-mcp` npm package
- The MCP server MUST connect to the agent's Chrome instance via `--browserUrl http://127.0.0.1:{debugPort}`
- The MCP server MUST use stdio transport — each MCP consumer launches its own ephemeral process; there SHALL NOT be a long-running MCP systemd service
- Multiple MCP clients MUST be able to connect to the same Chrome debug port simultaneously
- Human user accounts on the same host MUST be able to launch a `chrome-devtools-mcp` process connecting to any agent's Chrome debug port
- The Chrome profile MUST persist in the agent's home directory
- Extensions SHOULD be pre-installable declaratively

### FR-004: Email via Stalwart

- Each agent MUST have a Stalwart mail account (e.g., `agent-{name}@{domain}`)
- IMAP/SMTP credentials MUST be generated and stored in agenix
- A CLI mail client MUST be configured in the agent's environment
- The agent MUST be able to send and receive email programmatically
- CalDAV/CardDAV access SHOULD be provisioned alongside the mail account

### FR-005: Bitwarden Account

- Each agent MUST have a Bitwarden account on the org's Vaultwarden instance
- API credentials (client ID, client secret) MUST be stored in agenix
- The Bitwarden CLI (`bw`) MUST be installed and pre-configured for the agent
- The agent MUST be able to retrieve credentials programmatically without human intervention
- A dedicated Bitwarden collection MUST scope the agent's accessible secrets

### FR-006: Tailscale Identity

- Each agent MUST have its own Tailscale auth key (pre-auth, reusable)
- The agent MUST join the Headscale/Tailscale network with a unique hostname (`agent-{name}`)
- The agent's desktop MUST be reachable over the tailnet for remote viewing
- Auth keys MUST be stored in agenix and SHOULD be rotated on a configurable schedule
- Firewall rules MUST restrict the agent's network access to declared services only

### FR-007: SSH Key Management

- The system MUST generate an ed25519 SSH keypair for each agent at provisioning time
- The private key MUST be encrypted with a passphrase stored in agenix
- An `ssh-agent` systemd user service MUST auto-start and unlock the key using the passphrase from agenix
- The agent's SSH key MUST be added to its own `~/.ssh/authorized_keys` (for sandbox access)
- Git MUST be configured to use the SSH key for signing commits (`user.signingkey`, `gpg.format = ssh`)
- The public key MUST be exported for registration on GitHub/GitLab/etc.

### FR-008: Agenix Secrets Management

The system MUST manage all agent secrets via agenix with a consistent structure:

- `/run/agenix/agent-{name}-ssh-key` — SSH private key
- `/run/agenix/agent-{name}-ssh-passphrase` — SSH key passphrase
- `/run/agenix/agent-{name}-mail-password` — Stalwart IMAP/SMTP password
- `/run/agenix/agent-{name}-bitwarden-client-secret` — Bitwarden API secret
- `/run/agenix/agent-{name}-tailscale-auth-key` — Tailscale pre-auth key

Secrets:

- MUST be encrypted to the host's SSH host key and the admin's personal key
- MUST be readable only by the agent's user account (via agenix `owner`/`group`)
- MUST be rotatable without reboot (systemd reload triggers re-decryption)

### FR-009: Agent Space — Workspace Structure

- The system MUST support two modes of agent-space provisioning:
  - **Clone mode** (`space.repo`): Clone an existing repository into `/home/agent-{name}/agent-space/`
  - **Scaffold mode** (default): Create and initialize `/home/agent-{name}/agent-space/` with standard files
- The agent-space MUST be git-initialized with a Forgejo remote on the host (or configurable remote)
- The agent-space MUST contain the following standard files:
  - `TASKS.yaml` — Current task queue (see FR-010 for schema)
  - `PROJECTS.yaml` — Projects the agent is responsible for
  - `ISSUES.yaml` — Known issues and incident log (see FR-014)
  - `SCHEDULES.yaml` — Recurring and scheduled work with DeepWork workflow references
  - `SOUL.md` — Agent identity: name, display name, email, and accounts table
  - `HUMAN.md` — Human operator: name and email
  - `AGENTS.md` — Operational context, conventions, and bespoke learnings
  - `CLAUDE.md` — MUST be a symlink to `AGENTS.md`
  - `ARCHITECTURE.md` — System architecture the agent operates within
  - `REQUIREMENTS.md` — Standing requirements and constraints
  - `SERVICES.md` — Services the agent can access (intranet table)
- The agent-space MUST contain `.repos/`, `logs/`, `bin/`, `.deepwork/jobs/` directories
- The agent-space MUST contain a `flake.nix` providing the agent's dev shell (see FR-017)
- Identity documents (`SOUL.md`, `HUMAN.md`) MUST be auto-populated from `keystone.os.agents.{name}` configuration
- The agent MUST be able to commit and push changes to its agent-space repository
- Scaffold mode MUST create `.cronjobs/` directory with `shared/{lib.sh,config.sh,setup.sh}` (see FR-016)

### FR-010: Task Loop — Autonomous Work Orchestration

- The system MUST provide a two-tier systemd timer architecture:
  - A scheduler timer (daily, default `*-*-* 05:00:00`) that ingests new work from external sources
  - A task-loop timer (configurable interval, default `*:0/5`) that processes the task queue
- The task-loop `run.sh` MUST live in the agent-space (not the Nix store), so the agent MAY modify its own loop behavior
- The scheduler MUST ingest tasks from configurable sources: GitHub/Forgejo issues, email, `SCHEDULES.yaml` recurring entries
- The task loop MUST include a pre-fetch pipeline step that iterates `PROJECTS.yaml` sources
- The task loop MUST follow a pre-fetch, ingest, prioritize, execute cycle driven by the LLM
- The task loop MUST use hash-based change detection to skip unchanged source data
- The task loop MUST use lock management to prevent concurrent executions
- The task loop MUST honor a pause marker in its state directory and exit before pre-fetch, ingest, prioritize, or execute work when paused
- The task loop MUST implement configurable stop conditions (max tasks per run, max wall time, error threshold)
- The task loop MUST handle failures gracefully (log failure, mark task as failed, continue to next)
- The system MUST expose operator controls to pause, resume, and inspect task-loop pause state without disabling the timer units
- The system SHOULD expose machine-readable pause state and effective interactive defaults for desktop launch surfaces
- The system MUST support a three-tier model strategy:
  - A fast model for ingest (default: haiku)
  - A fast model for prioritize (default: haiku)
  - A capable model for execute (default: sonnet), overridable per-task via the `model` field
- Each task in `TASKS.yaml` MAY specify a `needs` field for dependency ordering
- Each task in `TASKS.yaml` MAY specify a `workflow` field for DeepWork workflow dispatch
- The task loop MUST validate `TASKS.yaml` after each write and restore from a pre-stage backup on validation failure

### FR-011: Audit Trail — Security Logging

- The system MUST maintain an immutable append-only audit log at `/var/log/agent-{name}/audit.jsonl`
- The audit log MUST record: git operations, email activity, credential access, browser activity, file modifications outside the agent's home directory
- Each log entry MUST use JSON Lines format with at minimum: `timestamp`, `event_type`, `details`, `outcome`
- The audit log file MUST be owned by root with the append-only attribute, preventing the agent from modifying or deleting entries
- Log rotation MUST be configured with a configurable retention period (default 90 days)
- The system SHOULD forward audit logs to Loki via Grafana Alloy when monitoring is enabled
- The system SHOULD define alert rules for suspicious patterns
- A NixOS assertion MUST prevent disabling audit logging when any agent is enabled

### FR-012: Security Testing — Isolation Verification

- The system MUST include a NixOS VM test that provisions 2+ agents and verifies:
  - Cross-agent home directory isolation (agent-a MUST NOT read agent-b's files)
  - Agenix secret isolation (agent-a MUST NOT read agent-b's secrets)
  - No sudo or wheel group membership
  - No write access to system paths (`/etc`, `/nix/store`, `/usr`)
  - Correct UID/GID assignment from the reserved range
  - Systemd cgroup resource limits are enforced
- The test MUST verify network isolation:
  - Egress firewall rules MUST block undeclared destinations
  - VNC ports MUST be accessible only from authorized sources
  - Each agent's Tailscale identity MUST be distinct
- The test MUST verify credential scoping:
  - Each agent MUST only access its own Bitwarden collection
  - Each agent MUST only use its own SSH key
  - Each agent MUST only authenticate to its own IMAP/SMTP account
- The security test SHOULD run in CI on PRs that touch `modules/os/agents/`

### FR-013: Coding Subagent — Structured Code Contribution

- The system MUST provide a `keystone.os.agents.{name}.codingAgent.enable` option
- When enabled, the system MUST install `agent.coding-agent` and provider scripts in the agent's PATH
- The coding-agent MUST implement an orchestrator/subagent split: the bash orchestrator handles git operations, push, and PR creation; the LLM subagent only creates commits within a sandboxed working tree
- The coding-agent MUST perform pre-flight checks (repo exists, clean working tree, remote accessible, detect remote type)
- Branch naming MUST follow a configurable pattern (default: `{prefix}/{slugified-task}`)
- The agent contract MUST permit: creating commits, reading files, running tests
- The agent contract MUST NOT permit: pushing to remote, creating PRs, switching branches
- The system MUST support automated review cycles (up to N cycles, configurable, default 2)
- Review output MUST use a structured COMMENT/VERDICT format
- PRs created by the orchestrator MUST be draft by default
- The coding-agent MUST support provider abstraction via a provider interface
- The coding-agent MUST support a `--review-only PR_NUMBER` mode
- The coding-agent MUST clean up working state on exit
- Push mechanism MUST support both GitHub (token-based URL) and Forgejo (SSH)

### FR-014: Incident Log — Operational Learning

- Each agent's `ISSUES.yaml` MUST follow a structured schema with fields: `name`, `description`, `discovered_during`, `status`, `severity`, `workaround`, `fix`
- The agent's `AGENTS.md` MUST include a section referencing active incidents from `ISSUES.yaml`
- Agents on the same host SHOULD share a common incident database at `/var/lib/agent-incidents/`
- Critical incidents MUST trigger auto-escalation (email to operator or configurable webhook)
- Known open issues MUST be injected into the agent's LLM context at task-loop startup

### FR-015: MCP Configuration — Tool Access

- The system MUST generate a `.mcp.json` in the agent's home directory from `keystone.os.agents.{name}.mcp` configuration
- The system MUST package `chrome-devtools-mcp` as a Nix derivation in the keystone overlay
- When `chrome.mcp.enable = true`, the generated `.mcp.json` MUST include a `chrome-devtools` entry
- Chrome DevTools MCP MUST use stdio transport — no dedicated systemd service SHALL be needed
- Chrome MUST be started as a separate process outside the MCP server
- The system MUST generate MCP config fragments that human users can reference to connect to agent Chrome instances
- The system MUST support configurable additional MCP servers via `keystone.os.agents.{name}.mcp.servers`
- MCP tool calls SHOULD be logged to the audit trail (FR-011)
- The `.mcp.json` MUST NOT contain secrets inline; credentials MUST be referenced from agenix paths

### FR-016: Cronjob Self-Management

- The agent-space MUST include `.deepwork/jobs/cronjobs/` with workflows for creating, editing, and reviewing cronjobs
- The agent-space MUST include a `.cronjobs/` directory with `{job-name}/run.sh`, `{job-name}/service.unit`, `{job-name}/timer.unit`
- The agent-space MUST include `.cronjobs/shared/` with `lib.sh`, `config.sh`, `setup.sh`
- `run.sh` scripts MUST use `SCRIPT_DIR` for relative paths, MUST NOT hardcode absolute paths
- `run.sh` scripts MUST source `shared/lib.sh` for common functions
- The system MUST provide a `keystone.os.agents.{name}.cronjobs` NixOS option for declaring managed timers
- The `cronjobs` DeepWork job MUST support three workflows: create, edit, review

### FR-017: Agent-Space Development Shell

- The agent-space `flake.nix` MUST provide a dev shell with: LLM CLI, DeepWork CLI, `git`, `gh`, `jq`, `yq-go`
- The agent-space `flake.nix` SHOULD provide additional tools based on agent role: `forgejo-cli`, `nodejs`, `bun`, `glow`
- Systemd services MUST access the dev shell via `nix develop --command` or direnv integration
- The `flake.nix` MUST declare DeepWork as an input for workflow access

## Non-Functional Requirements

### NFR-001: Observability

- The system MUST allow the human operator to list all running agent desktops and their connection URLs
- Desktop sessions MUST be logged (session start/stop, crash restarts)
- A systemd target (`agent-desktops.target`) MUST group all agent desktop services

### NFR-002: Isolation

- Agents MUST NOT access other agents' home directories
- Agents MUST NOT read other agents' agenix secrets
- Agents MUST NOT be able to escalate to root (no sudo, no wheel group)
- Network egress MUST be restricted per-agent via firewall rules

### NFR-003: Declarative Everything

- Adding a new agent MUST require only adding an entry to `keystone.os.agents.{name}`
- All provisioning (user, desktop, secrets, services) MUST happen automatically on `nixos-rebuild switch`
- The system MUST NOT require imperative setup steps beyond initial agenix secret encryption

### NFR-004: Resource Limits

- Each agent's desktop session MUST have configurable CPU and memory limits (via systemd resource control)
- Chrome's disk cache and memory MUST be bounded
- Total agent resource consumption SHOULD be capped at the system level
