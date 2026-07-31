//! `ks switch` command — deploy current local state without pull/lock/push.

use anyhow::{Context, Result};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use tokio::task::JoinHandle;

use crate::{
    cmd::{build, ssh::SshSessionManager},
    repo,
};

#[derive(Debug, Serialize)]
pub struct SwitchResult {
    pub hosts: Vec<String>,
    pub mode: String,
    pub store_paths: Vec<String>,
}

pub struct DeploySession {
    local_hosts: BTreeSet<String>,
    remote_targets: BTreeMap<String, String>,
    ssh: SshSessionManager,
}

/// Guard that keeps sudo credentials alive by refreshing every 60 seconds.
/// Dropping the guard cancels the background refresh task.
pub struct SudoKeepAlive {
    handle: JoinHandle<()>,
}

impl Drop for SudoKeepAlive {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

/// Normalize a hostname for comparison: trim whitespace, lowercase, and strip
/// any DNS domain suffix (e.g. `host.local` → `host`).
///
/// CRITICAL: hostname::get() may return a FQDN (`ncrmro-workstation.local`) or a
/// trailing-newline on some platforms, while the `hostname` field in hosts.nix
/// is the bare short name. Without normalization, a local deploy is misclassified
/// as remote and errors out demanding an sshTarget.
pub(crate) fn normalize_hostname(raw: &str) -> String {
    let trimmed = raw.trim().to_ascii_lowercase();
    match trimmed.split_once('.') {
        Some((short, _)) => short.to_string(),
        None => trimmed,
    }
}

/// Check whether a host entry refers to the current machine.
pub(crate) fn is_local_host(current: &str, host_hostname: &str, host_key: &str) -> bool {
    let current_n = normalize_hostname(current);
    current_n == normalize_hostname(host_hostname) || current_n == normalize_hostname(host_key)
}

/// Check whether any of the target hosts match the current machine's hostname.
pub async fn has_local_hosts(repo_root: &Path, hosts: &[String]) -> Result<bool> {
    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    for host in hosts {
        let info = repo::host_info(repo_root, host).await?;
        if is_local_host(&current_hostname, &info.hostname, host) {
            return Ok(true);
        }
    }
    Ok(false)
}

/// Cache sudo credentials upfront and spawn a keepalive loop that refreshes
/// the ticket every 60 seconds.  Returns `None` when there are no local hosts
/// (remote-only deploy) or the current user is already root.
pub async fn ensure_sudo(repo_root: &Path, hosts: &[String]) -> Result<Option<SudoKeepAlive>> {
    if !has_local_hosts(repo_root, hosts).await? {
        return Ok(None);
    }
    cache_sudo().await
}

/// Prompt for sudo credentials and spawn a keepalive loop.
/// Returns `None` when the current user is already root.
async fn cache_sudo() -> Result<Option<SudoKeepAlive>> {
    // Already root — nothing to cache.
    if unsafe { libc::geteuid() } == 0 {
        eprintln!("Running as root...");
        return Ok(None);
    }

    eprintln!("Caching sudo credentials (needed for local deploy)...");
    let status = tokio::process::Command::new("sudo")
        .arg("-v")
        .status()
        .await
        .context("Failed to cache sudo credentials")?;
    if !status.success() {
        anyhow::bail!("sudo credential caching failed");
    }

    let handle = tokio::spawn(async {
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            match tokio::process::Command::new("sudo")
                .args(["-n", "true"])
                .status()
                .await
            {
                Ok(status) if status.success() => {}
                Ok(status) => {
                    eprintln!(
                        "Warning: sudo keepalive refresh failed with status {status}; stopping keepalive loop."
                    );
                    break;
                }
                Err(err) => {
                    eprintln!(
                        "Warning: failed to run sudo keepalive refresh: {err}; stopping keepalive loop."
                    );
                    break;
                }
            }
        }
    });

    Ok(Some(SudoKeepAlive { handle }))
}

async fn build_targets(repo_root: &Path, hosts: &[String]) -> Result<Vec<String>> {
    let override_args = repo::local_override_args(repo_root).await?;
    let build_targets: Vec<String> = hosts
        .iter()
        .map(|host| {
            format!(
                "{}#nixosConfigurations.{}.config.system.build.toplevel",
                repo_root.display(),
                host,
            )
        })
        .collect();

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("build").arg("--no-link").arg("--print-out-paths");
    for target in &build_targets {
        cmd.arg(target);
    }
    for arg in &override_args {
        cmd.arg(arg);
    }
    cmd.current_dir(repo_root);

    let output = cmd.output().await.context("Failed to run nix build")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Build failed:\n{}", stderr);
    }

    let paths: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect();

    if paths.len() != hosts.len() {
        anyhow::bail!(
            "nix build returned {} path(s) for {} target host(s).",
            paths.len(),
            hosts.len()
        );
    }

    Ok(paths)
}

