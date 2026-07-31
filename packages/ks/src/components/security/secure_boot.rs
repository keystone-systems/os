//! Secure Boot enrollment — sbctl key management.
//!
//! Onboarding Stage 5: guides the user through Secure Boot key enrollment.
//!
//! Flow:
//! 1. Check sbctl status (enrolled / setup mode / not in setup mode)
//! 2. If setup mode → generate keys if needed, then enroll
//! 3. Verify enrollment succeeded
//! 4. Prompt reboot

use anyhow::Context;
use tokio::process::Command;

const PKI_BUNDLE: &str = "/var/lib/sbctl";
const DB_PEM: &str = "/var/lib/sbctl/keys/db/db.pem";

/// Secure Boot enrollment state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Not yet checked.
    Unknown,
    /// Secure Boot enabled in user mode — keys enrolled and active.
    Enrolled,
    /// Keys exist at /var/lib/sbctl but Secure Boot not yet active (needs reboot).
    KeysGenerated,
    /// UEFI is in setup mode — ready to enroll.
    SetupMode,
    /// Not in setup mode, no keys — user must enable Setup Mode in BIOS.
    NotInSetupMode,
}

fn status_from_facts(
    secure_boot_enabled: bool,
    setup_mode_enabled: bool,
    sb_keys_exist: bool,
    saw_setup_mode_line: bool,
) -> Status {
    if secure_boot_enabled {
        return Status::Enrolled;
    }

    // Setup Mode must win over key presence so enrollment remains available
    // after keys are generated but before they are enrolled.
    if setup_mode_enabled {
        return Status::SetupMode;
    }

    // Keys exist but Secure Boot is not active yet — most commonly after
    // install-time key generation, awaiting enrollment or reboot.
    if sb_keys_exist {
        return Status::KeysGenerated;
    }

    if saw_setup_mode_line {
        return Status::NotInSetupMode;
    }

    Status::Unknown
}

/// Check Secure Boot status via `sbctl status`.
///
/// Parses lines like:
///   Secure Boot:  ✓ Enabled
///   Setup Mode:   ✓ Enabled
pub async fn check_status() -> Status {
    let output = match Command::new("sbctl").arg("status").output().await {
        Ok(o) => o,
        Err(_) => return Status::Unknown,
    };

    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );

    let secure_boot_enabled = text
        .lines()
        .any(|l| l.contains("Secure Boot:") && l.contains("Enabled"));

    let setup_mode_enabled = text
        .lines()
        .any(|l| l.contains("Setup Mode:") && l.contains("Enabled"));
    let saw_setup_mode_line = text.lines().any(|l| l.contains("Setup Mode:"));

    status_from_facts(
        secure_boot_enabled,
        setup_mode_enabled,
        keys_exist(),
        saw_setup_mode_line,
    )
}

/// Generate Secure Boot keys via `sbctl create-keys`.
///
/// Idempotent: returns Ok immediately if keys already exist.
pub async fn generate_keys() -> anyhow::Result<String> {
    if keys_exist() {
        return Ok("Secure Boot keys already exist.".into());
    }

    let output = Command::new("sbctl")
        .arg("create-keys")
        .output()
        .await
        .context("failed to run sbctl create-keys")?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(format!("{}{}", stdout, stderr).trim().to_string())
    } else {
        anyhow::bail!(
            "sbctl create-keys failed: {}{}",
            stdout.trim(),
            stderr.trim()
        )
    }
}

/// Enroll Secure Boot keys via `sbctl enroll-keys`.
pub async fn enroll_keys() -> anyhow::Result<String> {
    let output = Command::new("sbctl")
        .args(["enroll-keys", "--yes-this-might-brick-my-machine"])
        .output()
        .await
        .context("failed to run sbctl enroll-keys")?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(format!("{}{}", stdout, stderr).trim().to_string())
    } else {
        anyhow::bail!(
            "sbctl enroll-keys failed: {}{}",
            stdout.trim(),
            stderr.trim()
        )
    }
}

/// Check whether SB keys have been generated at the expected PKI bundle path.
fn keys_exist() -> bool {
    std::path::Path::new(DB_PEM).exists()
}

/// Provision Secure Boot: generate keys and enroll if in setup mode.
///
/// Called by `ks provision-secure-boot` and the install flow.
pub async fn provision() -> anyhow::Result<String> {
    let status = check_status().await;
    match status {
        Status::Enrolled => Ok("Secure Boot is already enrolled.".into()),
        Status::SetupMode => {
            if !keys_exist() {
                generate_keys().await?;
            }
            enroll_keys().await?;
            Ok("Secure Boot keys enrolled. Reboot to activate Secure Boot.".into())
        }
        Status::KeysGenerated => Ok("Keys exist. Reboot to activate Secure Boot.".into()),
        Status::NotInSetupMode => {
            if !keys_exist() {
                generate_keys().await?;
                Ok("Keys generated. Enter UEFI Setup Mode and re-run to enroll.".into())
            } else {
                Ok(
                    "Secure Boot keys already exist. Enter UEFI Setup Mode and re-run to enroll."
                        .into(),
                )
            }
        }
        Status::Unknown => {
            if !keys_exist() {
                generate_keys().await?;
                Ok("Keys generated. Re-run Secure Boot provisioning to continue.".into())
            } else {
                Ok("Secure Boot keys already exist.".into())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{status_from_facts, Status};

    #[test]
    fn setup_mode_takes_priority_over_existing_keys() {
        assert_eq!(
            status_from_facts(false, true, true, true),
            Status::SetupMode
        );
    }

    #[test]
    fn keys_generated_used_when_setup_mode_is_disabled() {
        assert_eq!(
            status_from_facts(false, false, true, true),
            Status::KeysGenerated
        );
    }

    #[test]
    fn not_in_setup_mode_requires_parsed_status_line() {
        assert_eq!(
            status_from_facts(false, false, false, true),
            Status::NotInSetupMode
        );
        assert_eq!(
            status_from_facts(false, false, false, false),
            Status::Unknown
        );
    }
}
