//! `ks notification` — unified notification fetch with source-level read tracking.
//!
//! Replaces shell-script fetchers (fetch-email-source, fetch-github-sources) with
//! a single Rust subcommand that only returns unseen items and supports marking them
//! as read at the source after successful ingest (ISSUE-REQ-1 through ISSUE-REQ-12).

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use tokio::process::Command;

/// State directory for notification manifests.
fn state_dir() -> PathBuf {
    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            home::home_dir()
                .unwrap_or_else(|| PathBuf::from("/tmp"))
                .join(".local/state")
        });
    base.join("ks/notifications")
}

// ── CLI definitions ────────────────────────────────────────────────────

#[derive(Args)]
pub struct NotificationArgs {
    #[command(subcommand)]
    pub command: Option<NotificationCommand>,

    /// Output as JSON instead of human-readable table.
    #[arg(long, global = true)]
    pub json: bool,
}

#[derive(Subcommand)]
pub enum NotificationCommand {
    /// Fetch unseen notifications, output JSON (machine-readable).
    Fetch {
        /// Write a manifest file for later ack.
        #[arg(long)]
        manifest: bool,

        /// Only fetch from specific sources (comma-separated: email,github).
        #[arg(long)]
        sources: Option<String>,
    },

    /// Mark items in a manifest as read at their source.
    Ack {
        /// Path to the manifest file produced by `fetch --manifest`.
        manifest: PathBuf,
    },

    /// Show configured sources and connection status.
    Sources,
}

// ── Data types ─────────────────────────────────────────────────────────

/// A single source entry in the sources.json array consumed by the task loop.
#[derive(Debug, Serialize, Deserialize)]
pub struct SourceEntry {
    pub source: String,
    pub data: serde_json::Value,
}

