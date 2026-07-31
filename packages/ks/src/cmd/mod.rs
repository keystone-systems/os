//! CLI command infrastructure — JSON envelope types and command modules.

use serde::Serialize;

pub mod activate;
pub mod agent;
pub mod agent_loop;
pub mod agents;
pub mod approve;
pub mod build;
pub mod docs;
pub mod doctor;
pub mod grafana;
pub mod hardware_key;
pub mod menu;
pub mod notifications;
pub mod notify;
pub mod photos;
pub mod print;
pub mod projects;
pub mod run_background;
pub mod screenshots;
pub mod ssh;
pub mod switch;
pub mod sync_agent_assets;
pub mod sync_host_keys;
pub mod tasks;
pub mod update;
pub mod update_approve;
pub mod update_menu;
pub mod util;

// Re-export template types and execution from their canonical location.
pub use crate::components::template::run::execute as run_template;
pub use crate::components::template::types::{TemplateParams, TemplateResult};

/// Standard JSON output envelope for all commands.
#[derive(Debug, Serialize)]
pub struct JsonOutput<T: Serialize> {
    pub status: &'static str,
    pub data: T,
}

impl<T: Serialize> JsonOutput<T> {
    pub fn ok(data: T) -> Self {
        Self { status: "ok", data }
    }
}

/// Standard JSON error output.
#[derive(Debug, Serialize)]
pub struct JsonError {
    pub status: &'static str,
    pub error: String,
}

impl JsonError {
    pub fn new(msg: impl Into<String>) -> Self {
        Self {
            status: "error",
            error: msg.into(),
        }
    }
}
