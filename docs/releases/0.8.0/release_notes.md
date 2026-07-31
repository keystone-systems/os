# Keystone v0.8.0 — OS Agents

OS agents become fully autonomous Linux users. Each agent gets their own identity — a real Linux user account with a password manager (rbw/Bitwarden), real email (himalaya + Stalwart), internal mail for structured task dispatch, a headless Wayland desktop (labwc + wayvnc), and SSH keys for git signing. This identity-first approach limits agent scope to their own userspace while giving them genuine autonomy: they can read email, commit code, browse the web, and manage secrets without sharing credentials or stepping on each other.

The architectural refactor from a single 2k-line `agents.nix` into focused sub-modules makes the system maintainable as agent capabilities grow.

## Highlights

- **Agents split into focused sub-modules**: base, agentctl, desktop, chrome, dbus, mail-client, tailscale, ssh, notes, home-manager
- **Each agent is a real Linux user** (UID 4000+) with isolated userspace
- **Password manager** (rbw/Bitwarden) per agent with provisioning assertions
- **Real email** (himalaya) + structured task dispatch (agent-mail)
- **Headless desktop** (labwc + wayvnc) with Chromium remote debugging
- **agentctl CLI**: status, tasks, email, claude, vnc, provision, shell
- **MCP server config** with absolute Nix store paths
- **Task loop** integrity validation (TASKS.yaml)
- **fetch-github-sources**, **fetch-forgejo-sources** packages
- **Desktop + Chrome** enabled by default for all agents

## What's New

### Modular Agent Architecture

The monolithic `agents.nix` (2k+ lines) is refactored into focused sub-modules, each responsible for a single concern:

| Module             | Responsibility                                     |
| ------------------ | -------------------------------------------------- |
| `base.nix`         | User creation, groups, sudo, home dirs, activation |
| `agentctl.nix`     | CLI + alias wrappers + MCP config                  |
| `desktop.nix`      | labwc + wayvnc headless Wayland                    |
| `chrome.nix`       | Chromium remote debugging                          |
| `dbus.nix`         | D-Bus socket race fix                              |
| `mail-client.nix`  | himalaya + mail assertions                         |
| `tailscale.nix`    | Per-agent Tailscale                                |
| `ssh.nix`          | ssh-agent + assertions                             |
| `notes.nix`        | notes-sync, task-loop, scheduler                   |
| `home-manager.nix` | Terminal integration                               |

### Agent Identity

Each agent is a real Linux user (UID 4000+) with full isolation:

- **Own home directory** with private permissions
- **Own password manager** (rbw/Bitwarden) for credential storage
- **Own email account** (himalaya client + Stalwart server) for communication
- **Own SSH keys** for git signing and authentication
- **Own headless desktop** for browser automation and GUI tools

### Agent Mail

Agents communicate via structured email using the `agent-mail` package. Templates (task, status, spike, research) provide consistent formatting for machine-readable dispatch. Internal mail flows through the Stalwart server alongside human email.

### Headless Desktop

Each agent gets a labwc Wayland compositor with wayvnc for remote access. Chromium runs in remote debugging mode, enabling browser automation via CDP (Chrome DevTools Protocol). VNC ports and Chrome debug ports are auto-assigned to prevent conflicts.

### agentctl CLI

The unified `agentctl` command manages all agent operations:

```bash
agentctl drago status          # Service status
agentctl drago tasks           # View task queue
agentctl drago email           # Check inbox
agentctl drago claude          # Start Claude session
agentctl drago vnc             # Connect to desktop
agentctl drago provision       # Full identity provisioning
```

### Task Loop

Agents run a task loop that validates `TASKS.yaml` integrity, picks up pending tasks, and executes them. The scheduler creates new tasks on a configurable cadence.

## Breaking Changes

- **Agent module structure changed** — `modules/os/agents.nix` is now `modules/os/agents/` directory with sub-modules. Import path (`keystone.nixosModules.operating-system`) is unchanged.

## Full Changelog

[v0.7.0...v0.8.0](https://github.com/ncrmro/keystone/compare/v0.7.0...v0.8.0)
