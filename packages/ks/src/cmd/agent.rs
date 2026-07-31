//! `ks agent` command — launch an AI coding agent with Keystone context.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde_json::Value;

use super::util;
use crate::repo;

const UPDATE_WORKFLOW_DOCS: &str = r#"## Deployment Workflows (Reference Only — requires sudo, human-only)

> `ks update` and `ks switch` call `sudo` and activate system configurations.
> Use `ks build` to test changes, then ask a human to deploy.

### `ks update`
Pull, lock, build, push, and deploy.

### `ks switch`
Deploy the current local state without pull, lock, or push.
"#;

const LOCAL_OVERRIDE_DOCS: &str = r#"## Local Flake Overrides

`ks` auto-detects local repo clones and passes `--override-input` flags to
every `nix build` and `ks switch` call. No manual flags are needed.
"#;

fn load_conventions(ks_repo: &Path) -> Result<String> {
    let conventions_dir = ks_repo.join("conventions");
    if !conventions_dir.is_dir() {
        return Ok(String::new());
    }

    let mut sections = Vec::new();
    let mut entries = fs::read_dir(&conventions_dir)
        .with_context(|| format!("Failed to read {}", conventions_dir.display()))?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    entries.sort_by_key(|entry| entry.path());

    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("md") {
            continue;
        }
        sections.push(
            fs::read_to_string(&path)
                .with_context(|| format!("Failed to read {}", path.display()))?,
        );
    }

    Ok(sections.join("\n\n---\n\n"))
}

async fn build_host_table(repo_root: &Path) -> Result<Option<String>> {
    let hosts = repo::list_hosts(repo_root).await?;
    if hosts.is_empty() {
        return Ok(None);
    }

    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let mut lines = vec![
        "| Host | Hostname | Role | SSH Target | Fallback IP | Build Remote |".to_string(),
        "|------|----------|------|------------|-------------|--------------|".to_string(),
    ];

    for host in hosts {
        let info = match repo::host_info(repo_root, &host).await {
            Ok(info) => info,
            Err(_) => continue,
        };
        let marker = if info.hostname == current_hostname {
            " ← current"
        } else {
            ""
        };
        lines.push(format!(
            "| {}{} | {} | {} | {} | {} | {} |",
            host,
            marker,
            info.hostname,
            info.role.unwrap_or_default(),
            info.ssh_target.unwrap_or_else(|| "—".to_string()),
            info.fallback_ip.unwrap_or_else(|| "—".to_string()),
            info.build_on_remote
        ));
    }

    Ok(Some(lines.join("\n")))
}

async fn build_user_table(repo_root: &Path, current_host: &str) -> Result<Option<String>> {
    let mut override_args = repo::local_override_args(repo_root).await?;
    let users_expr = "u: builtins.mapAttrs (_: v: { fullName = v.fullName or \"\"; }) u";
    let agents_expr =
        "a: builtins.mapAttrs (_: v: { fullName = v.fullName or \"\"; email = v.email or \"\"; host = v.host or \"\"; }) a";

    let mut users_cmd = tokio::process::Command::new("nix");
    users_cmd
        .arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config.keystone.os.users",
            repo_root.display(),
            current_host,
        ))
        .arg("--json")
        .arg("--apply")
        .arg(users_expr);
    for arg in &override_args {
        users_cmd.arg(arg);
    }

    let mut agents_cmd = tokio::process::Command::new("nix");
    agents_cmd
        .arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config.keystone.os.agents",
            repo_root.display(),
            current_host,
        ))
        .arg("--json")
        .arg("--apply")
        .arg(agents_expr);
    for arg in override_args.drain(..) {
        agents_cmd.arg(arg);
    }

    let users_output = users_cmd.output().await.ok();
    let agents_output = agents_cmd.output().await.ok();

    let users: BTreeMap<String, Value> = users_output
        .filter(|output| output.status.success())
        .and_then(|output| serde_json::from_slice(&output.stdout).ok())
        .unwrap_or_default();
    let agents: BTreeMap<String, Value> = agents_output
        .filter(|output| output.status.success())
        .and_then(|output| serde_json::from_slice(&output.stdout).ok())
        .unwrap_or_default();

    if users.is_empty() && agents.is_empty() {
        return Ok(None);
    }

    let mut lines = vec![
        "| Name | Type | Full Name | Email | Host |".to_string(),
        "|------|------|-----------|-------|------|".to_string(),
    ];
    for (name, value) in users {
        let full_name = value
            .get("fullName")
            .and_then(Value::as_str)
            .unwrap_or_default();
        lines.push(format!("| {} | user | {} | | |", name, full_name));
    }
    for (name, value) in agents {
        lines.push(format!(
            "| {} | agent | {} | {} | {} |",
            name,
            value
                .get("fullName")
                .and_then(Value::as_str)
                .unwrap_or_default(),
            value
                .get("email")
                .and_then(Value::as_str)
                .unwrap_or_default(),
            value
                .get("host")
                .and_then(Value::as_str)
                .unwrap_or_default(),
        ));
    }

    Ok(Some(lines.join("\n")))
}