fn canonical_path(path: &str) -> Option<String> {
    std::fs::canonicalize(path)
        .ok()
        .map(|resolved| resolved.to_string_lossy().to_string())
}

fn local_system_closure_matches(store_path: &str) -> bool {
    match (
        canonical_path("/run/current-system"),
        canonical_path(store_path),
    ) {
        (Some(current), Some(target)) => current == target,
        _ => false,
    }
}

async fn set_local_system_profile(host: &str, store_path: &str) -> Result<()> {
    let set_status = tokio::process::Command::new("sudo")
        .args([
            "nix-env",
            "--profile",
            "/nix/var/nix/profiles/system",
            "--set",
        ])
        .arg(store_path)
        .status()
        .await
        .context("Failed to set local system profile")?;
    if !set_status.success() {
        anyhow::bail!("Failed to set system profile for {}", host);
    }

    Ok(())
}

async fn switch_local_system(host: &str, mode: &str, store_path: &str) -> Result<()> {
    let touch_status = tokio::process::Command::new("sudo")
        .args(["touch", "/var/run/nixos-rebuild-safe-to-update-bootloader"])
        .status()
        .await
        .context("Failed to mark local bootloader safe-to-update")?;
    if !touch_status.success() {
        anyhow::bail!("Failed to mark bootloader safe-to-update for {}", host);
    }

    let switch_cmd = format!("{}/bin/switch-to-configuration", store_path);
    let switch_status = tokio::process::Command::new("sudo")
        .arg(&switch_cmd)
        .arg(mode)
        .status()
        .await
        .context("Failed to switch local configuration")?;
    if !switch_status.success() {
        anyhow::bail!("Failed to {} for {}", mode, host);
    }

    Ok(())
}

async fn deploy_local(host: &str, mode: &str, store_path: &str) -> Result<()> {
    eprintln!("Deploying {} locally ({} mode)...", host, mode);
    set_local_system_profile(host, store_path).await?;
    switch_local_system(host, mode, store_path).await
}

async fn copy_remote_store_path(
    ssh: &SshSessionManager,
    ssh_target: &str,
    store_path: &str,
) -> Result<()> {
    let mut copy_cmd = tokio::process::Command::new("nix");
    copy_cmd
        .args(["copy", "--to"])
        .arg(format!("ssh://root@{}", ssh_target))
        .arg(store_path);
    ssh.configure_nix_copy_command(&mut copy_cmd, ssh_target);

    let copy_status = copy_cmd
        .status()
        .await
        .context("Failed to copy closure to remote host")?;
    if !copy_status.success() {
        eprintln!(
            "Warning: nix copy to {} failed, attempting switch anyway",
            ssh_target
        );
    }

    Ok(())
}

async fn remote_system_closure_matches(
    ssh: &SshSessionManager,
    ssh_target: &str,
    store_path: &str,
) -> Result<bool> {
    let mut check_cmd = tokio::process::Command::new("ssh");
    ssh.configure_ssh_command(&mut check_cmd, ssh_target);
    let output = check_cmd
        .arg(format!("root@{}", ssh_target))
        .arg(format!(
            "current_system=$(readlink -f /run/current-system 2>/dev/null || echo none); if [ \"$current_system\" = \"{}\" ]; then echo HM; else echo OS; fi",
            store_path
        ))
        .output()
        .await
        .context("Failed to inspect remote system closure")?;

    Ok(output.status.success() && String::from_utf8_lossy(&output.stdout).trim() == "HM")
}

async fn set_remote_system_profile(
    ssh: &SshSessionManager,
    host: &str,
    ssh_target: &str,
    store_path: &str,
) -> Result<()> {
    let mut remote_cmd = tokio::process::Command::new("ssh");
    ssh.configure_ssh_command(&mut remote_cmd, ssh_target);
    let remote_status = remote_cmd
        .arg(format!("root@{}", ssh_target))
        .arg(format!(
            "nix-env --profile /nix/var/nix/profiles/system --set {}",
            store_path
        ))
        .status()
        .await
        .context("Failed to set remote system profile")?;
    if !remote_status.success() {
        anyhow::bail!("Failed to set remote system profile for {}", host);
    }

    Ok(())
}

async fn switch_remote_system(
    ssh: &SshSessionManager,
    host: &str,
    mode: &str,
    store_path: &str,
    ssh_target: &str,
) -> Result<()> {
    let switch_cmd = format!("{}/bin/switch-to-configuration", store_path);
    let mut remote_cmd = tokio::process::Command::new("ssh");
    ssh.configure_ssh_command(&mut remote_cmd, ssh_target);
    let remote_status = remote_cmd
        .arg(format!("root@{}", ssh_target))
        .arg(format!(
            "nix-env --profile /nix/var/nix/profiles/system --set {} && touch /var/run/nixos-rebuild-safe-to-update-bootloader && {} {}",
            store_path, switch_cmd, mode
        ))
        .status()
        .await
        .context("Failed to switch remote configuration")?;
    if !remote_status.success() {
        anyhow::bail!("Failed to {} on remote host {}", mode, host);
    }

    Ok(())
}

