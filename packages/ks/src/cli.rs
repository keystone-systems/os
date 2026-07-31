//! CLI argument parsing (clap definitions).

use clap::{Args, Parser, Subcommand};

use crate::cmd::{
    agent_loop::AgentLoopArgs, notifications::NotificationArgs, photos::PhotosCommand,
    projects::ProjectArgs, screenshots::ScreenshotsCommand, tasks::TaskArgs,
    update_menu::UpdateMenuCommand,
};

/// Walker menu provider backends. Each provider is a subcommand under `ks
/// menu <provider>` — e.g., `ks menu update <action>`. Grouping keeps the
/// top-level namespace clean as more provider scripts from
/// `modules/desktop/home/scripts/` migrate to `ks`.
#[derive(clap::Subcommand)]
pub enum MenuCommand {
    /// Walker provider backend for the Keystone OS update entry.
    ///
    /// Subcommands emit JSON/text that Walker reads from stdout
    /// (`entries`, `preview-summary`, `preview-release-notes`) or perform
    /// activation side effects (`dispatch`). Replaces the legacy
    /// `keystone-update-menu` shell script.
    Update {
        #[command(subcommand)]
        action: UpdateMenuCommand,
    },
}

/// Keystone CLI/TUI — NixOS infrastructure configuration and management.
#[derive(Parser)]
#[command(name = "ks", version, about)]
pub struct Cli {
    /// Render a single screen to stdout as ANSI and exit.
    #[arg(long, value_name = "SCREEN")]
    pub screenshot: Option<String>,

    /// Override the consumer flake path (default: read from
    /// /run/current-system/keystone-system-flake).
    #[arg(long, value_name = "PATH", global = true)]
    pub flake: Option<std::path::PathBuf>,

    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand)]
