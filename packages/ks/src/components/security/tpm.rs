//! TPM2 enrollment — automatic disk unlock via PCR policy.
//!
//! Onboarding Stage 5: guides the user through TPM2 enrollment
//! so the disk unlocks automatically on trusted boots.
//!
//! Flow:
//! 1. Check if TPM2 device exists (/dev/tpmrm0)
//! 2. Check enrollment status from disk-unlock-status.json
//! 3. Show instructions for manual enrollment (requires interactive password)

use serde::Deserialize;

const DISK_UNLOCK_STATUS_FILE: &str = "/var/lib/keystone/disk-unlock-status.json";
const TPM_ENROLLMENT_MARKER: &str = "/var/lib/keystone/tpm-enrollment-complete";
const TPM_DEVICE: &str = "/dev/tpmrm0";

/// TPM2 enrollment state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Not yet checked.
    Unknown,
    /// TPM2 device detected, not yet enrolled.
    Available,
    /// Already enrolled for auto-unlock.
    Enrolled,
    /// No TPM2 device found.
    NotAvailable,
}

#[derive(Deserialize)]
struct DiskUnlockStatus {
    #[serde(default)]
    tpm_enrolled: bool,
}

/// Check TPM2 status by probing device and reading enrollment state.
pub async fn check_status() -> Status {
    if !tokio::fs::try_exists(TPM_DEVICE).await.unwrap_or(false) {
        return Status::NotAvailable;
    }

    // Check the JSON status file written by keystone-tpm-check.service
    if let Ok(content) = tokio::fs::read_to_string(DISK_UNLOCK_STATUS_FILE).await {
        if let Ok(status) = serde_json::from_str::<DiskUnlockStatus>(&content) {
            if status.tpm_enrolled {
                return Status::Enrolled;
            }
        }
    }

    // Fallback: check the marker file
    if tokio::fs::try_exists(TPM_ENROLLMENT_MARKER)
        .await
        .unwrap_or(false)
    {
        return Status::Enrolled;
    }

    Status::Available
}

/// TPM enrollment requires interactive password input via systemd-cryptenroll,
/// so we return instructions rather than attempting auto-enrollment from the TUI.
pub fn enroll_instructions() -> String {
    "To enroll TPM for automatic disk unlock:\n\n\
     Option 1 (recommended): Generate recovery key + enroll TPM\n\
       $ sudo keystone-enroll-recovery\n\n\
     Option 2: Set custom password + enroll TPM\n\
       $ sudo keystone-enroll-password\n\n\
     Option 3: Standalone TPM enrollment (advanced)\n\
       $ sudo keystone-enroll-tpm --auto"
        .into()
}
