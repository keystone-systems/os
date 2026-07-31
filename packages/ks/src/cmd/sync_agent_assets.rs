//! `ks sync-agent-assets` command — refresh generated agent assets.

use anyhow::{anyhow, Context, Result};
use std::env;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn find_executable(name: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    for entry in env::split_paths(&path) {
        let candidate = entry.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

pub fn execute() -> Result<()> {
    let Some(program) = find_executable("keystone-sync-agent-assets") else {
        return Err(anyhow!(
            "keystone-sync-agent-assets is not available in PATH. Refresh the home-manager profile before using this command."
        ));
    };

    let status = Command::new(program)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .context("Failed to run keystone-sync-agent-assets")?;

    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    Ok(())
}
