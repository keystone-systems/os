//! YubiKey / FIDO2 enrollment — hardware-backed SSH keys.
//!
//! Onboarding Stage 6: guides the user through FIDO2 key setup.
//!
//! Flow:
//! 1. Detect connected FIDO2 devices
//! 2. Generate ed25519-sk key: `ssh-keygen -t ed25519-sk`
//! 3. Optionally import existing public keys from GitHub
//! 4. Add public key to the NixOS config (authorizedKeys)
//! 5. Test SSH auth

/// FIDO2 / YubiKey detection state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Not yet checked.
    Unknown,
    /// FIDO2 device detected, not yet enrolled.
    Detected { device_name: String },
    /// No FIDO2 device found.
    NotDetected,
}

/// Detect connected FIDO2 / YubiKey devices.
///
/// TODO: check /sys/class/hidraw/ or use fido2-token -L
pub async fn detect_devices() -> Vec<String> {
    Vec::new()
}

/// Generate an ed25519-sk SSH key using a connected FIDO2 device.
///
/// TODO: run `ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk`
pub async fn generate_sk_key() -> anyhow::Result<String> {
    anyhow::bail!("FIDO2 key generation not yet implemented")
}