async fn build_home_manager_records_for_host(
    repo_root: &Path,
    host: &str,
) -> Result<Vec<build::HmActivationRecord>> {
    build::build_home_manager_records(repo_root, &[host.to_string()], None, false).await
}

async fn deploy_home_manager_only(
    repo_root: &Path,
    session: &DeploySession,
    host: &str,
) -> Result<()> {
    let records = build_home_manager_records_for_host(repo_root, host).await?;
    if records.is_empty() {
        return Ok(());
    }

    if session.local_hosts.contains(host) {
        for record in records {
            eprintln!(
                "Activating home-manager for {} on {} (local)...",
                record.user, record.host
            );
            let status = tokio::process::Command::new("sudo")
                .arg("-u")
                .arg(&record.user)
                .arg(format!("{}/activate", record.store_path))
                .status()
                .await
                .with_context(|| {
                    format!(
                        "Failed to activate home-manager for {} on {}",
                        record.user, record.host
                    )
                })?;
            if !status.success() {
                anyhow::bail!(
                    "Home-manager activation failed for {} on {}",
                    record.user,
                    record.host
                );
            }
        }
        return Ok(());
    }

    let ssh_target = session.remote_targets.get(host).ok_or_else(|| {
        anyhow::anyhow!("{} is not available in the prepared deploy session.", host)
    })?;

    for record in records {
        eprintln!(
            "Activating home-manager for {} on {} (remote: {})...",
            record.user, record.host, ssh_target
        );
        copy_remote_store_path(&session.ssh, ssh_target, &record.store_path).await?;

        let mut remote_cmd = tokio::process::Command::new("ssh");
        session
            .ssh
            .configure_ssh_command(&mut remote_cmd, ssh_target);
        let status = remote_cmd
            .arg(format!("root@{}", ssh_target))
            .arg(format!(
                "sudo -u '{}' '{}/activate'",
                record.user, record.store_path
            ))
            .status()
            .await
            .with_context(|| {
                format!(
                    "Failed to activate remote home-manager for {} on {}",
                    record.user, record.host
                )
            })?;
        if !status.success() {
            anyhow::bail!(
                "Home-manager activation failed for {} on {}",
                record.user,
                record.host
            );
        }
    }

    Ok(())
}

pub async fn prepare_deploy_session(repo_root: &Path, hosts: &[String]) -> Result<DeploySession> {
    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let mut local_hosts = BTreeSet::new();
    let mut remote_targets = BTreeMap::new();
    let mut ssh = SshSessionManager::new();

    for host in hosts {
        let host_info = repo::host_info(repo_root, host).await?;
        if is_local_host(&current_hostname, &host_info.hostname, host) {
            local_hosts.insert(host.clone());
            continue;
        }

        let ssh_target = repo::resolve_ssh_target(repo_root, host, &host_info)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{} has no sshTarget, cannot deploy remotely.\n\
                     current hostname: '{}' (normalized: '{}')\n\
                     host.hostname:    '{}' (normalized: '{}')\n\
                     host key:         '{}' (normalized: '{}')\n\
                     If this host is the current machine, ensure its hosts.nix `hostname` \
                     field matches `hostname(1)` output.",
                    host,
                    current_hostname,
                    normalize_hostname(&current_hostname),
                    host_info.hostname,
                    normalize_hostname(&host_info.hostname),
                    host,
                    normalize_hostname(host),
                )
            })?;

        let mut resolved = ssh_target.clone();
        if let Some(fallback_ip) = host_info
            .fallback_ip
            .as_deref()
            .filter(|value| !value.is_empty())
        {
            if !ssh.ssh_test(&ssh_target).await? {
                resolved = fallback_ip.to_string();
                eprintln!(
                    "Tailscale unavailable for {}, using LAN: {}",
                    host, fallback_ip
                );
            }
        }

        ssh.open_master(&resolved).await?;
        remote_targets.insert(host.clone(), resolved);
    }

    Ok(DeploySession {
        local_hosts,
        remote_targets,
        ssh,
    })
}

