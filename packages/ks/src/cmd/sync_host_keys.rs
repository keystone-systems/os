//! `ks sync-host-keys` command — fetch live SSH host keys into `hosts.nix`.

use anyhow::{anyhow, Context, Result};
use serde::Serialize;
use std::path::Path;
use tokio::fs;

use crate::repo;

#[derive(Debug, Serialize)]
pub struct SyncHostKeysResult {
    pub updated: usize,
    pub skipped: usize,
    pub failed: usize,
    pub changed_hosts: Vec<String>,
}

enum HostSyncOutcome {
    Updated { content: String, pubkey: String },
    Unchanged,
    Skipped,
    Failed(String),
}

fn root_target(target: &str) -> String {
    format!("root@{}", target)
}

async fn list_hosts(hosts_nix: &Path) -> Result<Vec<String>> {
    let output = tokio::process::Command::new("nix")
        .args(["eval", "-f"])
        .arg(hosts_nix)
        .args(["--json", "--apply", "builtins.attrNames"])
        .output()
        .await
        .context("Failed to list hosts from hosts.nix")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Failed to list hosts from hosts.nix: {}", stderr.trim())
    }

    serde_json::from_slice(&output.stdout).context("Failed to parse host list")
}

async fn ssh_reachable(target: &str) -> Result<bool> {
    let status = tokio::process::Command::new("ssh")
        .args(["-o", "ConnectTimeout=3", "-o", "BatchMode=yes"])
        .arg(target)
        .arg("true")
        .status()
        .await
        .with_context(|| format!("Failed to probe SSH reachability for {}", target))?;

    Ok(status.success())
}

fn parse_public_key(stdout: &[u8]) -> Option<String> {
    let line = String::from_utf8_lossy(stdout)
        .lines()
        .next()?
        .trim()
        .to_string();
    let mut fields = line.split_whitespace();
    let kind = fields.next()?;
    let key = fields.next()?;
    Some(format!("{} {}", kind, key))
}

async fn fetch_public_key(target: &str) -> Result<Option<String>> {
    let output = tokio::process::Command::new("ssh")
        .args(["-o", "ConnectTimeout=5", "-o", "BatchMode=yes"])
        .arg(target)
        .arg("cat /etc/ssh/ssh_host_ed25519_key.pub")
        .output()
        .await
        .with_context(|| format!("Failed to fetch host key from {}", target))?;

    if !output.status.success() {
        return Ok(None);
    }

    Ok(parse_public_key(&output.stdout))
}

fn find_host_block(content: &str, host: &str) -> Option<(usize, usize)> {
    let start_needles = [
        format!("\n  {} = {{", host),
        format!("\n  \"{}\" = {{", host),
        format!("  {} = {{", host),
        format!("  \"{}\" = {{", host),
    ];

    let start = start_needles
        .iter()
        .find_map(|needle| content.find(needle))?;
    let start = if content[start..].starts_with('\n') {
        start + 1
    } else {
        start
    };
    let end = content[start..]
        .find("\n  };")
        .map(|offset| start + offset + "\n  };".len())?;
    Some((start, end))
}

fn insert_after_line(block: &str, needle: &str, line_to_insert: &str) -> Option<String> {
    let start = block.find(needle)?;
    let line_end = block[start..].find('\n')? + start + 1;
    let mut updated = String::with_capacity(block.len() + line_to_insert.len() + 1);
    updated.push_str(&block[..line_end]);
    updated.push_str(line_to_insert);
    updated.push('\n');
    updated.push_str(&block[line_end..]);
    Some(updated)
}

fn update_host_public_key(
    content: &str,
    host: &str,
    current_key: Option<&str>,
    new_key: &str,
) -> Result<String> {
    let (start, end) = find_host_block(content, host)
        .ok_or_else(|| anyhow!("Could not locate host block for '{}' in hosts.nix", host))?;
    let block = &content[start..end];

    let updated_block = if let Some(current_key) = current_key.filter(|value| !value.is_empty()) {
        let current_line = format!("hostPublicKey = \"{}\";", current_key);
        let new_line = format!("hostPublicKey = \"{}\";", new_key);
        if block.contains(&current_line) {
            block.replacen(&current_line, &new_line, 1)
        } else if block.contains("hostPublicKey = ") {
            let mut replaced = None;
            for line in block.lines() {
                if line.trim_start().starts_with("hostPublicKey = ") {
                    replaced = Some(block.replacen(line, &format!("    {}", new_line), 1));
                    break;
                }
            }
            replaced.unwrap_or_else(|| block.to_string())
        } else {
            insert_after_line(block, "role = ", &format!("    {}", new_line)).unwrap_or_else(|| {
                let block_start_end = block
                    .find('\n')
                    .map(|offset| offset + 1)
                    .unwrap_or(block.len());
                let mut inserted = String::new();
                inserted.push_str(&block[..block_start_end]);
                inserted.push_str(&format!("    {}\n", new_line));
                inserted.push_str(&block[block_start_end..]);
                inserted
            })
        }
    } else {
        let new_line = format!("    hostPublicKey = \"{}\";", new_key);
        insert_after_line(block, "role = ", &new_line).unwrap_or_else(|| {
            let block_start_end = block
                .find('\n')
                .map(|offset| offset + 1)
                .unwrap_or(block.len());
            let mut inserted = String::new();
            inserted.push_str(&block[..block_start_end]);
            inserted.push_str(&new_line);
            inserted.push('\n');
            inserted.push_str(&block[block_start_end..]);
            inserted
        })
    };

    let mut updated = String::with_capacity(content.len() - block.len() + updated_block.len());
    updated.push_str(&content[..start]);
    updated.push_str(&updated_block);
    updated.push_str(&content[end..]);
    Ok(updated)
}