fn append_section(prompt: &mut String, title: Option<&str>, body: &str) {
    if body.trim().is_empty() {
        return;
    }
    if !prompt.is_empty() {
        prompt.push_str("\n\n---\n\n");
    }
    if let Some(title) = title {
        prompt.push_str(title);
        prompt.push_str("\n\n");
    }
    prompt.push_str(body);
}

async fn build_prompt(repo_root: &Path, current_host: Option<&str>) -> Result<String> {
    let mut prompt = String::new();
    let keystone_repo = repo::resolve_keystone_repo().ok();

    let canonical_prompt = home::home_dir()
        .unwrap_or_default()
        .join(".keystone/AGENTS.md");
    if canonical_prompt.is_file() {
        append_section(
            &mut prompt,
            None,
            &fs::read_to_string(&canonical_prompt)
                .with_context(|| format!("Failed to read {}", canonical_prompt.display()))?,
        );
    } else if let Some(ref ks_repo) = keystone_repo {
        append_section(&mut prompt, None, &load_conventions(ks_repo)?);
    }

    if let Some(ref ks_repo) = keystone_repo {
        let archetype = ks_repo.join("modules/os/agents/archetypes/ks-agent.md");
        if archetype.is_file() {
            append_section(
                &mut prompt,
                None,
                &fs::read_to_string(&archetype)
                    .with_context(|| format!("Failed to read {}", archetype.display()))?,
            );
        }
    }

    append_section(&mut prompt, None, UPDATE_WORKFLOW_DOCS);
    append_section(&mut prompt, None, LOCAL_OVERRIDE_DOCS);

    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let nixos_generation = Command::new("nixos-version")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .unwrap_or_default();

    let mut current_host_body = format!("## Current Host\n\n- **Hostname**: {}", current_hostname);
    if !nixos_generation.is_empty() {
        current_host_body.push_str(&format!("\n- **NixOS generation**: {}", nixos_generation));
    }
    append_section(&mut prompt, None, &current_host_body);

    if let Some(host_table) = build_host_table(repo_root).await? {
        append_section(&mut prompt, Some("## Hosts"), &host_table);
    }

    if let Some(current_host) = current_host {
        if let Some(user_table) = build_user_table(repo_root, current_host).await? {
            append_section(&mut prompt, Some("## Users & Agents"), &user_table);
        }
    }

    if let Some(keystone_repo) = repo::find_local_repo(repo_root, "ncrmro/keystone") {
        let branch = Command::new("git")
            .args(["-C"])
            .arg(&keystone_repo)
            .args(["branch", "--show-current"])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
            .unwrap_or_else(|| "unknown".to_string());
        let dirty = Command::new("git")
            .args(["-C"])
            .arg(&keystone_repo)
            .arg("status")
            .arg("--short")
            .output()
            .ok()
            .map(|output| !output.stdout.is_empty())
            .unwrap_or(false);
        let mut dev_body =
            format!(
            "**Status**: Active — using local keystone from disk{}\n**Path**: {}\n**Branch**: {}",
            if dirty { " (has uncommitted changes)" } else { "" },
            keystone_repo.display(),
            branch
        );
        dev_body.push_str(
            "\n\n- `ks build` rebuilds home-manager profiles only.\n- `ks update --dev` and `ks switch` deploy the current unlocked checkout.",
        );
        append_section(&mut prompt, Some("## Development Mode"), &dev_body);
    }

    Ok(prompt)
}

