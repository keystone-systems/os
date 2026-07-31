# Agent Platform Comparison

How Keystone OS Agents compare to other agent platforms and coding assistants.

## Platform Comparison

| Feature                | Keystone OS Agents                 | OpenClaw                 | Devin                 | Sculptor (Imbue)    | Claude Code          | Codex (OpenAI)              |
| ---------------------- | ---------------------------------- | ------------------------ | --------------------- | ------------------- | -------------------- | --------------------------- |
| Architecture           | NixOS user accounts                | Node.js service + skills | Cloud VM              | Docker containers   | CLI process          | CLI + cloud sandbox         |
| Identity / auth        | SSH keys, git signing, email       | API keys per skill       | Cloud auth            | Container-scoped    | User's credentials   | User's credentials          |
| Desktop / browser      | labwc + wayvnc + Chromium          | Browser automation skill | Full Linux desktop    | No desktop          | No desktop           | No desktop                  |
| Email integration      | Native himalaya client (IMAP/SMTP) | Skill-based              | Slack / Linear        | No                  | No                   | No                          |
| Isolation              | OS-level user separation           | Single process           | Cloud VM              | Docker containers   | User's environment   | Worktree or cloud container |
| Declarative config     | Nix flakes (full schema)           | YAML / JSON skills       | Web UI                | Dockerfile + config | CLAUDE.md + settings | CLI flags                   |
| Parallel agents        | Multiple user accounts             | Single instance          | Multi-agent (2.0)     | Parallel containers | Worktree agents      | Cloud parallel              |
| Persistence            | Home directory + ZFS snapshots     | Session-based            | Cloud sessions        | Container volumes   | Conversation only    | Session-based               |
| Self-hosted            | Yes (NixOS only)                   | Yes (any OS)             | No (SaaS)             | Yes (Docker)        | Yes (local CLI)      | Partial (cloud mode)        |
| Open source            | Yes                                | Yes (MIT)                | No                    | Yes                 | No (CLI binary)      | No                          |
| LLM flexibility        | Any (Claude, GPT, Gemini, local)   | Any (pluggable)          | Proprietary           | Any                 | Claude only          | OpenAI only                 |
| Scheduling / cron      | systemd timers + task loops        | Built-in cron            | Zapier / API triggers | No                  | No                   | No                          |
| Calendar / contacts    | CalDAV + CardDAV via mail server   | No                       | No                    | No                  | No                   | No                          |
| MCP servers            | Declarative per-agent config       | No                       | No                    | No                  | Manual config        | No                          |
| Git server integration | Auto-provisioned Forgejo repos     | No                       | GitHub                | No                  | User's repos         | User's repos                |
| Password manager       | Vaultwarden provisioning           | No                       | No                    | No                  | No                   | No                          |

## Platform Overview

### Keystone OS Agents

Agents are first-class NixOS user accounts with their own UID, home directory, SSH keys,
git signing identity, email, headless desktop, and browser. Each agent is declared in a
Nix flake and gets systemd-managed services for task execution, note syncing, and
scheduling. The `agentctl` CLI provides unified management across all agents.

Key differentiators:

- **OS-level identity** — agents are real users, not sandboxed processes
- **Full communication stack** — each agent has its own email, calendar, and contacts
- **Declarative everything** — agent config is reproducible Nix, not imperative setup
- **ZFS persistence** — agent home directories survive reboots with snapshot rollback
- **Headless desktop** — labwc + wayvnc gives agents a real Wayland session for browser automation

### OpenClaw

An open-source Node.js agent framework with a skill-based architecture. Skills are
modular capabilities (file editing, web browsing, API calls) composed via YAML/JSON
configuration. Runs as a single process on any OS. Good for building custom agent
workflows but lacks OS-level identity and isolation.

### Devin (Cognition)

A cloud-hosted autonomous coding agent with a full Linux VM environment including
desktop, terminal, and browser. Excels at end-to-end feature development but requires
a SaaS subscription with no self-hosting option. The 2.0 release added multi-agent
support for parallel task execution.

### Sculptor (Imbue)

An open-source agent runtime using Docker containers for isolation. Each agent runs in
its own container with configurable tools and environment. Supports parallel execution
via container orchestration. Self-hostable but limited to container-level isolation
without OS-level identity features.

### Claude Code

Anthropic's CLI tool for interactive coding assistance. Runs in the user's terminal
with access to the user's files and environment. Supports worktree-based parallel
agents and MCP server integration. Powerful for assisted development but operates
as a transient process without persistent identity or scheduling.

### Codex (OpenAI)

OpenAI's coding agent available as both a CLI tool and cloud-hosted sandbox. The CLI
mode runs locally with user credentials; cloud mode provides isolated sandboxes for
parallel execution. Limited to OpenAI models with no self-hosting for the cloud
component.

## When to Use What

| Use case                                       | Recommended                  |
| ---------------------------------------------- | ---------------------------- |
| Autonomous agents with full identity and comms | Keystone OS Agents           |
| Quick interactive coding assistance            | Claude Code, Codex           |
| Custom skill-based agent workflows             | OpenClaw                     |
| Cloud-hosted autonomous development            | Devin                        |
| Container-isolated batch processing            | Sculptor                     |
| Self-hosted with maximum control               | Keystone OS Agents, OpenClaw |
