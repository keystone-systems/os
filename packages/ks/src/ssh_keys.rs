//! SSH key auto-detection.
//!
//! Scans `~/.ssh/` for existing public keys (ed25519, ecdsa, rsa) and returns
//! them as authorized_keys strings. Also detects FIDO2/hardware security keys
//! by checking for `sk-` prefixed key types.

use std::path::PathBuf;

/// A detected SSH public key on the local filesystem.
#[derive(Debug, Clone)]
pub struct DetectedKey {
    /// Full public key string (e.g. "ssh-ed25519 AAAA... user@host").
    pub public_key: String,
    /// Path to the public key file.
    pub path: PathBuf,
    /// Key type (e.g. "ssh-ed25519", "sk-ssh-ed25519@openssh.com").
    pub key_type: String,
    /// Whether this is a FIDO2/hardware security key.
    pub is_hardware_key: bool,
}

/// Scan ~/.ssh/ for existing SSH public keys.
pub fn detect_ssh_keys() -> Vec<DetectedKey> {
    let ssh_dir = match home::home_dir() {
        Some(home) => home.join(".ssh"),
        None => return Vec::new(),
    };

    if !ssh_dir.is_dir() {
        return Vec::new();
    }

    let mut keys = Vec::new();

    let entries = match std::fs::read_dir(&ssh_dir) {
        Ok(entries) => entries,
        Err(_) => return Vec::new(),
    };

    for entry in entries.flatten() {
        let path = entry.path();

        // Only look at .pub files
        if path.extension().map(|e| e == "pub").unwrap_or(false) {
            if let Ok(content) = std::fs::read_to_string(&path) {
                let content = content.trim().to_string();
                if content.is_empty() {
                    continue;
                }

                // Parse key type from the first field
                let key_type = content.split_whitespace().next().unwrap_or("").to_string();

                // Only accept known SSH key types
                if !is_ssh_key_type(&key_type) {
                    continue;
                }

                let is_hardware_key = key_type.starts_with("sk-");

                keys.push(DetectedKey {
                    public_key: content,
                    path,
                    key_type,
                    is_hardware_key,
                });
            }
        }
    }

    // Sort: ed25519 first, then ecdsa, then rsa; hardware keys before software keys
    keys.sort_by(|a, b| {
        let a_prio = key_priority(&a.key_type);
        let b_prio = key_priority(&b.key_type);
        a_prio.cmp(&b_prio)
    });

    keys
}

/// Return just the public key strings, suitable for authorized_keys.
pub fn detect_local_ssh_keys() -> Vec<String> {
    detect_ssh_keys()
        .into_iter()
        .map(|k| k.public_key)
        .collect()
}

fn is_ssh_key_type(key_type: &str) -> bool {
    matches!(
        key_type,
        "ssh-ed25519"
            | "ssh-rsa"
            | "ecdsa-sha2-nistp256"
            | "ecdsa-sha2-nistp384"
            | "ecdsa-sha2-nistp521"
            | "sk-ssh-ed25519@openssh.com"
            | "sk-ecdsa-sha2-nistp256@openssh.com"
    )
}

fn key_priority(key_type: &str) -> u8 {
    match key_type {
        "sk-ssh-ed25519@openssh.com" => 0,
        "ssh-ed25519" => 1,
        "sk-ecdsa-sha2-nistp256@openssh.com" => 2,
        t if t.starts_with("ecdsa-") => 3,
        "ssh-rsa" => 4,
        _ => 5,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_ssh_key_type() {
        assert!(is_ssh_key_type("ssh-ed25519"));
        assert!(is_ssh_key_type("ssh-rsa"));
        assert!(is_ssh_key_type("ecdsa-sha2-nistp256"));
        assert!(is_ssh_key_type("sk-ssh-ed25519@openssh.com"));
        assert!(!is_ssh_key_type("not-a-key"));
        assert!(!is_ssh_key_type(""));
    }

    #[test]
    fn test_key_priority_order() {
        assert!(key_priority("sk-ssh-ed25519@openssh.com") < key_priority("ssh-ed25519"));
        assert!(key_priority("ssh-ed25519") < key_priority("ssh-rsa"));
    }

    #[test]
    fn test_detect_runs_without_panic() {
        // Just ensure it doesn't crash — actual keys depend on the system
        let _ = detect_ssh_keys();
        let _ = detect_local_ssh_keys();
    }
}
