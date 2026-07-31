//! `ks notify <unit> <result>` — fire a desktop notification on behalf of a
//! completed systemd user unit.
//!
//! This is the hook used by `OnSuccess=` / `OnFailure=` template units like
//! `ks-update-notify@.service`. The caller passes the source unit name plus a
//! result tag (`success` or `failure`); we read the tail of the unit's current
//! boot from the journal and format a human-readable notification via
//! `notify-send`.
//!
//! Keeping the notifier generic means any future background-task unit
//! (`ks-build.service`, `ks-backup.service`, …) can fan out through the same
//! template pair without introducing a new notifier each time.

use anyhow::{Context, Result};
use std::process::Command;

use super::util::notify_send;

/// Result tag passed by the template unit instance (`@success` / `@failure`).
#[derive(Debug, Clone, Copy)]
enum NotifyResult {
    Success,
    Failure,
}

impl NotifyResult {
    fn parse(raw: &str) -> Result<Self> {
        match raw {
            "success" => Ok(Self::Success),
            "failure" => Ok(Self::Failure),
            other => anyhow::bail!(
                "unknown notify result '{}' (expected 'success' or 'failure')",
                other
            ),
        }
    }

    fn urgency(self) -> &'static str {
        match self {
            Self::Success => "normal",
            Self::Failure => "critical",
        }
    }
}

/// Humanize a unit name like `ks-update.service` to `Keystone update`.
///
/// We only recognize units we explicitly own — unknown units fall back to the
/// raw name so notifications are still useful during development.
fn unit_title(unit: &str, result: NotifyResult) -> String {
    let friendly = match unit {
        "ks-update.service" => "Keystone update",
        other => other,
    };
    match result {
        NotifyResult::Success => format!("{friendly} complete"),
        NotifyResult::Failure => format!("{friendly} failed"),
    }
}

/// Read the tail of the unit's journal from the current boot.
///
/// We cap at 5 lines to keep the notification body short. `-o cat` strips
/// timestamps and unit prefixes, giving us just the program output.
fn journal_tail(unit: &str) -> Result<String> {
    let output = Command::new("journalctl")
        .args([
            "--user",
            "-u",
            unit,
            "-b",
            "-n",
            "5",
            "-o",
            "cat",
            "--no-pager",
        ])
        .output()
        .context("failed to invoke journalctl")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        anyhow::bail!("journalctl failed: {}", stderr);
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Build the notification body. Success stays brief; failure includes the last
/// journal lines so the user can triage without opening a terminal.
fn notification_body(unit: &str, result: NotifyResult) -> String {
    match result {
        NotifyResult::Success => format!("{unit} finished successfully."),
        NotifyResult::Failure => match journal_tail(unit) {
            Ok(tail) if !tail.is_empty() => format!("{unit} failed.\n\n{tail}"),
            _ => format!("{unit} failed. See journalctl --user -u {unit} for details."),
        },
    }
}

pub fn execute(unit: &str, result: &str) -> Result<()> {
    let parsed = NotifyResult::parse(result)?;
    let title = unit_title(unit, parsed);
    let body = notification_body(unit, parsed);

    notify_send(&title, &body, parsed.urgency())
}