async fn sync_host_entry(
    repo_root: &Path,
    _hosts_nix: &Path,
    hosts_nix_content: &str,
    host: &str,
) -> Result<HostSyncOutcome> {
    let info = match repo::host_info(repo_root, host).await {
        Ok(info) => info,
        Err(error) => return Ok(HostSyncOutcome::Failed(error.to_string())),
    };

    let Some(ssh_target) = repo::resolve_ssh_target(repo_root, host, &info).await? else {
        return Ok(HostSyncOutcome::Skipped);
    };

    let mut resolved = ssh_target.clone();
    if !ssh_reachable(&root_target(&ssh_target)).await? {
        if let Some(fallback_ip) = info
            .fallback_ip
            .as_deref()
            .filter(|value| !value.is_empty())
        {
            resolved = fallback_ip.to_string();
            println!(
                "  Tailscale unavailable for {}, using LAN: {}",
                host, fallback_ip
            );
        } else {
            return Ok(HostSyncOutcome::Failed(format!(
                "unreachable via {}",
                ssh_target
            )));
        }
    }

    let Some(pubkey) = fetch_public_key(&root_target(&resolved)).await? else {
        return Ok(HostSyncOutcome::Failed(format!(
            "could not read host key from {}",
            resolved
        )));
    };

    let current_key = info
        .host_public_key
        .as_deref()
        .filter(|value| !value.is_empty());
    if current_key == Some(pubkey.as_str()) {
        return Ok(HostSyncOutcome::Unchanged);
    }

    let content = update_host_public_key(hosts_nix_content, host, current_key, &pubkey)?;
    Ok(HostSyncOutcome::Updated { content, pubkey })
}

pub async fn execute(flake_override: Option<&std::path::Path>) -> Result<SyncHostKeysResult> {
    let repo_root = repo::find_repo(flake_override)?;
    let hosts_nix = repo_root.join("hosts.nix");
    if !hosts_nix.is_file() {
        anyhow::bail!(
            "sync-host-keys requires a legacy hosts.nix layout.\n\
             The repo at {} uses mkSystemFlake (flake.nix + hosts/) which is not yet supported by this command.",
            repo_root.display()
        );
    }
    let hosts = list_hosts(&hosts_nix).await?;
    let mut hosts_nix_content = fs::read_to_string(&hosts_nix)
        .await
        .with_context(|| format!("Failed to read {}", hosts_nix.display()))?;

    let mut result = SyncHostKeysResult {
        updated: 0,
        skipped: 0,
        failed: 0,
        changed_hosts: Vec::new(),
    };

    for host in hosts {
        match sync_host_entry(&repo_root, &hosts_nix, &hosts_nix_content, &host).await? {
            HostSyncOutcome::Updated { content, pubkey } => {
                hosts_nix_content = content;
                println!("  SET {} -> {}...", host, &pubkey[..pubkey.len().min(40)]);
                result.updated += 1;
                result.changed_hosts.push(host);
            }
            HostSyncOutcome::Unchanged => {
                println!("  OK {} (unchanged)", host);
            }
            HostSyncOutcome::Skipped => {
                println!("SKIP {} (no sshTarget)", host);
                result.skipped += 1;
            }
            HostSyncOutcome::Failed(detail) => {
                println!("FAIL {} ({})", host, detail);
                result.failed += 1;
            }
        }
    }

    if result.updated > 0 {
        fs::write(&hosts_nix, hosts_nix_content)
            .await
            .with_context(|| format!("Failed to write {}", hosts_nix.display()))?;
    }

    println!();
    println!(
        "Summary: {} updated, {} skipped, {} failed",
        result.updated, result.skipped, result.failed
    );
    if result.updated > 0 {
        println!("Review changes with: git diff hosts.nix");
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replaces_existing_host_public_key() {
        let input = r#"{
  alpha = {
    role = "server";
    hostPublicKey = "ssh-ed25519 old";
  };
}
"#;

        let updated =
            update_host_public_key(input, "alpha", Some("ssh-ed25519 old"), "ssh-ed25519 new")
                .unwrap();
        assert!(updated.contains("hostPublicKey = \"ssh-ed25519 new\";"));
        assert!(!updated.contains("hostPublicKey = \"ssh-ed25519 old\";"));
    }

    #[test]
    fn inserts_host_public_key_after_role() {
        let input = r#"{
  beta = {
    role = "server";
  };
}
"#;

        let updated = update_host_public_key(input, "beta", None, "ssh-ed25519 new").unwrap();
        assert!(updated.contains("role = \"server\";\n    hostPublicKey = \"ssh-ed25519 new\";"));
    }
}
