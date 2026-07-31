//! `ks grafana` command — manage checked-in Grafana dashboards.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde_json::{json, Value};

use crate::repo;

const HELP: &str = r#"Usage: ks grafana dashboards <apply|export> [uid]

Manage checked-in Keystone Grafana dashboards through the Grafana API.

Subcommands:
  dashboards apply
  dashboards export <uid>
"#;

fn print_help() {
    println!("{HELP}");
}

fn dashboards_dir(repo_root: &Path) -> Result<PathBuf> {
    if let Ok(keystone_root) = repo::resolve_keystone_repo() {
        let path = keystone_root.join("modules/server/services/grafana/dashboards");
        if path.is_dir() {
            return Ok(path);
        }
    }

    let local = repo_root.join("modules/server/services/grafana/dashboards");
    if local.is_dir() {
        return Ok(local);
    }

    anyhow::bail!("could not locate keystone Grafana dashboards directory")
}

async fn eval_nix_json(args: &[String]) -> Result<Value> {
    let output = tokio::process::Command::new("nix")
        .args(args)
        .output()
        .await
        .context("Failed to run nix eval")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("{}", stderr.trim())
    }

    serde_json::from_slice(&output.stdout).context("Failed to parse nix eval output")
}

async fn eval_nix_raw(args: &[String]) -> Result<String> {
    let output = tokio::process::Command::new("nix")
        .args(args)
        .output()
        .await
        .context("Failed to run nix eval")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("{}", stderr.trim())
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

async fn host_has_grafana(repo_root: &Path, host: &str) -> Result<bool> {
    let value = eval_nix_json(&[
        "eval".to_string(),
        format!(
            "{}#nixosConfigurations.{}.config.keystone.server.services.grafana.enable",
            repo_root.display(),
            host,
        ),
        "--json".to_string(),
    ])
    .await?;

    Ok(value.as_bool().unwrap_or(false))
}

async fn resolve_grafana_url(repo_root: &Path) -> Result<String> {
    if let Ok(url) = std::env::var("GRAFANA_URL") {
        if !url.trim().is_empty() {
            return Ok(url);
        }
    }

    if repo::detect_layout(repo_root).is_none() {
        anyhow::bail!("No recognized repo layout found while resolving Grafana URL")
    }

    let mut grafana_host = None;
    if let Some(current_host) = repo::resolve_current_host(repo_root).await? {
        if host_has_grafana(repo_root, &current_host)
            .await
            .unwrap_or(false)
        {
            grafana_host = Some(current_host);
        }
    }

    if grafana_host.is_none() {
        let all_hosts = repo::list_hosts(repo_root).await.unwrap_or_default();
        for host in &all_hosts {
            if host_has_grafana(repo_root, host).await.unwrap_or(false) {
                grafana_host = Some(host.to_string());
                break;
            }
        }
    }

    let Some(grafana_host) = grafana_host else {
        anyhow::bail!(
            "could not find any host with keystone.server.services.grafana.enable = true. Set GRAFANA_URL."
        )
    };

    let subdomain = eval_nix_raw(&[
        "eval".to_string(),
        format!(
            "{}#nixosConfigurations.{}.config.keystone.server.services.grafana.subdomain",
            repo_root.display(),
            grafana_host,
        ),
        "--raw".to_string(),
    ])
    .await
    .ok()
    .unwrap_or_else(|| "grafana".to_string());

    let domain = eval_nix_raw(&[
        "eval".to_string(),
        format!(
            "{}#nixosConfigurations.{}.config.keystone.domain",
            repo_root.display(),
            grafana_host,
        ),
        "--raw".to_string(),
    ])
    .await
    .with_context(|| format!("Failed to resolve Grafana domain for {}", grafana_host))?;
    if domain.is_empty() {
        anyhow::bail!(
            "could not resolve Grafana URL from config for host '{}'. Set GRAFANA_URL.",
            grafana_host
        )
    }

    Ok(format!("https://{subdomain}.{domain}"))
}

fn resolve_grafana_api_key() -> Result<Option<String>> {
    if let Ok(api_key) = std::env::var("GRAFANA_API_KEY") {
        if !api_key.trim().is_empty() {
            return Ok(Some(api_key));
        }
    }

    let runtime_secret = Path::new("/run/agenix/grafana-api-token");
    if runtime_secret.is_file() {
        return Ok(Some(
            fs::read_to_string(runtime_secret)
                .with_context(|| format!("Failed to read {}", runtime_secret.display()))?
                .trim()
                .to_string(),
        ));
    }

    Ok(None)
}

async fn grafana_api_request(
    method: reqwest::Method,
    url: &str,
    api_key: &str,
    body: Option<Value>,
) -> Result<Value> {
    let client = reqwest::Client::new();
    let mut request = client
        .request(method.clone(), url)
        .bearer_auth(api_key)
        .header(reqwest::header::CONTENT_TYPE, "application/json");
    if let Some(body) = body {
        request = request.json(&body);
    }

    let response = request
        .send()
        .await
        .with_context(|| format!("Grafana API request failed: {} {}", method, url))?;
    let status = response.status();
    let text = response.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!(
            "Grafana API request failed: {} {} (HTTP {})\n{}",
            method,
            url,
            status.as_u16(),
            text.trim()
        )
    }

    if text.trim().is_empty() {
        Ok(Value::Null)
    } else {
        serde_json::from_str(&text).context("Failed to parse Grafana API response")
    }
}

