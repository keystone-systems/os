//! Shared platform helpers for GitHub and Forgejo API interactions.
//!
//! Extracted from notifications.rs to enable reuse across commands
//! (notifications, project status, etc.).

use anyhow::{Context, Result};
use tokio::process::Command;

/// Resolve GitHub username from `$GITHUB_USERNAME` env var or `gh api /user`.
pub fn resolve_github_username() -> Option<String> {
    std::env::var("GITHUB_USERNAME").ok().or_else(|| {
        std::process::Command::new("gh")
            .args(["api", "/user", "--jq", ".login"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|s| !s.is_empty())
    })
}

/// Parse trailing number from a REST API URL like
/// `https://api.github.com/repos/owner/repo/issues/123`.
pub fn parse_number_from_url(url: &str) -> Option<u64> {
    url.rsplit('/').next()?.parse().ok()
}

/// Construct GitHub HTML URL from repo + subject type + number.
pub fn github_html_url(repo: &str, subject_type: &str, number: u64) -> String {
    let kind = if subject_type == "PullRequest" {
        "pull"
    } else {
        "issues"
    };
    format!("https://github.com/{repo}/{kind}/{number}")
}

/// Construct Forgejo HTML URL from host + repo + subject type + number.
pub fn forgejo_html_url(host: &str, repo: &str, subject_type: &str, number: u64) -> String {
    let kind = if subject_type == "Pull" {
        "pulls"
    } else {
        "issues"
    };
    format!("{host}/{repo}/{kind}/{number}")
}

/// Execute a GitHub GraphQL query via `gh api graphql`.
pub async fn github_graphql(
    query: &str,
    variables: serde_json::Value,
) -> Result<serde_json::Value> {
    // Build args: gh api graphql -f query=QUERY -f key=value for each variable
    let mut cmd = Command::new("gh");
    cmd.args(["api", "graphql", "-f", &format!("query={query}")]);

    // Add each variable as a -F (typed) field
    if let Some(obj) = variables.as_object() {
        for (key, val) in obj {
            match val {
                serde_json::Value::String(s) => {
                    cmd.args(["-f", &format!("{key}={s}")]);
                }
                serde_json::Value::Number(n) => {
                    cmd.args(["-F", &format!("{key}={n}")]);
                }
                _ => {
                    cmd.args(["-f", &format!("{key}={}", val)]);
                }
            }
        }
    }

    let output = cmd.output().await.context("failed to run gh api graphql")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("gh api graphql failed: {stderr}");
    }

    let parsed: serde_json::Value = serde_json::from_slice(&output.stdout)
        .context("failed to parse GraphQL response as JSON")?;

    // Check for GraphQL-level errors
    if let Some(errors) = parsed.get("errors") {
        if let Some(arr) = errors.as_array() {
            if !arr.is_empty() {
                let msg = arr
                    .iter()
                    .filter_map(|e| e.get("message").and_then(|m| m.as_str()))
                    .collect::<Vec<_>>()
                    .join("; ");
                anyhow::bail!("GraphQL errors: {msg}");
            }
        }
    }

    Ok(parsed)
}

/// Execute a Forgejo REST API call via curl.
// TODO: Token in argv is visible via /proc on multi-user systems. Migrate to
// reqwest or pass auth via stdin/config file when keystone adds an HTTP client.
// Matches existing pattern in notifications.rs for now.
pub async fn forgejo_rest(host: &str, token: &str, endpoint: &str) -> Result<serde_json::Value> {
    let url = format!("{host}/api/v1{endpoint}");
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
        .with_context(|| format!("failed to fetch {url}"))?;

    if !output.status.success() {
        anyhow::bail!("forgejo REST failed: {endpoint}");
    }

    serde_json::from_slice(&output.stdout)
        .with_context(|| format!("failed to parse JSON from {endpoint}"))
}
