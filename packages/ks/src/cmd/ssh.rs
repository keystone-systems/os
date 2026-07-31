//! Shared SSH helpers for deploy-oriented commands.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::{Command as StdCommand, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};

#[derive(Debug, Default)]
pub struct SshSessionManager {
    control_dir: Option<PathBuf>,
    opened_targets: BTreeSet<String>,
}

impl SshSessionManager {
    pub fn new() -> Self {
        Self::default()
    }

    fn ensure_control_dir(&mut self) -> Result<&Path> {
        if self.control_dir.is_none() {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis();
            let dir =
                std::env::temp_dir().join(format!("ks-ssh.{}.{}", std::process::id(), unique));
            std::fs::create_dir_all(&dir)
                .with_context(|| format!("Failed to create {}", dir.display()))?;
            self.control_dir = Some(dir);
        }

        Ok(self
            .control_dir
            .as_deref()
            .expect("control_dir initialized"))
    }

    fn control_path(&self, target: &str) -> Option<PathBuf> {
        self.control_dir.as_ref().map(|dir| {
            dir.join(format!(
                "ks-{}",
                target
                    .chars()
                    .map(|ch| match ch {
                        'a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '-' => ch,
                        _ => '_',
                    })
                    .collect::<String>()
            ))
        })
    }

    fn control_path_if_open(&self, target: &str) -> Option<PathBuf> {
        self.opened_targets
            .contains(target)
            .then(|| self.control_path(target))
            .flatten()
    }

    async fn master_is_alive(&self, target: &str) -> bool {
        let Some(control_path) = self.control_path(target) else {
            return false;
        };

        tokio::process::Command::new("ssh")
            .arg("-o")
            .arg(format!("ControlPath={}", control_path.display()))
            .args(["-O", "check"])
            .arg(format!("root@{}", target))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await
            .map(|status| status.success())
            .unwrap_or(false)
    }

    pub async fn ssh_test(&self, target: &str) -> Result<bool> {
        if self.master_is_alive(target).await {
            return Ok(true);
        }

        let status = tokio::process::Command::new("ssh")
            .args(["-o", "ConnectTimeout=3", "-o", "BatchMode=yes"])
            .arg(format!("root@{}", target))
            .arg("true")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await
            .with_context(|| format!("Failed to probe SSH reachability for {}", target))?;

        Ok(status.success())
    }

    pub async fn open_master(&mut self, target: &str) -> Result<()> {
        let _ = self.ensure_control_dir()?;
        let control_path = self
            .control_path(target)
            .expect("control path available after init");

        if self.master_is_alive(target).await {
            self.opened_targets.insert(target.to_string());
            return Ok(());
        }

        eprintln!(
            "Establishing SSH connection to root@{} (hardware key touch may be required)...",
            target
        );

        let status = tokio::process::Command::new("ssh")
            .args([
                "-o",
                "ControlMaster=yes",
                "-o",
                &format!("ControlPath={}", control_path.display()),
                "-o",
                "ControlPersist=600",
                "-o",
                "ConnectTimeout=10",
                "-o",
                "BatchMode=yes",
                "-o",
                "ServerAliveInterval=30",
                "-fN",
            ])
            .arg(format!("root@{}", target))
            .status()
            .await
            .with_context(|| format!("Failed to establish SSH ControlMaster for {}", target))?;

        if !status.success() {
            anyhow::bail!("Failed to establish SSH ControlMaster for root@{}", target);
        }

        self.opened_targets.insert(target.to_string());
        Ok(())
    }

    pub fn configure_ssh_command(&self, command: &mut tokio::process::Command, target: &str) {
        if let Some(control_path) = self.control_path_if_open(target) {
            command
                .arg("-o")
                .arg(format!("ControlPath={}", control_path.display()));
        }
    }

    pub fn configure_nix_copy_command(&self, command: &mut tokio::process::Command, target: &str) {
        if let Some(control_path) = self.control_path_if_open(target) {
            command.env(
                "NIX_SSHOPTS",
                format!("-o ControlPath={}", control_path.display()),
            );
        }
    }
}

impl Drop for SshSessionManager {
    fn drop(&mut self) {
        for target in self.opened_targets.clone() {
            if let Some(control_path) = self.control_path(&target) {
                let _ = StdCommand::new("ssh")
                    .arg("-o")
                    .arg(format!("ControlPath={}", control_path.display()))
                    .args(["-O", "exit"])
                    .arg(format!("root@{}", target))
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        }

        if let Some(control_dir) = self.control_dir.take() {
            let _ = std::fs::remove_dir_all(control_dir);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn control_path_sanitizes_target() {
        let mut manager = SshSessionManager::new();
        manager.control_dir = Some(PathBuf::from("/tmp/ks-test"));
        let path = manager.control_path("host.example:2222").unwrap();
        assert!(path.ends_with("ks-host.example_2222"));
    }
}