pub async fn deploy_paths_with_session(
    repo_root: &Path,
    session: &DeploySession,
    mode: &str,
    hosts: &[String],
    store_paths: &[String],
) -> Result<()> {
    for (host, store_path) in hosts.iter().zip(store_paths.iter()) {
        if session.local_hosts.contains(host) {
            if local_system_closure_matches(store_path) {
                eprintln!(
                    "System closure unchanged. Activating fast home-manager switch locally..."
                );
                deploy_home_manager_only(repo_root, session, host).await?;
                set_local_system_profile(host, store_path).await?;
                eprintln!(
                    "Skipped switch-to-configuration for {} because the system closure is unchanged.",
                    host
                );
            } else {
                deploy_local(host, mode, store_path).await?;
            }
            continue;
        }

        let ssh_target = session.remote_targets.get(host).ok_or_else(|| {
            anyhow::anyhow!("{} is not available in the prepared deploy session.", host)
        })?;

        eprintln!("Deploying {} remotely to {}...", host, ssh_target);
        copy_remote_store_path(&session.ssh, ssh_target, store_path).await?;

        if remote_system_closure_matches(&session.ssh, ssh_target, store_path).await? {
            eprintln!("OS core unchanged. Activating fast home-manager switch remotely...");
            deploy_home_manager_only(repo_root, session, host).await?;
            set_remote_system_profile(&session.ssh, host, ssh_target, store_path).await?;
            eprintln!(
                "Skipped switch-to-configuration for {} because the system closure is unchanged.",
                host
            );
        } else {
            switch_remote_system(&session.ssh, host, mode, store_path, ssh_target).await?;
        }
    }

    Ok(())
}

pub async fn deploy_paths(
    repo_root: &Path,
    mode: &str,
    hosts: &[String],
    store_paths: &[String],
) -> Result<()> {
    let session = prepare_deploy_session(repo_root, hosts).await?;
    deploy_paths_with_session(repo_root, &session, mode, hosts, store_paths).await
}

pub async fn execute(
    hosts_arg: Option<&str>,
    boot: bool,
    flake_override: Option<&std::path::Path>,
) -> Result<SwitchResult> {
    let repo_root = repo::find_repo(flake_override)?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;
    let mode = if boot { "boot" } else { "switch" };
    let _sudo_guard = ensure_sudo(&repo_root, &hosts).await?;
    let session = prepare_deploy_session(&repo_root, &hosts).await?;
    let store_paths = build_targets(&repo_root, &hosts).await?;

    deploy_paths_with_session(&repo_root, &session, mode, &hosts, &store_paths).await?;

    Ok(SwitchResult {
        hosts,
        mode: mode.to_string(),
        store_paths,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_hostname_strips_fqdn_and_case() {
        assert_eq!(
            normalize_hostname("ncrmro-workstation"),
            "ncrmro-workstation"
        );
        assert_eq!(
            normalize_hostname("NCRMRO-Workstation.local\n"),
            "ncrmro-workstation"
        );
        assert_eq!(normalize_hostname(" host.lan.example "), "host");
    }

    #[test]
    fn is_local_host_matches_normalized_hostname() {
        assert!(is_local_host(
            "ncrmro-workstation",
            "ncrmro-workstation",
            "ncrmro-workstation"
        ));
        // FQDN vs short name — should still match.
        assert!(is_local_host(
            "ncrmro-workstation.local",
            "ncrmro-workstation",
            "ncrmro-workstation"
        ));
        // Host key matches even if hostname field differs.
        assert!(is_local_host(
            "ncrmro-workstation",
            "other",
            "ncrmro-workstation"
        ));
    }

    #[test]
    fn is_local_host_rejects_different_hosts() {
        assert!(!is_local_host("laptop", "ocean", "ocean"));
    }

    #[test]
    fn switch_result_serialization() {
        let result = SwitchResult {
            hosts: vec!["laptop".to_string()],
            mode: "switch".to_string(),
            store_paths: vec!["/nix/store/xyz-system".to_string()],
        };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["hosts"][0], "laptop");
        assert_eq!(json["mode"], "switch");
    }

    #[test]
    fn deploy_session_tracks_local_and_remote_hosts() {
        let session = DeploySession {
            local_hosts: ["local".to_string()].into_iter().collect(),
            remote_targets: [("remote".to_string(), "tail.example.ts.net".to_string())]
                .into_iter()
                .collect(),
            ssh: SshSessionManager::new(),
        };

        assert!(session.local_hosts.contains("local"));
        assert_eq!(
            session.remote_targets.get("remote"),
            Some(&"tail.example.ts.net".to_string())
        );
    }

    #[test]
    fn local_system_closure_mismatch_is_false_for_missing_path() {
        assert!(!local_system_closure_matches(
            "/nix/store/does-not-exist-system"
        ));
    }

    #[tokio::test]
    async fn sudo_keepalive_aborts_on_drop() {
        let handle = tokio::spawn(async {
            loop {
                tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
            }
        });
        let abort_handle = handle.abort_handle();
        let guard = SudoKeepAlive { handle };
        assert!(!abort_handle.is_finished());
        drop(guard);
        // Give the runtime a tick to process the abort
        tokio::task::yield_now().await;
        assert!(abort_handle.is_finished());
    }
}
