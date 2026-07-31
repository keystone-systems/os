//! Shared types for the template command — used by JSON, CLI, and TUI modes.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Input parameters for the `template` command.
///
/// Used by `--json` (deserialized from stdin), interactive CLI prompts,
/// and the TUI create-config form.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateParams {
    pub hostname: String,
    #[serde(default = "default_kind")]
    pub kind: String,
    pub username: String,
    pub password: String,
    #[serde(default)]
    pub disk_device: Option<String>,
    #[serde(default)]
    pub github_username: Option<String>,
    #[serde(default)]
    pub owner_name: Option<String>,
    #[serde(default)]
    pub owner_email: Option<String>,
    #[serde(default = "default_timezone")]
    pub time_zone: String,
    #[serde(default = "default_state_version")]
    pub state_version: String,
    #[serde(default)]
    pub output: Option<String>,
}

fn default_kind() -> String {
    "server".to_string()
}
fn default_timezone() -> String {
    "UTC".to_string()
}
fn default_state_version() -> String {
    "25.05".to_string()
}

/// Output of the `template` command.
#[derive(Debug, Serialize)]
pub struct TemplateResult {
    pub config_version: &'static str,
    pub output_dir: PathBuf,
    pub files: Vec<String>,
}

impl TemplateParams {
    /// Convert to the internal GenerateConfig used by template generation.
    pub fn to_generate_config(&self) -> crate::template::GenerateConfig {
        use crate::template::*;

        let machine_type = match self.kind.as_str() {
            "workstation" => MachineType::Workstation,
            "laptop" => MachineType::Laptop,
            _ => MachineType::Server,
        };

        let storage_type = match machine_type {
            MachineType::Laptop => StorageType::Ext4,
            _ => StorageType::Zfs,
        };

        GenerateConfig {
            hostname: self.hostname.clone(),
            machine_type,
            storage_type,
            disk_device: self.disk_device.clone(),
            github_username: self.github_username.clone(),
            time_zone: self.time_zone.clone(),
            state_version: self.state_version.clone(),
            user: UserConfig {
                username: self.username.clone(),
                password: self.password.clone(),
                authorized_keys: Vec::new(), // populated by caller after GitHub fetch
            },
            remote_unlock: RemoteUnlockConfig {
                enable: machine_type == MachineType::Server,
                authorized_keys: Vec::new(),
            },
            owner_name: self.owner_name.clone(),
            owner_email: self.owner_email.clone(),
        }
    }

    /// Run the interactive CLI form (line-based prompts, not full TUI).
    pub fn from_interactive(github_username: Option<&str>) -> std::io::Result<Self> {
        use std::io::{self, BufRead, Write};

        let stdin = io::stdin();
        let stdout = io::stdout();
        let mut out = stdout.lock();

        let prompt = |out: &mut io::StdoutLock, label: &str, default: &str| -> String {
            if default.is_empty() {
                write!(out, "{}: ", label).unwrap();
            } else {
                write!(out, "{} [{}]: ", label, default).unwrap();
            }
            out.flush().unwrap();
            let mut line = String::new();
            stdin.lock().read_line(&mut line).unwrap();
            let trimmed = line.trim().to_string();
            if trimmed.is_empty() {
                default.to_string()
            } else {
                trimmed
            }
        };

        let hostname = prompt(&mut out, "Hostname", "");
        let kind = prompt(&mut out, "Kind (server/workstation/laptop)", "server");
        let username = prompt(&mut out, "Username", "admin");
        let password = prompt(&mut out, "Password", "changeme");
        let disk_device_raw = prompt(&mut out, "Disk device (optional)", "");
        let time_zone = prompt(&mut out, "Timezone", "UTC");

        let disk_device = if disk_device_raw.is_empty() {
            None
        } else {
            Some(disk_device_raw)
        };

        Ok(Self {
            hostname,
            kind,
            username,
            password,
            disk_device,
            github_username: github_username.map(|s| s.to_string()),
            owner_name: None,
            owner_email: None,
            time_zone,
            state_version: "25.05".to_string(),
            output: None,
        })
    }
}
