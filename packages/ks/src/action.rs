//! Global action enum — the single source of truth for app-level actions.
//!
//! Per the ratatui Component Architecture, each component handles its own
//! internal actions (list navigation, form input, etc.) inside
//! `handle_events()`. Only actions that cross component boundaries live here.

use crate::nix::HostInfo;

/// The active screen/component.
#[derive(Debug, Clone)]
pub enum Screen {
    Welcome,
    Template { repo_name: String },
    Hosts,
    HostDetail(Box<HostInfo>),
    Build { host_name: String },
    Iso { host_name: Option<String> },
    Deploy { host_name: String },
    Install,
    FirstBoot,
    Installer,
    Secrets,
    Security,
    Services,
    Update,
    Doctor,
}

/// App-level actions that cross component boundaries.
///
/// Components return these from `update()` to request navigation or
/// app-level side effects. Internal component actions (scroll, select,
/// toggle) are handled inside `handle_events()` and never appear here.
#[derive(Debug, Clone)]
pub enum Action {
    /// Tick event for polling-based components.
    Tick,
    /// Render a frame.
    Render,
    /// Navigate to a different screen.
    NavigateTo(Screen),
    /// Go back to the previous screen.
    GoBack,
    /// Quit the application.
    Quit,
    /// Reboot the system (installer/first-boot).
    Reboot,
    /// Refresh the hosts dashboard (re-parse flake, re-poll).
    RefreshDashboard,
}
