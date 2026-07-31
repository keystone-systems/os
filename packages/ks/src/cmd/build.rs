//! `ks build` command — build home-manager profiles or full NixOS systems.

use anyhow::{Context, Result};
use serde::Serialize;
use std::path::Path;

use crate::repo;

/// Result of a build operation.
#[derive(Debug, Serialize)]
pub struct BuildResult {
    pub hosts: Vec<String>,
    pub lock: bool,
    pub store_paths: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct HmActivationRecord {
    pub host: String,
    pub user: String,
    pub store_path: String,
}

async fn run_nix_build(
    repo_root: &Path,
    targets: &[String],
    override_args: &[String],
) -> Result<Vec<String>> {
    if targets.is_empty() {
        anyhow::bail!("No build targets resolved.");
    }

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("build").arg("--no-link").arg("--print-out-paths");
    for target in targets {
        cmd.arg(target);
    }
    for arg in override_args {
        cmd.arg(arg);
    }
    cmd.current_dir(repo_root);

    let output = cmd.output().await.context("Failed to run nix build")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Build failed:\n{}", stderr);
    }

    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect())
}

pub async fn build_home_manager_records(
    repo_root: &Path,
    hosts: &[String],
    user_filter: Option<&str>,
    all_users: bool,
) -> Result<Vec<HmActivationRecord>> {
    let override_args = repo::local_override_args(repo_root).await?;
    let mut build_targets = Vec::new();
    let mut target_map = Vec::new();

    for host in hosts {
        let users = repo::list_target_hm_users(repo_root, host, user_filter, all_users).await?;
        for user in users {
            build_targets.push(format!(
                "{}#nixosConfigurations.{}.config.home-manager.users.\"{}\".home.activationPackage",
                repo_root.display(),
                host,
                user,
            ));
            target_map.push((host.clone(), user));
        }
    }

    eprintln!("Building home-manager profiles for: {}", hosts.join(", "));
    let paths = run_nix_build(repo_root, &build_targets, &override_args).await?;

    if paths.len() != target_map.len() {
        anyhow::bail!(
            "nix build returned {} path(s) for {} home-manager activation target(s).",
            paths.len(),
            target_map.len()
        );
    }

    Ok(target_map
        .into_iter()
        .zip(paths)
        .map(|((host, user), store_path)| HmActivationRecord {
            host,
            user,
            store_path,
        })
        .collect())
}

async fn build_home_manager(
    repo_root: &Path,
    hosts: &[String],
    user_filter: Option<&str>,
    all_users: bool,
) -> Result<BuildResult> {
    let records = build_home_manager_records(repo_root, hosts, user_filter, all_users).await?;

    Ok(BuildResult {
        hosts: hosts.to_vec(),
        lock: false,
        store_paths: records
            .into_iter()
            .map(|record| record.store_path)
            .collect(),
    })
}

async fn lock_flake_inputs(repo_root: &Path, registry: &serde_json::Value) -> Result<()> {
    let obj = match registry.as_object() {
        Some(obj) => obj,
        None => return Ok(()),
    };

    let inputs: Vec<&str> = obj
        .values()
        .filter_map(|value| value.get("flakeInput").and_then(|input| input.as_str()))
        .filter(|input| !input.is_empty() && *input != "null")
        .collect();

    if inputs.is_empty() {
        return Ok(());
    }

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("flake").arg("update");
    for input in &inputs {
        cmd.arg(input);
    }
    cmd.arg("--flake").arg(repo_root);

    let output = cmd.output().await.context("Failed to lock flake inputs")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Flake lock failed:\n{}", stderr);
    }

    Ok(())
}

async fn commit_flake_lock(repo_root: &Path) -> Result<()> {
    let changed = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["diff", "--quiet", "flake.lock"])
        .status()
        .await
        .context("Failed to inspect flake.lock")?;

    if changed.success() {
        return Ok(());
    }

    let add_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["add", "flake.lock"])
        .status()
        .await
        .context("Failed to stage flake.lock")?;
    if !add_status.success() {
        anyhow::bail!("Failed to stage flake.lock")
    }

    let commit_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["commit", "-m", "chore: relock keystone + agenix-secrets"])
        .status()
        .await
        .context("Failed to commit flake.lock")?;
    if !commit_status.success() {
        anyhow::bail!("Failed to commit flake.lock")
    }

    Ok(())
}

async fn build_locked(repo_root: &Path, hosts: &[String]) -> Result<BuildResult> {
    let registry = repo::get_repos_registry(repo_root).await?;
    let override_args = repo::local_override_args(repo_root).await?;

    lock_flake_inputs(repo_root, &registry).await?;

    let targets: Vec<String> = hosts
        .iter()
        .map(|host| {
            format!(
                "{}#nixosConfigurations.{}.config.system.build.toplevel",
                repo_root.display(),
                host,
            )
        })
        .collect();

    let paths = run_nix_build(repo_root, &targets, &override_args).await?;
    commit_flake_lock(repo_root).await?;

    Ok(BuildResult {
        hosts: hosts.to_vec(),
        lock: true,
        store_paths: paths,
    })
}

pub async fn execute(
    hosts_arg: Option<&str>,
    lock: bool,
    user_filter: Option<&str>,
    all_users: bool,
    flake_override: Option<&std::path::Path>,
) -> Result<BuildResult> {
    let repo_root = repo::find_repo(flake_override)?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;

    if lock {
        build_locked(&repo_root, &hosts).await
    } else {
        build_home_manager(&repo_root, &hosts, user_filter, all_users).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_result_serialization() {
        let result = BuildResult {
            hosts: vec!["workstation".to_string()],
            lock: false,
            store_paths: vec!["/nix/store/abc-system".to_string()],
        };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["hosts"][0], "workstation");
        assert_eq!(json["lock"], false);
        assert_eq!(json["store_paths"][0], "/nix/store/abc-system");
    }
}
