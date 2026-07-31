//! `ks run-background <unit>` — start a systemd user unit, intended for
//! Walker dispatch paths and keybinds that kick off a supervised background
//! task (e.g., `ks-update.service`) without opening a terminal.
//!
//! Thin wrapper around `systemctl --user start`. The unit name must match a
//! `ks-<name>.service` shape constraint (prefix `ks-`, suffix `.service`,
//! `<name>` restricted to lowercase ASCII + digits + hyphens) so caller
//! surfaces that accept external input (Walker dispatch values, future
//! keybinds, potentially cron) cannot activate arbitrary user units. This
//! is a structural check — not a literal allowlist of approved unit names.
//! When a literal allowlist becomes worthwhile (i.e., when multiple
//! background-task units exist and the set can be enumerated), tighten
//! here.
//!
//! The consumer stays simple: one binary invocation instead of
//! reimplementing the systemctl spawn plus error-surface translation per
//! caller.

use anyhow::{anyhow, Context, Result};
use std::process::Command;

/// Validate that `unit` matches the `ks-<name>.service` shape this verb
/// accepts. The check is structural (prefix / suffix / allowed characters
/// in `<name>`), not a literal allowlist of known unit names — see the
/// module docstring for rationale. Rejects shell metacharacters, path
/// traversal, uppercase (which would require systemd escaping), empty
/// stems, non-`.service` suffixes, and any prefix other than `ks-`.
///
/// Allowed characters in `<name>`: lowercase ASCII, digits, hyphens.
/// These are the conventions keystone uses for its own service names and
/// are all safe under shell and systemd unit-name rules.
pub(crate) fn validate_unit_name(unit: &str) -> Result<()> {
    if !unit.ends_with(".service") {
        return Err(anyhow!("unit {unit:?} is not a .service unit"));
    }
    if !unit.starts_with("ks-") {
        return Err(anyhow!(
            "unit {unit:?} does not match the ks-<name>.service shape"
        ));
    }
    let stem = unit.trim_end_matches(".service").trim_start_matches("ks-");
    if stem.is_empty() {
        return Err(anyhow!("unit {unit:?} has an empty task name"));
    }
    if !stem
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        return Err(anyhow!(
            "unit {unit:?} contains characters outside the ks-<name>.service shape (lowercase ascii, digits, hyphens)"
        ));
    }
    Ok(())
}

pub fn execute(unit: &str) -> Result<()> {
    validate_unit_name(unit)?;

    let status = Command::new("systemctl")
        .args(["--user", "start", unit])
        .status()
        .with_context(|| format!("failed to invoke systemctl --user start {unit}"))?;

    if !status.success() {
        anyhow::bail!(
            "systemctl --user start {unit} exited with status {:?}",
            status.code()
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_canonical_keystone_unit_names() {
        validate_unit_name("ks-update.service").unwrap();
        validate_unit_name("ks-build.service").unwrap();
        validate_unit_name("ks-backup.service").unwrap();
        validate_unit_name("ks-photos-import.service").unwrap();
    }

    #[test]
    fn rejects_non_ks_prefixed_units() {
        let err = validate_unit_name("user-session.service").unwrap_err();
        assert!(
            err.to_string().contains("ks-<name>.service shape"),
            "got: {err}"
        );
    }

    #[test]
    fn rejects_non_service_suffixes() {
        assert!(validate_unit_name("ks-update.timer").is_err());
        assert!(validate_unit_name("ks-update.socket").is_err());
        assert!(validate_unit_name("ks-update").is_err());
    }

    #[test]
    fn rejects_shell_metacharacters_and_uppercase() {
        // Each of these attempts to smuggle something past the systemd
        // spawn; the allowlist must reject all of them.
        assert!(validate_unit_name("ks-update.service; rm -rf /").is_err());
        assert!(validate_unit_name("ks-up date.service").is_err());
        assert!(validate_unit_name("ks-UPPER.service").is_err());
        assert!(validate_unit_name("ks-../other.service").is_err());
        assert!(validate_unit_name("ks-up$date.service").is_err());
    }

    #[test]
    fn rejects_empty_stem() {
        assert!(validate_unit_name("ks-.service").is_err());
    }
}