/// Manifest tracking fetched item IDs per source for later ack.
#[derive(Debug, Serialize, Deserialize)]
pub struct Manifest {
    pub created_at: String,
    pub sources: Vec<ManifestSource>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ManifestSource {
    pub source: String,
    pub ids: Vec<String>,
}

/// Email envelope from himalaya JSON output.
#[derive(Debug, Serialize, Deserialize)]
struct EmailEnvelope {
    id: String,
    #[serde(flatten)]
    rest: serde_json::Map<String, serde_json::Value>,
}

// ── Entrypoint ─────────────────────────────────────────────────────────

pub async fn execute(args: &NotificationArgs) -> Result<()> {
    match &args.command {
        Some(NotificationCommand::Fetch { manifest, sources }) => {
            let filter: Option<Vec<&str>> = sources
                .as_ref()
                .map(|s| s.split(',').map(|s| s.trim()).collect());
            execute_fetch(*manifest, filter.as_deref(), args.json).await
        }
        Some(NotificationCommand::Ack { manifest }) => execute_ack(manifest).await,
        Some(NotificationCommand::Sources) => execute_sources(args.json).await,
        None => execute_list(args.json).await,
    }
}

// ── Fetch ──────────────────────────────────────────────────────────────

use crate::platform;
use crate::time;

/// Collect a source fetch result into entries and manifest.
fn collect_source(
    result: Result<(SourceEntry, Vec<String>)>,
    source_name: &str,
    entries: &mut Vec<SourceEntry>,
    manifest_sources: &mut Vec<ManifestSource>,
) {
    match result {
        Ok((entry, ids)) => {
            if !ids.is_empty() {
                manifest_sources.push(ManifestSource {
                    source: source_name.to_string(),
                    ids,
                });
            }
            let empty_array = serde_json::Value::Array(vec![]);
            let empty_object = serde_json::json!({});
            if entry.data != empty_array && entry.data != empty_object {
                entries.push(entry);
            }
        }
        Err(e) => eprintln!("warning: {source_name} fetch failed: {e}"),
    }
}

/// Fetch notifications from all configured sources and return structured entries.
/// Called by both `execute_fetch` (CLI) and `agent_loop`.
pub async fn fetch_sources(
    source_filter: Option<&[&str]>,
) -> Result<(Vec<SourceEntry>, Vec<ManifestSource>)> {
    let mut entries: Vec<SourceEntry> = Vec::new();
    let mut manifest_sources: Vec<ManifestSource> = Vec::new();

    let should_fetch =
        |name: &str| -> bool { source_filter.map(|f| f.contains(&name)).unwrap_or(true) };

    if should_fetch("email") {
        collect_source(
            fetch_email().await,
            "email",
            &mut entries,
            &mut manifest_sources,
        );
    }

    if should_fetch("github") {
        let username = platform::resolve_github_username();
        collect_source(
            fetch_github(username.as_deref().unwrap_or("")).await,
            "github",
            &mut entries,
            &mut manifest_sources,
        );
    }

    if should_fetch("forgejo") {
        let fj_host = std::env::var("FORGEJO_HOST").ok();
        let fj_token = std::env::var("FORGEJO_TOKEN").ok();
        if let (Some(ref host), Some(ref token)) = (&fj_host, &fj_token) {
            collect_source(
                fetch_forgejo(host, token, "").await,
                "forgejo",
                &mut entries,
                &mut manifest_sources,
            );
        }
    }

    Ok((entries, manifest_sources))
}

async fn execute_fetch(
    write_manifest: bool,
    source_filter: Option<&[&str]>,
    _json_output: bool,
) -> Result<()> {
    let (entries, manifest_sources) = fetch_sources(source_filter).await?;

    // ISSUE-REQ-8: Write manifest for later ack
    if write_manifest && !manifest_sources.is_empty() {
        let manifest = Manifest {
            created_at: chrono_now(),
            sources: manifest_sources,
        };
        let dir = state_dir();
        tokio::fs::create_dir_all(&dir).await?;
        let path = dir.join(format!("manifest-{}.json", timestamp_slug()));
        let content = serde_json::to_string_pretty(&manifest)?;
        tokio::fs::write(&path, &content).await?;
        eprintln!("manifest: {}", path.display());
    }

    // ISSUE-REQ-5: Output JSON in sources.json schema
    let output = serde_json::to_string_pretty(&entries)?;
    println!("{output}");

    Ok(())
}

// ── Email source ───────────────────────────────────────────────────────

/// Fetch unseen email envelopes and enrich with bodies.
/// ISSUE-REQ-2: Uses `not flag seen` query to exclude already-read messages.
async fn fetch_email() -> Result<(SourceEntry, Vec<String>)> {
    // Fetch only unseen envelopes
    let output = Command::new("himalaya")
        .args([
            "envelope", "list", "-o", "json", "-s", "50", "not", "flag", "seen",
        ])
        .output()
        .await
        .context("failed to run himalaya")?;

    if !output.status.success() {
        anyhow::bail!(
            "himalaya envelope list failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let envelopes: Vec<EmailEnvelope> = serde_json::from_slice(&output.stdout).unwrap_or_default();

    let ids: Vec<String> = envelopes.iter().map(|e| e.id.clone()).collect();

    // Enrich each envelope with its body — parallel fetches
    let body_futures: Vec<_> = envelopes
        .iter()
        .map(|env| {
            let id = env.id.clone();
            async move {
                let body = fetch_email_body(&id).await.unwrap_or_default();
                (id, body)
            }
        })
        .collect();
    let bodies: Vec<_> = futures::future::join_all(body_futures).await;

    let mut enriched = Vec::new();
    for (env, (_id, body)) in envelopes.iter().zip(bodies) {
        let mut obj = serde_json::Map::new();
        obj.insert("id".to_string(), serde_json::Value::String(env.id.clone()));
        for (k, v) in &env.rest {
            obj.insert(k.clone(), v.clone());
        }
        obj.insert("body".to_string(), serde_json::Value::String(body));
        enriched.push(serde_json::Value::Object(obj));
    }

    Ok((
        SourceEntry {
            source: "email".to_string(),
            data: serde_json::Value::Array(enriched),
        },
        ids,
    ))
}

async fn fetch_email_body(id: &str) -> Result<String> {
    let output = Command::new("himalaya")
        .args(["message", "read", "-p", id])
        .output()
        .await?;

    if !output.status.success() {
        eprintln!("warning: failed to read email body for id {id}");
        return Ok(String::new());
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

// ── GitHub source ──────────────────────────────────────────────────────

/// Fetch unread GitHub notifications — metadata only, no enrichment.
/// ISSUE-REQ-3: Does NOT pass `all=true` — only unread notifications.
/// Uses exactly 1 API call. Agent fetches full details JIT during task execution.
async fn fetch_github(_username: &str) -> Result<(SourceEntry, Vec<String>)> {
    let output = Command::new("gh")
        .args(["api", "/notifications?participating=true&per_page=100"])
        .output()
        .await
        .context("failed to run gh api")?;

    if !output.status.success() {
        anyhow::bail!(
            "gh api notifications failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let raw: Vec<serde_json::Value> = serde_json::from_slice(&output.stdout).unwrap_or_default();

    // Deduplicate by subject URL, extract metadata, and track only emitted thread IDs
    let mut seen = std::collections::HashSet::new();
    let mut items = Vec::new();
    let mut thread_ids: Vec<String> = Vec::new();

    for notif in &raw {
        let subject_type = notif
            .pointer("/subject/type")
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let subject_url = notif
            .pointer("/subject/url")
            .and_then(|u| u.as_str())
            .unwrap_or("");

        if (subject_type != "Issue" && subject_type != "PullRequest")
            || subject_url.is_empty()
            || !seen.insert(subject_url.to_string())
        {
            continue;
        }

        let Some(number) = platform::parse_number_from_url(subject_url) else {
            continue; // Skip unparseable URLs rather than emitting number=0
        };

        let title = notif
            .pointer("/subject/title")
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let repo = notif
            .pointer("/repository/full_name")
            .and_then(|n| n.as_str())
            .unwrap_or("");
        let reason = notif.get("reason").and_then(|r| r.as_str()).unwrap_or("");
        let updated_at = notif
            .get("updated_at")
            .and_then(|u| u.as_str())
            .unwrap_or("");
        let url = platform::github_html_url(repo, subject_type, number);

        items.push(serde_json::json!({
            "repo": repo,
            "number": number,
            "title": title,
            "url": url,
            "type": subject_type,
            "reason": reason,
            "updated_at": updated_at,
        }));

        // Only track thread IDs for items we actually emit
        if let Some(id) = notif.get("id").and_then(|v| v.as_str()) {
            thread_ids.push(id.to_string());
        }
    }

    let data = serde_json::Value::Array(items);

    Ok((
        SourceEntry {
            source: "github".to_string(),
            data,
        },
        thread_ids,
    ))
}

// ── Forgejo source ────────────────────────────────────────────────────

/// Fetch unread Forgejo notifications — metadata only, no enrichment.
/// ISSUE-REQ-4: Uses unread-only notifications endpoint.
/// Uses exactly 1 API call. Agent fetches full details JIT during task execution.
async fn fetch_forgejo(
    host: &str,
    token: &str,
    _username: &str,
) -> Result<(SourceEntry, Vec<String>)> {
    let url = format!("{host}/api/v1/notifications?limit=100");
    let output = Command::new("curl")
        .args([
            "-sf",
            "-H",
            "Accept: application/json",
            "-H",
            &format!("Authorization: token {token}"),
            &url,
        ])
        .output()
        .await
        .context("failed to fetch forgejo notifications")?;

    if !output.status.success() {
        anyhow::bail!("forgejo notifications API failed");
    }

    let raw: Vec<serde_json::Value> = serde_json::from_slice(&output.stdout).unwrap_or_default();

    // Collect thread IDs for ack manifest
    let thread_ids: Vec<String> = raw
        .iter()
        .filter_map(|n| {
            n.get("id")
                .and_then(|v| v.as_u64())
                .map(|id| id.to_string())
        })
        .collect();

    // Deduplicate by subject URL, extract metadata from notification envelope
    let mut seen = std::collections::HashSet::new();
    let mut items = Vec::new();

    for notif in &raw {
        let subject_type = notif
            .pointer("/subject/type")
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let subject_url = notif
            .pointer("/subject/url")
            .and_then(|u| u.as_str())
            .unwrap_or("");
        let title = notif
            .pointer("/subject/title")
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let repo = notif
            .pointer("/repository/full_name")
            .and_then(|n| n.as_str())
            .unwrap_or("");
        let updated_at = notif
            .get("updated_at")
            .and_then(|u| u.as_str())
            .unwrap_or("");

        if (subject_type != "Issue" && subject_type != "Pull")
            || subject_url.is_empty()
            || !seen.insert(subject_url.to_string())
        {
            continue;
        }

        let number = platform::parse_number_from_url(subject_url).unwrap_or(0);
        let html_url = platform::forgejo_html_url(host, repo, subject_type, number);

        items.push(serde_json::json!({
            "repo": repo,
            "number": number,
            "title": title,
            "url": html_url,
            "type": subject_type,
            "updated_at": updated_at,
        }));
    }

    let data = serde_json::Value::Array(items);

    Ok((
        SourceEntry {
            source: "forgejo".to_string(),
            data,
        },
        thread_ids,
    ))
}

// ── Ack ────────────────────────────────────────────────────────────────

/// ISSUE-REQ-6: Mark items as read at the source.
async fn execute_ack(manifest_path: &PathBuf) -> Result<()> {
    let content = tokio::fs::read_to_string(manifest_path)
        .await
        .context("failed to read manifest")?;
    let manifest: Manifest = serde_json::from_str(&content)?;

    for source in &manifest.sources {
        match source.source.as_str() {
            "email" => ack_email(&source.ids).await?,
            "github" => ack_github(&source.ids).await?,
            "forgejo" => ack_forgejo(&source.ids).await?,
            other => eprintln!("warning: unknown source in manifest: {other}"),
        }
    }

    // Delete manifest after successful ack
    tokio::fs::remove_file(manifest_path).await.ok();
    eprintln!("ack complete, manifest removed");

    Ok(())
}

/// Mark emails as seen via himalaya flag add.
async fn ack_email(ids: &[String]) -> Result<()> {
    for id in ids {
        let status = Command::new("himalaya")
            .args(["flag", "add", id, "Seen"])
            .status()
            .await?;

        if !status.success() {
            eprintln!("warning: failed to mark email {id} as seen");
        }
    }
    Ok(())
}

/// Mark GitHub notification threads as read.
async fn ack_github(thread_ids: &[String]) -> Result<()> {
    for id in thread_ids {
        let url = format!("/notifications/threads/{id}");
        let status = Command::new("gh")
            .args(["api", "-X", "PATCH", &url])
            .status()
            .await?;

        if !status.success() {
            eprintln!("warning: failed to mark GitHub thread {id} as read");
        }
    }
    Ok(())
}

/// Mark Forgejo notification threads as read.
async fn ack_forgejo(thread_ids: &[String]) -> Result<()> {
    let host =
        std::env::var("FORGEJO_HOST").unwrap_or_else(|_| "https://git.ncrmro.com".to_string());
    let token = std::env::var("FORGEJO_TOKEN").unwrap_or_default();
    if token.is_empty() {
        eprintln!("warning: FORGEJO_TOKEN not set, skipping forgejo ack");
        return Ok(());
    }

    let futures: Vec<_> = thread_ids
        .iter()
        .map(|id| {
            let url = format!("{host}/api/v1/notifications/threads/{id}");
            let token = token.clone();
            async move {
                let status = Command::new("curl")
                    .args([
                        "-sf",
                        "-X",
                        "PATCH",
                        "-H",
                        "Accept: application/json",
                        "-H",
                        &format!("Authorization: token {token}"),
                        &url,
                    ])
                    .status()
                    .await;

                if status.map(|s| !s.success()).unwrap_or(true) {
                    eprintln!("warning: failed to mark Forgejo thread {id} as read");
                }
            }
        })
        .collect();

    futures::future::join_all(futures).await;
    Ok(())
}

// ── Human-readable list ────────────────────────────────────────────────

/// ISSUE-REQ-11: Display human-readable summary grouped by source.
async fn execute_list(json: bool) -> Result<()> {
    let entries = fetch_all_sources().await;

    if json {
        println!("{}", serde_json::to_string_pretty(&entries)?);
        return Ok(());
    }

    if entries.is_empty() {
        println!("No unread notifications.");
        return Ok(());
    }

    for entry in &entries {
        println!("\n── {} ──", entry.source.to_uppercase());

        match entry.source.as_str() {
            "email" => {
                if let Some(arr) = entry.data.as_array() {
                    for item in arr {
                        let from = item
                            .get("from")
                            .and_then(|f| f.as_str())
                            .unwrap_or("unknown");
                        let subject = item
                            .get("subject")
                            .and_then(|s| s.as_str())
                            .unwrap_or("(no subject)");
                        let id = item.get("id").and_then(|i| i.as_str()).unwrap_or("");
                        println!("  [{id}] {from}: {subject}");
                    }
                }
            }
            "github" | "forgejo" => {
                if let Some(items) = entry.data.as_array() {
                    for item in items {
                        let repo = item.get("repo").and_then(|r| r.as_str()).unwrap_or("");
                        let number = item.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
                        let title = item.get("title").and_then(|t| t.as_str()).unwrap_or("");
                        let kind = item.get("type").and_then(|t| t.as_str()).unwrap_or("");
                        let reason = item.get("reason").and_then(|r| r.as_str()).unwrap_or("");
                        let suffix = if !reason.is_empty() {
                            format!(" ({reason})")
                        } else {
                            String::new()
                        };
                        let icon = match kind {
                            "Issue" => "I",
                            "PullRequest" | "Pull" => "P",
                            _ => "?",
                        };
                        println!("  [{icon}] {repo}#{number}: {title}{suffix}");
                    }
                }
            }
            _ => {
                println!("  {}", serde_json::to_string_pretty(&entry.data)?);
            }
        }
    }

    Ok(())
}

/// Fetch from all available sources (used by both list and fetch).
async fn fetch_all_sources() -> Vec<SourceEntry> {
    let mut entries = Vec::new();

    if let Ok((entry, _)) = fetch_email().await {
        if entry.data != serde_json::Value::Array(vec![]) {
            entries.push(entry);
        }
    }

    let gh_user = platform::resolve_github_username();
    if let Ok((entry, _)) = fetch_github(gh_user.as_deref().unwrap_or("")).await {
        let empty = serde_json::Value::Array(vec![]);
        if entry.data != empty {
            entries.push(entry);
        }
    }

    // Forgejo — only host + token required
    let fj_host = std::env::var("FORGEJO_HOST").ok();
    let fj_token = std::env::var("FORGEJO_TOKEN").ok();
    if let (Some(ref host), Some(ref token)) = (&fj_host, &fj_token) {
        if let Ok((entry, _)) = fetch_forgejo(host, token, "").await {
            let empty = serde_json::Value::Array(vec![]);
            if entry.data != empty {
                entries.push(entry);
            }
        }
    }

    entries
}

// ── Sources status ─────────────────────────────────────────────────────

/// ISSUE-REQ-12: Show configured sources and connection status.
async fn execute_sources(json: bool) -> Result<()> {
    let mut sources = Vec::new();

    // Check email (himalaya)
    let email_ok = Command::new("himalaya")
        .args(["account", "list", "-o", "json"])
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);

    sources.push(serde_json::json!({
        "source": "email",
        "tool": "himalaya",
        "available": email_ok,
    }));

    // Check GitHub (gh)
    let gh_ok = Command::new("gh")
        .args(["auth", "status"])
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);

    sources.push(serde_json::json!({
        "source": "github",
        "tool": "gh",
        "available": gh_ok,
        "username": std::env::var("GITHUB_USERNAME").unwrap_or_default(),
    }));

    // Check Forgejo
    let fj_host = std::env::var("FORGEJO_HOST").unwrap_or_default();
    let fj_token = std::env::var("FORGEJO_TOKEN").ok();
    let fj_ok = if let Some(ref token) = fj_token {
        if !fj_host.is_empty() {
            Command::new("curl")
                .args([
                    "-sf",
                    "-H",
                    "Accept: application/json",
                    "-H",
                    &format!("Authorization: token {token}"),
                    &format!("{fj_host}/api/v1/user"),
                ])
                .output()
                .await
                .map(|o| o.status.success())
                .unwrap_or(false)
        } else {
            false
        }
    } else {
        false
    };

    sources.push(serde_json::json!({
        "source": "forgejo",
        "tool": "curl",
        "available": fj_ok,
        "host": fj_host,
        "username": std::env::var("FORGEJO_USERNAME").unwrap_or_default(),
    }));

    if json {
        println!("{}", serde_json::to_string_pretty(&sources)?);
    } else {
        println!("Notification sources:\n");
        for s in &sources {
            let name = s.get("source").and_then(|n| n.as_str()).unwrap_or("");
            let tool = s.get("tool").and_then(|t| t.as_str()).unwrap_or("");
            let ok = s
                .get("available")
                .and_then(|a| a.as_bool())
                .unwrap_or(false);
            let status = if ok { "connected" } else { "unavailable" };
            println!("  {name:<10} ({tool}) — {status}");
        }
    }

    Ok(())
}

// ── Helpers ────────────────────────────────────────────────────────────

fn chrono_now() -> String {
    time::iso_now()
}

fn timestamp_slug() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{now}")
}