fn dashboard_uid(path: &Path) -> Result<Option<String>> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("Failed to read dashboard {}", path.display()))?;
    let value: Value = serde_json::from_str(&contents)
        .with_context(|| format!("Failed to parse dashboard {}", path.display()))?;
    Ok(value.get("uid").and_then(Value::as_str).map(str::to_string))
}

async fn apply_dashboards(repo_root: &Path) -> Result<()> {
    let dashboards_dir = dashboards_dir(repo_root)?;
    let grafana_url = resolve_grafana_url(repo_root).await?;
    let Some(api_key) = resolve_grafana_api_key()? else {
        if repo::keystone_development_enabled(repo_root)
            .await
            .unwrap_or(false)
        {
            anyhow::bail!(
                "Keystone Grafana API token is required for dashboard sync in development mode."
            )
        }
        eprintln!(
            "Warning: Keystone Grafana API token is not configured on this host. Set GRAFANA_API_KEY or define /run/agenix/grafana-api-token."
        );
        return Ok(());
    };

    let mut desired_uids = Vec::new();
    for entry in fs::read_dir(&dashboards_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        let contents = fs::read_to_string(&path)?;
        let mut dashboard: Value = serde_json::from_str(&contents)?;
        let Some(uid) = dashboard
            .get("uid")
            .and_then(Value::as_str)
            .map(str::to_string)
        else {
            eprintln!("Skipping {} (missing uid)", path.display());
            continue;
        };

        desired_uids.push(uid.clone());
        let tags = dashboard
            .get("tags")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let mut tag_values = tags
            .into_iter()
            .filter_map(|value| value.as_str().map(str::to_string))
            .collect::<Vec<_>>();
        if !tag_values.iter().any(|tag| tag == "keystone-managed") {
            tag_values.push("keystone-managed".to_string());
        }
        dashboard["tags"] = Value::Array(tag_values.into_iter().map(Value::String).collect());

        let payload = json!({
            "dashboard": dashboard,
            "overwrite": true,
        });
        grafana_api_request(
            reqwest::Method::POST,
            &format!("{grafana_url}/api/dashboards/db"),
            &api_key,
            Some(payload),
        )
        .await?;
        println!("Applied {uid}");
    }

    let remote_dashboards = grafana_api_request(
        reqwest::Method::GET,
        &format!("{grafana_url}/api/search?type=dash-db&tag=keystone-managed"),
        &api_key,
        None,
    )
    .await?;

    for uid in remote_dashboards
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|dashboard| dashboard.get("uid").and_then(Value::as_str))
    {
        if desired_uids.iter().any(|desired| desired == uid) {
            continue;
        }

        grafana_api_request(
            reqwest::Method::DELETE,
            &format!("{grafana_url}/api/dashboards/uid/{uid}"),
            &api_key,
            None,
        )
        .await?;
        println!("Deleted stale {uid}");
    }

    Ok(())
}

async fn export_dashboard(repo_root: &Path, uid: &str) -> Result<()> {
    let dashboards_dir = dashboards_dir(repo_root)?;
    let grafana_url = resolve_grafana_url(repo_root).await?;
    let Some(api_key) = resolve_grafana_api_key()? else {
        anyhow::bail!(
            "Keystone Grafana API token is not configured on this host. Set GRAFANA_API_KEY or define /run/agenix/grafana-api-token."
        )
    };

    let mut target_file = None;
    for entry in fs::read_dir(&dashboards_dir)? {
        let path = entry?.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        if dashboard_uid(&path)?.as_deref() == Some(uid) {
            target_file = Some(path);
            break;
        }
    }

    let Some(target_file) = target_file else {
        anyhow::bail!(
            "no checked-in dashboard JSON with uid '{}' under {}",
            uid,
            dashboards_dir.display()
        )
    };

    let response = grafana_api_request(
        reqwest::Method::GET,
        &format!("{grafana_url}/api/dashboards/uid/{uid}"),
        &api_key,
        None,
    )
    .await?;

    let mut dashboard = response
        .get("dashboard")
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("Grafana response did not include a dashboard payload"))?;
    if let Some(object) = dashboard.as_object_mut() {
        object.remove("id");
        object.remove("version");
    }

    fs::write(&target_file, serde_json::to_string_pretty(&dashboard)?)
        .with_context(|| format!("Failed to write {}", target_file.display()))?;
    println!("Exported {uid} -> {}", target_file.display());
    Ok(())
}

pub async fn execute(args: &[String], flake_override: Option<&std::path::Path>) -> Result<()> {
    if args.is_empty() || matches!(args.first().map(String::as_str), Some("-h" | "--help")) {
        print_help();
        return Ok(());
    }

    if matches!(args, [dashboards, help] if dashboards == "dashboards" && (help == "--help" || help == "-h"))
    {
        print_help();
        return Ok(());
    }

    let repo_root = repo::find_repo(flake_override)?;
    match args.first().map(String::as_str) {
        Some("dashboards") => match args.get(1).map(String::as_str) {
            Some("apply") => apply_dashboards(&repo_root).await,
            Some("export") => {
                let Some(uid) = args.get(2) else {
                    anyhow::bail!("grafana dashboards export requires a uid")
                };
                export_dashboard(&repo_root, uid).await
            }
            Some("-h" | "--help") | None => {
                print_help();
                Ok(())
            }
            Some(other) => anyhow::bail!("Unknown grafana dashboards action '{}'", other),
        },
        Some(other) => anyhow::bail!("Unknown grafana subcommand '{}'", other),
        None => {
            print_help();
            Ok(())
        }
    }
}