fn resolve_local_model(explicit_model: Option<&str>, default_model: &str) -> Result<String> {
    if let Some(model) = explicit_model.filter(|model| *model != "default" && !model.is_empty()) {
        return Ok(model.to_string());
    }
    if !default_model.is_empty() {
        return Ok(default_model.to_string());
    }
    anyhow::bail!(
        "no local model was provided and keystone.terminal.ai.ollama.defaultModel is not set"
    )
}

fn prompt_file_path() -> PathBuf {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    std::env::temp_dir().join(format!("ks-prompt-{}-{timestamp}.md", std::process::id()))
}

async fn launch_agent(
    local_model: Option<&str>,
    repo_root: &Path,
    current_host: Option<&str>,
    prompt: &str,
    passthrough_args: &[String],
) -> Result<()> {
    let prompt_file = prompt_file_path();
    fs::write(&prompt_file, prompt)
        .with_context(|| format!("Failed to write {}", prompt_file.display()))?;

    let claude = util::require_executable("claude", "claude is not available.")?;
    let mut command = Command::new(claude);
    command.arg("--append-system-prompt");
    command.arg(format!("@{}", prompt_file.display()));
    command.args(passthrough_args);

    if let Some(local_model) = local_model {
        let Some(current_host) = current_host else {
            anyhow::bail!(
                "could not resolve the current host in hosts.nix, so --local cannot load home-manager Ollama settings"
            )
        };

        let hm_user = repo::resolve_current_hm_user(repo_root, current_host)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "could not resolve a home-manager user for '{}'",
                    current_host
                )
            })?;
        if !repo::resolve_ollama_enabled(repo_root, current_host, Some(&hm_user)).await? {
            anyhow::bail!(
                "local model support is not enabled for home-manager user '{}' on host '{}'",
                hm_user,
                current_host
            )
        }

        util::require_executable("ollama", "--local requires ollama to be installed.")?;
        let ollama_host =
            repo::resolve_ollama_host(repo_root, current_host, Some(&hm_user)).await?;
        let default_model =
            repo::resolve_ollama_default_model(repo_root, current_host, Some(&hm_user)).await?;
        let resolved_model = resolve_local_model(Some(local_model), &default_model)?;

        command.arg("--model");
        command.arg(resolved_model);
        command.env("ANTHROPIC_BASE_URL", ollama_host);
        command.env("ANTHROPIC_AUTH_TOKEN", "ollama");
    }

    let status = util::run_inherited(&mut command, "Failed to launch claude")?;
    let _ = fs::remove_file(&prompt_file);
    util::finish_status(status)
}

pub async fn execute(
    local_model: Option<&str>,
    passthrough_args: &[String],
    flake_override: Option<&std::path::Path>,
) -> Result<()> {
    let repo_root = repo::find_repo(flake_override)?;
    let current_host = repo::resolve_current_host(&repo_root).await?;
    let prompt = build_prompt(&repo_root, current_host.as_deref()).await?;
    launch_agent(
        local_model,
        &repo_root,
        current_host.as_deref(),
        &prompt,
        passthrough_args,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_explicit_or_default_model() {
        assert_eq!(
            resolve_local_model(Some("qwen"), "llama").unwrap(),
            "qwen".to_string()
        );
        assert_eq!(
            resolve_local_model(Some("default"), "llama").unwrap(),
            "llama".to_string()
        );
    }
}
