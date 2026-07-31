//! Shared helpers for Rust-owned CLI commands.

use std::env;
use std::io::{self, IsTerminal};
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};

use anyhow::{anyhow, Context, Result};

pub fn find_executable(name: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    for entry in env::split_paths(&path) {
        let candidate = entry.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

pub fn require_executable(name: &str, guidance: &str) -> Result<PathBuf> {
    find_executable(name).ok_or_else(|| anyhow!(guidance.to_string()))
}

/// Fire a desktop notification via `notify-send` under the Keystone app
/// name. `--` separates the args from the literal title/body so a unit name
/// or rendered title beginning with `-` isn't misread as a flag.
pub fn notify_send(summary: &str, body: &str, urgency: &str) -> Result<()> {
    let status = Command::new("notify-send")
        .args([
            "--app-name=Keystone",
            &format!("--urgency={urgency}"),
            "--",
            summary,
            body,
        ])
        .status()
        .context("failed to invoke notify-send (is libnotify installed?)")?;

    if !status.success() {
        anyhow::bail!(
            "notify-send exited with status {}",
            status.code().unwrap_or(-1)
        );
    }

    Ok(())
}

pub fn run_inherited(command: &mut Command, context: &str) -> Result<ExitStatus> {
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| context.to_string())
}

pub fn finish_status(status: ExitStatus) -> Result<()> {
    if status.success() {
        Ok(())
    } else {
        std::process::exit(status.code().unwrap_or(1));
    }
}

pub fn parse_or_exit<T>(result: std::result::Result<T, clap::Error>) -> Result<T> {
    match result {
        Ok(value) => Ok(value),
        Err(error) => {
            let exit_code = match error.kind() {
                clap::error::ErrorKind::DisplayHelp | clap::error::ErrorKind::DisplayVersion => 0,
                _ => 2,
            };
            error.print()?;
            std::process::exit(exit_code);
        }
    }
}

pub fn interactive_terminal() -> bool {
    io::stdin().is_terminal() && io::stdout().is_terminal()
}

pub fn stderr_terminal() -> bool {
    io::stderr().is_terminal()
}

/// Best-effort short hostname for user-facing messages. Falls back to a
/// generic label so callers can always format a readable string.
pub fn hostname_label() -> String {
    // KEYSTONE_CONFIG_HOST is set by the host-identity shell hook and is
    // the keystone "host key" rather than `uname -n`. Prefer it when
    // present so messages match what the user sees elsewhere.
    if let Ok(value) = env::var("KEYSTONE_CONFIG_HOST") {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    match Command::new("uname").arg("-n").output() {
        Ok(out) if out.status.success() => {
            let raw = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if raw.is_empty() {
                "this host".to_string()
            } else {
                raw
            }
        }
        _ => "this host".to_string(),
    }
}