pub enum Command {
    /// Generate a new Keystone config from a template.
    Template {
        #[arg(long)]
        github_username: Option<String>,

        #[arg(long, short)]
        output: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Build home-manager profiles (or full NixOS systems with --lock).
    Build {
        #[arg(long)]
        lock: bool,

        #[arg(long)]
        user: Option<String>,

        #[arg(long)]
        all_users: bool,

        hosts: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Deploy current local state without pull, lock, or push.
    Switch {
        #[arg(long)]
        boot: bool,

        hosts: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// Pull, lock, build, push, and deploy.
    Update {
        #[arg(long)]
        debug: bool,

        #[arg(long)]
        dev: bool,

        #[arg(long)]
        boot: bool,

        #[arg(long)]
        pull: bool,

        #[arg(long)]
        lock: bool,

        #[arg(long)]
        user: Option<String>,

        #[arg(long)]
        all_users: bool,

        hosts: Option<String>,

        #[arg(long)]
        json: bool,

        /// Route this invocation through the approval broker before running
        /// the update body. Used by the Walker-triggered graphical-session
        /// launch so the update flow gets a polkit prompt instead of
        /// assuming root.
        ///
        /// When `KS_APPROVE_EXECUTING` is set (i.e., we are already the
        /// approved child), this flag is a no-op and the body runs directly.
        #[arg(long)]
        approve: bool,

        /// Local-development override for the `--approve` supervised flow:
        /// use this keystone ref instead of the channel-resolved target.
        /// Accepts any value that `nix flake update keystone
        /// --override-input keystone <value>` accepts — typically
        /// `github:ncrmro/keystone/<branch-or-sha>` or
        /// `path:/absolute/path/to/worktree`.
        ///
        /// In override mode the supervised flow modifies `flake.lock` in
        /// the working tree only (no commit), runs build + activation
        /// against that ref, and restores `flake.lock` on exit
        /// regardless of outcome. Push is always skipped. The system is
        /// activated against the override target while the consumer
        /// flake stays clean — re-run `ks update --approve` without the
        /// flag once you're done testing to bring the system back to the
        /// channel rev.
        ///
        /// Only valid alongside `--approve`. Other update modes ignore it.
        #[arg(long = "keystone")]
        keystone_override: Option<String>,
    },

    /// Activate a pre-built NixOS system closure (privileged).
    ///
    /// This is the narrow root-only step of the Walker → Update flow.
    /// The closure at `<store-path>` must already exist in the local
    /// /nix/store; `ks activate` does not build, lock, or fetch
    /// anything. The supervised flow is:
    ///   ks approve --reason "<text>" -- ks activate <store-path>
    ///
    /// Running this command outside the approval broker (i.e., not as
    /// root) returns an error pointing the caller at the broker form.
    Activate(ActivateArgs),

    /// Request approval for one allowlisted privileged command.
    Approve(ApproveArgs),

    /// Control autonomous agent task loops.
    Agents(AgentsArgs),

    /// Browse Keystone docs.
    Docs { topic_or_path: Option<String> },

    /// Search Keystone Photos assets.
    Photos {
        #[command(subcommand)]
        command: PhotosCommand,
    },

    /// Diagnose and manage hardware-key integrations.
    HardwareKey {
        #[command(subcommand)]
        command: HardwareKeyCommand,
    },

    /// Manage local screenshots.
    Screenshots {
        #[command(subcommand)]
        command: ScreenshotsCommand,
    },

    /// Refresh generated Keystone agent assets.
    SyncAgentAssets,

    /// Fetch SSH host public keys from live hosts into hosts.nix.
    SyncHostKeys,

    /// Manage checked-in Grafana dashboards.
    Grafana {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Convert markdown files to print-ready PDFs.
    Print {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Launch an AI coding agent with Keystone context.
    Agent(AgentArgs),

    /// Run the autonomous agent task loop (replaces task-loop.sh).
    #[command(name = "agent-loop")]
    AgentLoop(AgentLoopArgs),

    /// Generate a system health diagnostic report.
    Doctor(DoctorArgs),

    /// Run the installer headlessly (no TUI). Requires installer ISO context.
    Install(InstallArgs),

    /// Unified notification fetch with source-level read tracking.
    Notification(NotificationArgs),

    /// Manage tasks — list, add, start, complete, prioritize, prune.
    Task(TaskArgs),

    /// Manage projects — list, add, detect, configure provider overrides.
    Project(ProjectArgs),

    /// Fire a desktop notification for a completed systemd user unit.
    ///
    /// Invoked by OnSuccess=/OnFailure= template units (e.g.,
    /// `ks-update-notify@success.service`). Reads the tail of the source
    /// unit's journal to build a body the user can triage without opening a
    /// terminal.
    Notify {
        /// Source unit name (e.g., `ks-update.service`).
        unit: String,

        /// Result tag passed by the template instance: `success` or
        /// `failure`.
        result: String,
    },

    /// Walker menu provider backends (`ks menu <provider> <action>`).
    ///
    /// Groups menu-provider subcommands so future migrations of
    /// `modules/desktop/home/scripts/*-menu.sh` (audio, package, main, agent,
    /// …) slot in as siblings under `menu` rather than flat top-level
    /// commands. Currently the only provider is `update` — see
    /// [`MenuCommand::Update`].
    #[command(name = "menu")]
    Menu {
        #[command(subcommand)]
        command: MenuCommand,
    },

    /// Start a systemd user unit in the background.
    ///
    /// Thin wrapper around `systemctl --user start`, with the unit name
    /// constrained to the `ks-<name>.service` shape (prefix + suffix +
    /// lowercase-ASCII `<name>`) so caller surfaces accepting external
    /// input cannot activate arbitrary user units. Structural check, not
    /// a literal allowlist — see `cmd::run_background` module docs.
    ///
    /// Used by Walker dispatch paths and other trigger surfaces that
    /// should kick off a supervised background task (e.g.,
    /// `ks-update.service`) without opening a terminal.
    #[command(name = "run-background")]
    RunBackground {
        /// Unit to start (must match `ks-<name>.service`).
        unit: String,
    },
}

#[derive(Args)]
pub struct InstallArgs {
    /// Target host to install (must match an embedded installer target).
    /// When omitted, `ks install` lists the available hosts and prompts you
    /// to pick one interactively. In a non-interactive context (piped or
    /// scripted), `--host` is required and the available hosts are printed
    /// to stderr to assist the next invocation.
    #[arg(long)]
    pub host: Option<String>,

    /// Target disk to install to (must match a discovered /dev/disk/by-id path).
    /// When omitted, headless install excludes installer media and may prompt
    /// for a numbered disk choice.
    #[arg(long)]
    pub disk: Option<String>,
}

#[derive(Args)]
pub struct ApproveArgs {
    #[arg(long)]
    pub reason: String,

    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub command: Vec<String>,
}

#[derive(Args)]
pub struct ActivateArgs {
    /// Pre-built NixOS system closure under /nix/store. Must already
    /// be realized — `ks activate` does not build.
    pub store_path: String,

    /// Activation mode forwarded to switch-to-configuration.
    /// Defaults to `switch`.
    #[arg(long, default_value = "switch")]
    pub mode: String,
}

#[derive(Args)]
pub struct AgentsArgs {
    pub action: String,
    pub target: String,
    pub reason: Option<String>,
}

#[derive(Args)]
pub struct AgentArgs {
    #[arg(long, num_args = 0..=1, default_missing_value = "default")]
    pub local: Option<String>,

    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub args: Vec<String>,
}

#[derive(Args)]
pub struct DoctorArgs {
    #[arg(long)]
    pub json: bool,

    #[arg(long, num_args = 0..=1, default_missing_value = "default")]
    pub local: Option<String>,

    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub args: Vec<String>,
}

#[derive(Subcommand)]
pub enum HardwareKeyCommand {
    /// Validate registered hardware-key configuration and local runtime state.
    Doctor {
        /// Optional selector: `user` or `user/key`.
        selector: Option<String>,

        #[arg(long)]
        json: bool,
    },

    /// TODO stub for managing agenix secrets from hardware-key metadata.
    Secrets {
        #[arg(long)]
        json: bool,
    },
}
