//! `ks project` — project management with provider overrides and detection.
//!
//! Projects map repos to named entities with priority and per-project
//! provider/model configuration. Detection resolves notifications to
//! projects deterministically (repo match) or heuristically (subject match).

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use tokio::process::Command;

// ── CLI definition ────────────────────────────────────────────────────

#[derive(Args)]
pub struct ProjectArgs {
    #[command(subcommand)]
    pub command: Option<ProjectCommand>,

    /// Output as JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand)]
pub enum ProjectCommand {
    /// Show full details for a project.
    Show {
        /// Project slug.
        slug: String,
    },

    /// Add a new project.
    Add {
        /// Project slug (kebab-case).
        slug: String,

        /// Display name.
        #[arg(long)]
        name: Option<String>,

        /// Associated repo (repeatable, "owner/repo" format).
        #[arg(long, action = clap::ArgAction::Append)]
        repo: Vec<String>,

        /// Priority (lower = higher priority).
        #[arg(long)]
        priority: Option<u32>,
    },

    /// Remove a project.
    Remove {
        /// Project slug.
        slug: String,
    },

    /// Detect which project a notification belongs to.
    Detect {
        /// Match by repo ("owner/repo" or full URL).
        #[arg(long)]
        repo: Option<String>,

        /// Match by subject text (heuristic).
        #[arg(long)]
        subject: Option<String>,
    },

    /// Show live project status: milestones, issues, PRs, branches, tasks.
    Status {
        /// Project slug. Auto-detected from cwd if omitted.
        slug: Option<String>,

        /// Show status for all projects.
        #[arg(long)]
        all: bool,
    },
}

// ── Data model ────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectFile {
    pub projects: Vec<Project>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Project {
    pub slug: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub priority: Option<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub repos: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sources: Vec<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<ProjectProvider>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectProvider {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
}

/// Detection result with confidence level.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DetectionResult {
    pub slug: Option<String>,
    pub confidence: String, // "exact", "heuristic", "none"
    pub method: String,
}

// ── Paths ─────────────────────────────────────────────────────────────

fn projects_file_path() -> PathBuf {
    if let Ok(p) = std::env::var("KS_PROJECTS_FILE") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let home_path = PathBuf::from(&home).join("PROJECTS.yaml");
    if home_path.exists() {
        return home_path;
    }
    let cwd_path = PathBuf::from("PROJECTS.yaml");
    if cwd_path.exists() {
        return cwd_path;
    }
    home_path
}

// ── Core operations ───────────────────────────────────────────────────

pub fn load_projects_from(path: &PathBuf) -> Result<ProjectFile> {
    if !path.exists() {
        return Ok(ProjectFile { projects: vec![] });
    }
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let pf: ProjectFile = serde_yaml::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(pf)
}

pub fn save_projects_to(pf: &ProjectFile, path: &PathBuf) -> Result<()> {
    let content = serde_yaml::to_string(pf)?;
    let output = format!("---\n{content}");
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).context("failed to create parent directory")?;
    }
    std::fs::write(path, output).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Add a project. Returns false if slug already exists.
pub fn add_project(pf: &mut ProjectFile, project: Project) -> bool {
    if pf.projects.iter().any(|p| p.slug == project.slug) {
        return false;
    }
    pf.projects.push(project);
    true
}

/// Remove a project by slug. Returns true if found and removed.
pub fn remove_project(pf: &mut ProjectFile, slug: &str) -> bool {
    let before = pf.projects.len();
    pf.projects.retain(|p| p.slug != slug);
    pf.projects.len() < before
}

/// Normalize a repo URL to "owner/repo" format.
/// Handles: https://github.com/owner/repo.git, git@github.com:owner/repo, owner/repo
pub fn normalize_repo(url: &str) -> String {
    let s = url.trim().trim_end_matches('/');
    // Strip .git suffix
    let s = s.strip_suffix(".git").unwrap_or(s);
    // SSH format: git@host:owner/repo
    if let Some(after_colon) = s
        .strip_prefix("git@")
        .and_then(|s| s.split_once(':').map(|(_, r)| r))
    {
        return after_colon.to_string();
    }
    // HTTPS format: https://host/owner/repo
    if s.contains("://") {
        let parts: Vec<&str> = s.split('/').collect();
        if parts.len() >= 2 {
            let repo = parts[parts.len() - 1];
            let owner = parts[parts.len() - 2];
            if !owner.is_empty() && !repo.is_empty() {
                return format!("{owner}/{repo}");
            }
        }
    }
    // Already normalized or bare owner/repo
    s.to_string()
}

/// Detect project from a repo identifier. Exact match against project repos.
pub fn detect_by_repo(pf: &ProjectFile, repo_input: &str) -> DetectionResult {
    let normalized = normalize_repo(repo_input);
    for project in &pf.projects {
        for repo in &project.repos {
            if normalize_repo(repo) == normalized {
                return DetectionResult {
                    slug: Some(project.slug.clone()),
                    confidence: "exact".to_string(),
                    method: "repo-match".to_string(),
                };
            }
        }
    }
    DetectionResult {
        slug: None,
        confidence: "none".to_string(),
        method: "repo-match".to_string(),
    }
}

/// Detect project from subject text. Heuristic substring match.
pub fn detect_by_subject(pf: &ProjectFile, subject: &str) -> DetectionResult {
    let lower = subject.to_lowercase();
    let mut matches: Vec<&str> = Vec::new();

    for project in &pf.projects {
        let slug_match = lower.contains(&project.slug.to_lowercase());
        let name_match = project
            .name
            .as_ref()
            .map(|n| lower.contains(&n.to_lowercase()))
            .unwrap_or(false);

        if slug_match || name_match {
            matches.push(&project.slug);
        }
    }

    match matches.len() {
        1 => DetectionResult {
            slug: Some(matches[0].to_string()),
            confidence: "heuristic".to_string(),
            method: "subject-match".to_string(),
        },
        _ => DetectionResult {
            slug: None,
            confidence: "none".to_string(),
            method: "subject-match".to_string(),
        },
    }
}

/// Build a repo→project mapping for bulk detection.
pub fn build_repo_map(pf: &ProjectFile) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    for project in &pf.projects {
        for repo in &project.repos {
            map.insert(normalize_repo(repo), project.slug.clone());
        }
    }
    map
}

// ── Entry point ───────────────────────────────────────────────────────

pub async fn execute(args: &ProjectArgs) -> Result<()> {
    match &args.command {
        None => execute_list(args.json),
        Some(ProjectCommand::Show { slug }) => execute_show(slug, args.json),
        Some(ProjectCommand::Add {
            slug,
            name,
            repo,
            priority,
        }) => execute_add(slug, name.as_deref(), repo, *priority),
        Some(ProjectCommand::Remove { slug }) => execute_remove(slug),
        Some(ProjectCommand::Detect { repo, subject }) => {
            execute_detect(repo.as_deref(), subject.as_deref())
        }
        Some(ProjectCommand::Status { slug, all }) => {
            execute_status(slug.as_deref(), *all, args.json).await
        }
    }
}

// ── List ──────────────────────────────────────────────────────────────

fn execute_list(json: bool) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    if json {
        println!("{}", serde_json::to_string_pretty(&pf.projects)?);
        return Ok(());
    }

    if pf.projects.is_empty() {
        println!("No projects.");
        return Ok(());
    }

    for p in &pf.projects {
        let name = p.name.as_deref().unwrap_or(&p.slug);
        let pri = p
            .priority
            .map(|n| format!(" (pri: {n})"))
            .unwrap_or_default();
        let repos = if p.repos.is_empty() {
            String::new()
        } else {
            format!(" — {} repos", p.repos.len())
        };
        println!("  {}{pri}{repos}", name);
    }
    Ok(())
}

// ── Show ──────────────────────────────────────────────────────────────

fn execute_show(slug: &str, json: bool) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    match pf.projects.iter().find(|p| p.slug == slug) {
        Some(project) => {
            if json {
                println!("{}", serde_json::to_string_pretty(project)?);
            } else {
                println!(
                    "Project: {}",
                    project.name.as_deref().unwrap_or(&project.slug)
                );
                if let Some(desc) = &project.description {
                    println!("  {desc}");
                }
                if let Some(pri) = project.priority {
                    println!("  Priority: {pri}");
                }
                if !project.repos.is_empty() {
                    println!("  Repos:");
                    for r in &project.repos {
                        println!("    {r}");
                    }
                }
                if let Some(prov) = &project.provider {
                    println!("  Provider: {:?}", prov);
                }
            }
        }
        None => eprintln!("Project '{slug}' not found."),
    }
    Ok(())
}

// ── Add ───────────────────────────────────────────────────────────────

fn execute_add(
    slug: &str,
    name: Option<&str>,
    repos: &[String],
    priority: Option<u32>,
) -> Result<()> {
    // Validate slug: kebab-case (lowercase alphanumeric + hyphens, no leading/trailing hyphen)
    let valid = !slug.is_empty()
        && slug
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        && !slug.starts_with('-')
        && !slug.ends_with('-')
        && !slug.contains("--");
    if !valid {
        anyhow::bail!("Invalid slug '{slug}': must be kebab-case (e.g., 'my-project')");
    }

    let path = projects_file_path();
    let mut pf = load_projects_from(&path)?;

    let project = Project {
        slug: slug.to_string(),
        name: name.map(String::from),
        description: None,
        priority,
        repos: repos.iter().map(|r| normalize_repo(r)).collect(),
        sources: vec![],
        provider: None,
    };

    if add_project(&mut pf, project) {
        save_projects_to(&pf, &path)?;
        println!("Added: {slug}");
    } else {
        eprintln!("Project '{slug}' already exists.");
    }
    Ok(())
}

// ── Remove ────────────────────────────────────────────────────────────

fn execute_remove(slug: &str) -> Result<()> {
    let path = projects_file_path();
    let mut pf = load_projects_from(&path)?;

    if remove_project(&mut pf, slug) {
        save_projects_to(&pf, &path)?;
        println!("Removed: {slug}");
    } else {
        eprintln!("Project '{slug}' not found.");
    }
    Ok(())
}

// ── Detect ────────────────────────────────────────────────────────────

fn execute_detect(repo: Option<&str>, subject: Option<&str>) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    let result = if let Some(r) = repo {
        detect_by_repo(&pf, r)
    } else if let Some(s) = subject {
        detect_by_subject(&pf, s)
    } else {
        anyhow::bail!("Provide --repo or --subject for detection");
    };

    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

// ── Status ────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct ProjectStatus {
    project: Project,
    milestones: Vec<MilestoneStatus>,
    issues: Vec<IssueStatus>,
    pull_requests: Vec<PrStatus>,
    branches: Vec<BranchStatus>,
    recent_commits: Vec<CommitStatus>,
    tasks: HashMap<String, Vec<TaskSummary>>,
    attention: AttentionSection,
}

#[derive(Debug, Serialize)]
struct MilestoneStatus {
    repo: String,
    title: String,
    number: u64,
    due_on: Option<String>,
    open_issues: u64,
    closed_issues: u64,
    completion_pct: u64,
    flags: Vec<String>,
}

#[derive(Debug, Serialize)]
struct IssueStatus {
    repo: String,
    number: u64,
    title: String,
    state: String,
    milestone: Option<String>,
    labels: Vec<String>,
    assignees: Vec<String>,
    created_at: String,
    age_days: u64,
}

#[derive(Debug, Serialize)]
struct PrStatus {
    repo: String,
    number: u64,
    title: String,
    draft: bool,
    author: String,
    head_ref: String,
    milestone: Option<String>,
    created_at: String,
    age_days: u64,
    flags: Vec<String>,
}

#[derive(Debug, Serialize)]
struct BranchStatus {
    repo: String,
    name: String,
    owner: String,
    pr_number: Option<u64>,
    pr_state: Option<String>,
    worktree_path: Option<String>,
    checkout_path: Option<String>,
    commits_ahead: u64,
    last_commit_age_days: u64,
    merged: bool,
    flags: Vec<String>,
}

#[derive(Debug, Serialize)]
struct CommitStatus {
    repo: String,
    sha: String,
    message: String,
    age_days: u64,
}

#[derive(Debug, Serialize)]
struct TaskSummary {
    name: String,
    status: String,
    project: Option<String>,
    source: Option<String>,
    source_ref: Option<String>,
    blocked_reason: Option<String>,
}

#[derive(Debug, Serialize)]
struct AttentionSection {
    stale_prs: Vec<serde_json::Value>,
    issues_without_milestone: Vec<serde_json::Value>,
    milestones_without_due_date: Vec<serde_json::Value>,
    stale_branches: Vec<serde_json::Value>,
    merged_branches_to_cleanup: Vec<serde_json::Value>,
}

/// Resolve slug from cwd git remote when no slug is provided.
async fn resolve_slug_from_cwd() -> Result<Option<String>> {
    let output = Command::new("git")
        .args(["remote", "get-url", "origin"])
        .output()
        .await;

    let url = match output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        _ => return Ok(None),
    };

    if url.is_empty() {
        return Ok(None);
    }

    let path = projects_file_path();
    let pf = load_projects_from(&path)?;
    let result = detect_by_repo(&pf, &url);
    Ok(result.slug)
}

/// Determine whether a repo is hosted on GitHub (vs Forgejo/other).
fn is_github_repo(repo: &str) -> bool {
    // Simple heuristic: GitHub repos don't contain a custom domain
    // Forgejo repos in this codebase use git.ncrmro.com
    !repo.contains("git.ncrmro.com")
}

/// Fetch milestones, issues, PRs, and commits for a GitHub repo via GraphQL.
async fn fetch_github_repo_status(
    owner: &str,
    repo_name: &str,
    full_repo: &str,
) -> (
    Vec<MilestoneStatus>,
    Vec<IssueStatus>,
    Vec<PrStatus>,
    Vec<CommitStatus>,
) {
    let query = r#"
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    milestones(states: [OPEN], first: 10, orderBy: {field: DUE_DATE, direction: ASC}) {
      nodes {
        title
        number
        dueOn
        open: issues(states: [OPEN]) { totalCount }
        closed: issues(states: [CLOSED]) { totalCount }
      }
    }
    issues(states: [OPEN], first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        title
        createdAt
        labels(first: 5) { nodes { name } }
        assignees(first: 3) { nodes { login } }
        milestone { title }
      }
    }
    pullRequests(states: [OPEN], first: 20) {
      nodes {
        number
        title
        isDraft
        createdAt
        author { login }
        headRefName
        milestone { title }
      }
    }
    defaultBranchRef {
      target {
        ... on Commit {
          history(first: 10) {
            nodes { oid messageHeadline committedDate }
          }
        }
      }
    }
  }
}
"#;

    let variables = serde_json::json!({
        "owner": owner,
        "repo": repo_name,
    });

    let resp = match crate::platform::github_graphql(query, variables).await {
        Ok(r) => r,
        Err(e) => {
            eprintln!("warning: GitHub GraphQL failed for {full_repo}: {e}");
            return (vec![], vec![], vec![], vec![]);
        }
    };

    let repo_data = match resp.pointer("/data/repository") {
        Some(r) => r,
        None => return (vec![], vec![], vec![], vec![]),
    };

    // Parse milestones
    let milestones = parse_github_milestones(repo_data, full_repo);

    // Parse issues
    let issues = parse_github_issues(repo_data, full_repo);

    // Parse PRs
    let prs = parse_github_prs(repo_data, full_repo);

    // Parse recent commits
    let commits = parse_github_commits(repo_data, full_repo);

    (milestones, issues, prs, commits)
}

fn parse_github_milestones(repo_data: &serde_json::Value, full_repo: &str) -> Vec<MilestoneStatus> {
    let mut milestones = Vec::new();
    if let Some(nodes) = repo_data
        .pointer("/milestones/nodes")
        .and_then(|n| n.as_array())
    {
        for node in nodes {
            let title = node
                .get("title")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();
            let number = node.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            let due_on = node.get("dueOn").and_then(|d| d.as_str()).map(String::from);
            let open = node
                .pointer("/open/totalCount")
                .and_then(|n| n.as_u64())
                .unwrap_or(0);
            let closed = node
                .pointer("/closed/totalCount")
                .and_then(|n| n.as_u64())
                .unwrap_or(0);
            let total = open + closed;
            let pct = (closed * 100).checked_div(total).unwrap_or(0);

            let mut flags = Vec::new();
            if due_on.is_none() {
                flags.push("no-due-date".to_string());
            }

            milestones.push(MilestoneStatus {
                repo: full_repo.to_string(),
                title,
                number,
                due_on,
                open_issues: open,
                closed_issues: closed,
                completion_pct: pct,
                flags,
            });
        }
    }
    milestones
}

fn parse_github_issues(repo_data: &serde_json::Value, full_repo: &str) -> Vec<IssueStatus> {
    let mut issues = Vec::new();
    if let Some(nodes) = repo_data
        .pointer("/issues/nodes")
        .and_then(|n| n.as_array())
    {
        for node in nodes {
            let number = node.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            let title = node
                .get("title")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();
            let created_at = node
                .get("createdAt")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            let milestone = node
                .pointer("/milestone/title")
                .and_then(|m| m.as_str())
                .map(String::from);
            let labels: Vec<String> = node
                .pointer("/labels/nodes")
                .and_then(|n| n.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|l| l.get("name").and_then(|n| n.as_str()).map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let assignees: Vec<String> = node
                .pointer("/assignees/nodes")
                .and_then(|n| n.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|a| a.get("login").and_then(|l| l.as_str()).map(String::from))
                        .collect()
                })
                .unwrap_or_default();

            let age_days = crate::time::days_since(&created_at);

            issues.push(IssueStatus {
                repo: full_repo.to_string(),
                number,
                title,
                state: "open".to_string(),
                milestone,
                labels,
                assignees,
                created_at,
                age_days,
            });
        }
    }
    issues
}

fn parse_github_prs(repo_data: &serde_json::Value, full_repo: &str) -> Vec<PrStatus> {
    let mut prs = Vec::new();
    if let Some(nodes) = repo_data
        .pointer("/pullRequests/nodes")
        .and_then(|n| n.as_array())
    {
        for node in nodes {
            let number = node.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            let title = node
                .get("title")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();
            let draft = node
                .get("isDraft")
                .and_then(|d| d.as_bool())
                .unwrap_or(false);
            let created_at = node
                .get("createdAt")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            let author = node
                .pointer("/author/login")
                .and_then(|a| a.as_str())
                .unwrap_or("")
                .to_string();
            let head_ref = node
                .get("headRefName")
                .and_then(|h| h.as_str())
                .unwrap_or("")
                .to_string();
            let milestone = node
                .pointer("/milestone/title")
                .and_then(|m| m.as_str())
                .map(String::from);

            let age_days = crate::time::days_since(&created_at);
            let mut flags = Vec::new();
            if age_days > 14 {
                flags.push("stale".to_string());
            }
            if draft {
                flags.push("draft".to_string());
            }

            prs.push(PrStatus {
                repo: full_repo.to_string(),
                number,
                title,
                draft,
                author,
                head_ref,
                milestone,
                created_at,
                age_days,
                flags,
            });
        }
    }
    prs
}

fn parse_github_commits(repo_data: &serde_json::Value, full_repo: &str) -> Vec<CommitStatus> {
    let mut commits = Vec::new();
    let nodes = repo_data
        .pointer("/defaultBranchRef/target/history/nodes")
        .and_then(|n| n.as_array());

    if let Some(nodes) = nodes {
        for node in nodes {
            let sha = node
                .get("oid")
                .and_then(|o| o.as_str())
                .unwrap_or("")
                .to_string();
            let message = node
                .get("messageHeadline")
                .and_then(|m| m.as_str())
                .unwrap_or("")
                .to_string();
            let date = node
                .get("committedDate")
                .and_then(|d| d.as_str())
                .unwrap_or("");
            let age_days = crate::time::days_since(date);

            commits.push(CommitStatus {
                repo: full_repo.to_string(),
                sha,
                message,
                age_days,
            });
        }
    }
    commits
}

/// Fetch milestones, issues, and PRs for a Forgejo repo via REST.
async fn fetch_forgejo_repo_status(
    host: &str,
    token: &str,
    full_repo: &str,
) -> (Vec<MilestoneStatus>, Vec<IssueStatus>, Vec<PrStatus>) {
    let ms_endpoint = format!("/repos/{full_repo}/milestones?state=open");
    let issues_endpoint = format!("/repos/{full_repo}/issues?state=open&type=issues");
    let prs_endpoint = format!("/repos/{full_repo}/pulls?state=open");

    let ms_fut = crate::platform::forgejo_rest(host, token, &ms_endpoint);
    let issues_fut = crate::platform::forgejo_rest(host, token, &issues_endpoint);
    let prs_fut = crate::platform::forgejo_rest(host, token, &prs_endpoint);

    let (ms_res, issues_res, prs_res) = futures::future::join3(ms_fut, issues_fut, prs_fut).await;

    let milestones = ms_res
        .map(|v| parse_forgejo_milestones(&v, full_repo))
        .unwrap_or_default();

    let issues = issues_res
        .map(|v| parse_forgejo_issues(&v, full_repo))
        .unwrap_or_default();

    let prs = prs_res
        .map(|v| parse_forgejo_prs(&v, full_repo))
        .unwrap_or_default();

    (milestones, issues, prs)
}

fn parse_forgejo_milestones(data: &serde_json::Value, full_repo: &str) -> Vec<MilestoneStatus> {
    let arr = match data.as_array() {
        Some(a) => a,
        None => return vec![],
    };
    arr.iter()
        .map(|m| {
            let title = m
                .get("title")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();
            let number = m.get("id").and_then(|n| n.as_u64()).unwrap_or(0);
            let due_on = m
                .get("due_on")
                .and_then(|d| d.as_str())
                .filter(|s| !s.is_empty() && *s != "null")
                .map(String::from);
            let open = m.get("open_issues").and_then(|n| n.as_u64()).unwrap_or(0);
            let closed = m.get("closed_issues").and_then(|n| n.as_u64()).unwrap_or(0);
            let total = open + closed;
            let pct = (closed * 100).checked_div(total).unwrap_or(0);
            let mut flags = Vec::new();
            if due_on.is_none() {
                flags.push("no-due-date".to_string());
            }
            MilestoneStatus {
                repo: full_repo.to_string(),
                title,
                number,
                due_on,
                open_issues: open,
                closed_issues: closed,
                completion_pct: pct,
                flags,
            }
        })
        .collect()
}

fn parse_forgejo_issues(data: &serde_json::Value, full_repo: &str) -> Vec<IssueStatus> {
    let arr = match data.as_array() {
        Some(a) => a,
        None => return vec![],
    };
    arr.iter()
        .map(|i| {
            let number = i.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            let title = i
                .get("title")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();
            let created_at = i
                .get("created_at")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            let milestone = i
                .pointer("/milestone/title")
                .and_then(|m| m.as_str())
                .map(String::from);
            let labels: Vec<String> = i
                .get("labels")
                .and_then(|l| l.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|l| l.get("name").and_then(|n| n.as_str()).map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let assignees: Vec<String> = i
                .get("assignees")
                .and_then(|a| a.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|a| a.get("login").and_then(|l| l.as_str()).map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let age_days = crate::time::days_since(&created_at);
            IssueStatus {
                repo: full_repo.to_string(),
                number,
                title,
                state: "open".to_string(),
                milestone,
                labels,
                assignees,
                created_at,
                age_days,
            }
        })
        .collect()
}

fn parse_forgejo_prs(data: &serde_json::Value, full_repo: &str) -> Vec<PrStatus> {
    let arr = match data.as_array() {
        Some(a) => a,
        None => return vec![],
    };
    arr.iter()
        .map(|p| {
            let number = p.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            let title = p
                .get("title")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();
            let created_at = p
                .get("created_at")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            let author = p
                .pointer("/user/login")
                .and_then(|a| a.as_str())
                .unwrap_or("")
                .to_string();
            let head_ref = p
                .pointer("/head/ref")
                .and_then(|h| h.as_str())
                .unwrap_or("")
                .to_string();
            let milestone = p
                .pointer("/milestone/title")
                .and_then(|m| m.as_str())
                .map(String::from);
            // Forgejo REST does not have an isDraft field in the list endpoint
            let draft = false;
            let age_days = crate::time::days_since(&created_at);
            let mut flags = Vec::new();
            if age_days > 14 {
                flags.push("stale".to_string());
            }
            PrStatus {
                repo: full_repo.to_string(),
                number,
                title,
                draft,
                author,
                head_ref,
                milestone,
                created_at,
                age_days,
                flags,
            }
        })
        .collect()
}

/// Resolve the default branch ref for a checkout (origin/main or origin/master).
async fn resolve_default_branch(checkout_path: &str) -> String {
    // Try origin/HEAD first (set by git clone)
    let output = Command::new("git")
        .args([
            "-C",
            checkout_path,
            "symbolic-ref",
            "refs/remotes/origin/HEAD",
        ])
        .output()
        .await;

    if let Ok(o) = output {
        if o.status.success() {
            let refname = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if !refname.is_empty() {
                return refname;
            }
        }
    }

    // Fallback: check if origin/main exists
    let main_check = Command::new("git")
        .args(["-C", checkout_path, "rev-parse", "--verify", "origin/main"])
        .output()
        .await;

    if main_check.map(|o| o.status.success()).unwrap_or(false) {
        return "origin/main".to_string();
    }

    // Last resort
    "origin/master".to_string()
}

/// Discover local git checkouts and worktrees for a repo across all users.
fn discover_checkouts(full_repo: &str) -> Vec<(PathBuf, String)> {
    let parts: Vec<&str> = full_repo.split('/').collect();
    if parts.len() != 2 {
        return Vec::new();
    }
    let (owner, repo_name) = (parts[0], parts[1]);
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let mut checkout_paths = Vec::new();

    // Human: ~/repos/{owner}/{repo}/ and ~/repos/{owner}/{repo}/worktrees/*/
    let main_checkout = PathBuf::from(&home)
        .join("repos")
        .join(owner)
        .join(repo_name);
    if main_checkout.exists() {
        checkout_paths.push((main_checkout.clone(), home.clone()));
        collect_worktree_dirs(&main_checkout.join("worktrees"), &home, &mut checkout_paths);
    }

    // Agents: /home/agent-*/repos/{owner}/{repo}/worktrees/*/
    if let Ok(entries) = std::fs::read_dir("/home") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !name.starts_with("agent-") {
                continue;
            }
            let agent_home = entry.path();
            let agent_home_str = agent_home.to_string_lossy().to_string();
            let agent_checkout = agent_home.join("repos").join(owner).join(repo_name);
            if agent_checkout.exists() {
                checkout_paths.push((agent_checkout.clone(), agent_home_str.clone()));
                collect_worktree_dirs(
                    &agent_checkout.join("worktrees"),
                    &agent_home_str,
                    &mut checkout_paths,
                );
            }
        }
    }

    checkout_paths
}

/// Collect git worktree directories below a repo-owned worktrees path.
fn collect_worktree_dirs(base: &Path, owner_home: &str, out: &mut Vec<(PathBuf, String)>) {
    if !base.exists() {
        return;
    }
    if let Ok(entries) = std::fs::read_dir(base) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if path.join(".git").exists() {
                    out.push((path, owner_home.to_string()));
                } else {
                    collect_worktree_dirs(&path, owner_home, out);
                }
            }
        }
    }
}

/// Parse branches from a single git checkout using batched git commands.
/// Uses `for-each-ref` with creatordate to avoid per-branch git log calls.
async fn parse_checkout_branches(
    checkout_path: &Path,
    owner_home: &str,
    full_repo: &str,
    pr_head_refs: &HashMap<String, (u64, String)>,
) -> Vec<BranchStatus> {
    let checkout_str = checkout_path.to_string_lossy().to_string();
    let owner_name = PathBuf::from(owner_home)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    // Resolve default branch (origin/main or origin/master)
    let default_ref = resolve_default_branch(&checkout_str).await;

    // One call: branches + ahead count + last commit date
    let branch_output = Command::new("git")
        .args([
            "-C",
            &checkout_str,
            "for-each-ref",
            &format!(
                "--format=%(refname:short)\t%(ahead-behind:{})\t%(creatordate:iso)",
                default_ref
            ),
            "refs/heads/",
        ])
        .output()
        .await;

    // One call: merged branches (relative to default branch, not HEAD)
    let merged_output = Command::new("git")
        .args(["-C", &checkout_str, "branch", "--merged", &default_ref])
        .output()
        .await;

    let merged_set: std::collections::HashSet<String> = merged_output
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .map(|l| l.trim().trim_start_matches("* ").to_string())
                .collect()
        })
        .unwrap_or_default();

    let is_worktree = checkout_str.contains("/worktrees/");
    let mut branches = Vec::new();

    let output = match branch_output {
        Ok(o) if o.status.success() => o,
        _ => return branches,
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.is_empty() {
            continue;
        }
        let branch_name = fields[0].to_string();
        if branch_name == "main" || branch_name == "master" {
            continue;
        }

        let ahead = fields
            .get(1)
            .and_then(|f| f.split_whitespace().next())
            .and_then(|n| n.parse::<u64>().ok())
            .unwrap_or(0);

        let last_commit_age = fields
            .get(2)
            .map(|d| crate::time::days_since(d.trim()))
            .unwrap_or(0);

        let merged = merged_set.contains(&branch_name);
        let (pr_number, pr_state) = pr_head_refs
            .get(&branch_name)
            .map(|(n, s)| (Some(*n), Some(s.clone())))
            .unwrap_or((None, None));

        let mut flags = Vec::new();
        if last_commit_age > 14 && !merged {
            flags.push("stale".to_string());
        }
        if merged {
            flags.push("cleanup-candidate".to_string());
        }

        branches.push(BranchStatus {
            repo: full_repo.to_string(),
            name: branch_name,
            owner: owner_name.clone(),
            pr_number,
            pr_state,
            worktree_path: if is_worktree {
                Some(checkout_str.clone())
            } else {
                None
            },
            checkout_path: if !is_worktree {
                Some(checkout_str.clone())
            } else {
                None
            },
            commits_ahead: ahead,
            last_commit_age_days: last_commit_age,
            merged,
            flags,
        });
    }

    branches
}

/// Discover local git checkouts and worktrees for a repo, gather branch info.
async fn gather_local_branches(
    full_repo: &str,
    pr_head_refs: &HashMap<String, (u64, String)>,
) -> Vec<BranchStatus> {
    let checkout_paths = discover_checkouts(full_repo);
    let mut all_branches = Vec::new();

    for (checkout_path, owner_home) in &checkout_paths {
        let branches =
            parse_checkout_branches(checkout_path, owner_home, full_repo, pr_head_refs).await;
        all_branches.extend(branches);
    }

    all_branches
}

/// Load tasks from home TASKS.yaml files, filtered by project slug.
fn gather_tasks(slug: &str) -> HashMap<String, Vec<TaskSummary>> {
    let mut result: HashMap<String, Vec<TaskSummary>> = HashMap::new();

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let mut paths: Vec<(String, PathBuf)> = Vec::new();

    // Current user
    let user_name = PathBuf::from(&home)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "user".to_string());
    let user_tasks = PathBuf::from(&home).join("TASKS.yaml");
    paths.push((user_name, user_tasks));

    // Agent users
    if let Ok(entries) = std::fs::read_dir("/home") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("agent-") {
                let agent_tasks = entry.path().join("TASKS.yaml");
                paths.push((name, agent_tasks));
            }
        }
    }

    for (owner_name, path) in &paths {
        if let Ok(tf) = crate::cmd::tasks::load_tasks_from(path) {
            let filtered: Vec<TaskSummary> = tf
                .tasks
                .iter()
                .filter(|t| t.project.as_deref() == Some(slug))
                .map(|t| TaskSummary {
                    name: t.name.clone(),
                    status: t.status.clone(),
                    project: t.project.clone(),
                    source: t.source.clone(),
                    source_ref: t.source_ref.clone(),
                    blocked_reason: t.blocked_reason.clone(),
                })
                .collect();
            if !filtered.is_empty() {
                result.insert(owner_name.clone(), filtered);
            }
        }
    }

    result
}

/// Sort milestones: due_on ascending, None last.
fn sort_milestones(milestones: &mut [MilestoneStatus]) {
    milestones.sort_by(|a, b| match (&a.due_on, &b.due_on) {
        (Some(da), Some(db)) => da.cmp(db),
        (Some(_), None) => std::cmp::Ordering::Less,
        (None, Some(_)) => std::cmp::Ordering::Greater,
        (None, None) => a.title.cmp(&b.title),
    });
}

/// Compute the attention section from aggregated status data.
fn compute_attention(
    milestones: &[MilestoneStatus],
    issues: &[IssueStatus],
    prs: &[PrStatus],
    branches: &[BranchStatus],
) -> AttentionSection {
    let stale_prs: Vec<serde_json::Value> = prs
        .iter()
        .filter(|p| p.age_days > 14)
        .map(|p| serde_json::json!({"repo": &p.repo, "number": p.number, "title": &p.title, "age_days": p.age_days}))
        .collect();

    let issues_without_milestone: Vec<serde_json::Value> = issues
        .iter()
        .filter(|i| i.milestone.is_none())
        .map(|i| serde_json::json!({"repo": &i.repo, "number": i.number, "title": &i.title}))
        .collect();

    let milestones_without_due_date: Vec<serde_json::Value> = milestones
        .iter()
        .filter(|m| m.due_on.is_none())
        .map(|m| serde_json::json!({"repo": &m.repo, "title": &m.title, "number": m.number}))
        .collect();

    let stale_branches: Vec<serde_json::Value> = branches
        .iter()
        .filter(|b| b.last_commit_age_days > 14 && !b.merged)
        .map(|b| serde_json::json!({"repo": &b.repo, "name": &b.name, "owner": &b.owner, "age_days": b.last_commit_age_days}))
        .collect();

    let merged_branches_to_cleanup: Vec<serde_json::Value> = branches
        .iter()
        .filter(|b| b.merged)
        .map(|b| serde_json::json!({"repo": &b.repo, "name": &b.name, "owner": &b.owner}))
        .collect();

    AttentionSection {
        stale_prs,
        issues_without_milestone,
        milestones_without_due_date,
        stale_branches,
        merged_branches_to_cleanup,
    }
}

/// Execute the status subcommand for a single project.
async fn execute_status_single(slug: &str, json: bool) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    let project = pf
        .projects
        .iter()
        .find(|p| p.slug == slug)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("project '{slug}' not found"))?;

    let mut all_milestones = Vec::new();
    let mut all_issues = Vec::new();
    let mut all_prs = Vec::new();
    let mut all_commits = Vec::new();
    let mut all_branches = Vec::new();

    let fj_host = std::env::var("FORGEJO_HOST").ok();
    let fj_token = std::env::var("FORGEJO_TOKEN").ok();

    for repo in &project.repos {
        let normalized = normalize_repo(repo);
        let parts: Vec<&str> = normalized.split('/').collect();
        if parts.len() != 2 {
            continue;
        }

        // Per-repo PR head ref map to avoid cross-repo branch/PR mismatches
        let mut repo_pr_head_refs: HashMap<String, (u64, String)> = HashMap::new();

        if is_github_repo(repo) {
            let (ms, issues, prs, commits) =
                fetch_github_repo_status(parts[0], parts[1], &normalized).await;

            for pr in &prs {
                repo_pr_head_refs.insert(pr.head_ref.clone(), (pr.number, "open".to_string()));
            }

            all_milestones.extend(ms);
            all_issues.extend(issues);
            all_prs.extend(prs);
            all_commits.extend(commits);
        } else if let (Some(ref host), Some(ref token)) = (&fj_host, &fj_token) {
            let (ms, issues, prs) = fetch_forgejo_repo_status(host, token, &normalized).await;

            for pr in &prs {
                repo_pr_head_refs.insert(pr.head_ref.clone(), (pr.number, "open".to_string()));
            }

            all_milestones.extend(ms);
            all_issues.extend(issues);
            all_prs.extend(prs);
        }

        // Gather local branches scoped to this repo's PRs
        let branches = gather_local_branches(&normalized, &repo_pr_head_refs).await;
        all_branches.extend(branches);
    }

    // Sort milestones
    sort_milestones(&mut all_milestones);

    // Gather tasks
    let tasks = gather_tasks(slug);

    // Compute attention
    let attention = compute_attention(&all_milestones, &all_issues, &all_prs, &all_branches);

    let status = ProjectStatus {
        project,
        milestones: all_milestones,
        issues: all_issues,
        pull_requests: all_prs,
        branches: all_branches,
        recent_commits: all_commits,
        tasks,
        attention,
    };

    if json {
        println!("{}", serde_json::to_string_pretty(&status)?);
    } else {
        render_status_human(&status);
    }

    Ok(())
}

#[allow(clippy::cognitive_complexity)]
fn render_status_human(status: &ProjectStatus) {
    let name = status
        .project
        .name
        .as_deref()
        .unwrap_or(&status.project.slug);
    println!("Project: {name}\n");

    // Milestones
    if !status.milestones.is_empty() {
        println!("Milestones:");
        for m in &status.milestones {
            let due = m.due_on.as_deref().unwrap_or("no due date");
            println!(
                "  {} ({}/{} closed, {}%) — {due}",
                m.title,
                m.closed_issues,
                m.open_issues + m.closed_issues,
                m.completion_pct
            );
        }
        println!();
    }

    // Issues
    if !status.issues.is_empty() {
        println!("Open issues ({}):", status.issues.len());
        for i in &status.issues {
            let ms = i
                .milestone
                .as_ref()
                .map(|m| format!(" [{m}]"))
                .unwrap_or_default();
            println!("  {}#{}: {}{ms}", i.repo, i.number, i.title);
        }
        println!();
    }

    // PRs
    if !status.pull_requests.is_empty() {
        println!("Open PRs ({}):", status.pull_requests.len());
        for p in &status.pull_requests {
            let draft_label = if p.draft { " [draft]" } else { "" };
            let flags = if p.flags.is_empty() {
                String::new()
            } else {
                format!(" ({})", p.flags.join(", "))
            };
            println!(
                "  {}#{}: {} by {}{draft_label}{flags}",
                p.repo, p.number, p.title, p.author
            );
        }
        println!();
    }

    // Branches
    if !status.branches.is_empty() {
        println!("Branches ({}):", status.branches.len());
        for b in &status.branches {
            let pr = b.pr_number.map(|n| format!(" PR#{n}")).unwrap_or_default();
            let flags = if b.flags.is_empty() {
                String::new()
            } else {
                format!(" ({})", b.flags.join(", "))
            };
            println!(
                "  {} [{}] +{} commits{pr}{flags}",
                b.name, b.owner, b.commits_ahead
            );
        }
        println!();
    }

    // Recent commits
    if !status.recent_commits.is_empty() {
        println!("Recent commits:");
        for c in &status.recent_commits {
            let short_sha = if c.sha.len() >= 7 {
                &c.sha[..7]
            } else {
                &c.sha
            };
            println!("  {short_sha} {} ({}d ago)", c.message, c.age_days);
        }
        println!();
    }

    // Tasks
    if !status.tasks.is_empty() {
        println!("Tasks:");
        for (owner, tasks) in &status.tasks {
            println!("  {owner}:");
            for t in tasks {
                println!("    {} [{}]", t.name, t.status);
            }
        }
        println!();
    }

    // Attention
    let att = &status.attention;
    let attention_items = att.stale_prs.len()
        + att.issues_without_milestone.len()
        + att.milestones_without_due_date.len()
        + att.stale_branches.len()
        + att.merged_branches_to_cleanup.len();

    if attention_items > 0 {
        println!("Attention ({attention_items} items):");
        for p in &att.stale_prs {
            let repo = p.get("repo").and_then(|r| r.as_str()).unwrap_or("");
            let num = p.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            let age = p.get("age_days").and_then(|a| a.as_u64()).unwrap_or(0);
            println!("  Stale PR: {repo}#{num} ({age}d)");
        }
        for i in &att.issues_without_milestone {
            let repo = i.get("repo").and_then(|r| r.as_str()).unwrap_or("");
            let num = i.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
            println!("  No milestone: {repo}#{num}");
        }
        for m in &att.milestones_without_due_date {
            let title = m.get("title").and_then(|t| t.as_str()).unwrap_or("");
            println!("  No due date: milestone \"{title}\"");
        }
        for b in &att.stale_branches {
            let name = b.get("name").and_then(|n| n.as_str()).unwrap_or("");
            let age = b.get("age_days").and_then(|a| a.as_u64()).unwrap_or(0);
            println!("  Stale branch: {name} ({age}d)");
        }
        for b in &att.merged_branches_to_cleanup {
            let name = b.get("name").and_then(|n| n.as_str()).unwrap_or("");
            println!("  Cleanup: {name} (merged)");
        }
    }
}

async fn execute_status(slug: Option<&str>, all: bool, json: bool) -> Result<()> {
    if all {
        let path = projects_file_path();
        let pf = load_projects_from(&path)?;

        if pf.projects.is_empty() {
            if json {
                println!("[]");
            } else {
                println!("No projects configured.");
            }
            return Ok(());
        }

        // For --all mode with JSON, collect all statuses (we run them sequentially
        // to avoid overwhelming API rate limits)
        if json {
            // Collect all project slugs, then run each
            let slugs: Vec<String> = pf.projects.iter().map(|p| p.slug.clone()).collect();
            print!("[");
            for (i, s) in slugs.iter().enumerate() {
                if i > 0 {
                    print!(",");
                }
                // For --all --json we print each individually
                // (simpler than collecting into a Vec<ProjectStatus>)
                execute_status_single(s, true).await?;
            }
            println!("]");
        } else {
            for p in &pf.projects {
                println!("═══ {} ═══\n", p.name.as_deref().unwrap_or(&p.slug));
                execute_status_single(&p.slug, false).await?;
                println!();
            }
        }
        return Ok(());
    }

    let resolved_slug = match slug {
        Some(s) => s.to_string(),
        None => resolve_slug_from_cwd()
            .await?
            .ok_or_else(|| anyhow::anyhow!("could not detect project from cwd; provide a slug"))?,
    };

    execute_status_single(&resolved_slug, json).await
}

// ── Tests ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    fn make_project(slug: &str, repos: &[&str]) -> Project {
        Project {
            slug: slug.to_string(),
            name: Some(slug.replace('-', " ").to_string()),
            description: None,
            priority: None,
            repos: repos.iter().map(|r| r.to_string()).collect(),
            sources: vec![],
            provider: None,
        }
    }

    // ── YAML round-trip ───────────────────────────────────────────

    #[test]
    fn test_yaml_round_trip() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let tmp = NamedTempFile::new().unwrap();
        save_projects_to(&pf, &tmp.path().to_path_buf()).unwrap();
        let loaded = load_projects_from(&tmp.path().to_path_buf()).unwrap();
        assert_eq!(loaded.projects.len(), 1);
        assert_eq!(loaded.projects[0].slug, "keystone");
    }

    #[test]
    fn test_load_missing_file() {
        let path = PathBuf::from("/tmp/nonexistent-ks-projects.yaml");
        let result = load_projects_from(&path).unwrap();
        assert!(result.projects.is_empty());
    }

    // ── add / remove ──────────────────────────────────────────────

    #[test]
    fn test_add_project() {
        let mut pf = ProjectFile { projects: vec![] };
        assert!(add_project(&mut pf, make_project("keystone", &[])));
        assert_eq!(pf.projects.len(), 1);
    }

    #[test]
    fn test_add_project_dedup() {
        let mut pf = ProjectFile {
            projects: vec![make_project("keystone", &[])],
        };
        assert!(!add_project(&mut pf, make_project("keystone", &[])));
        assert_eq!(pf.projects.len(), 1);
    }

    #[test]
    fn test_remove_project() {
        let mut pf = ProjectFile {
            projects: vec![make_project("keystone", &[])],
        };
        assert!(remove_project(&mut pf, "keystone"));
        assert!(pf.projects.is_empty());
    }

    #[test]
    fn test_remove_project_not_found() {
        let mut pf = ProjectFile { projects: vec![] };
        assert!(!remove_project(&mut pf, "missing"));
    }

    // ── normalize_repo ────────────────────────────────────────────

    #[test]
    fn test_normalize_bare() {
        assert_eq!(normalize_repo("ncrmro/keystone"), "ncrmro/keystone");
    }

    #[test]
    fn test_normalize_https() {
        assert_eq!(
            normalize_repo("https://github.com/ncrmro/keystone.git"),
            "ncrmro/keystone"
        );
    }

    #[test]
    fn test_normalize_ssh() {
        assert_eq!(
            normalize_repo("git@github.com:ncrmro/keystone.git"),
            "ncrmro/keystone"
        );
    }

    #[test]
    fn test_normalize_https_no_git() {
        assert_eq!(
            normalize_repo("https://github.com/ncrmro/keystone"),
            "ncrmro/keystone"
        );
    }

    // ── detect_by_repo ────────────────────────────────────────────

    #[test]
    fn test_detect_repo_exact() {
        let pf = ProjectFile {
            projects: vec![make_project(
                "keystone",
                &["ncrmro/keystone", "ncrmro/nixos-config"],
            )],
        };
        let result = detect_by_repo(&pf, "ncrmro/keystone");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "exact");
    }

    #[test]
    fn test_detect_repo_normalized_url() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let result = detect_by_repo(&pf, "https://github.com/ncrmro/keystone.git");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "exact");
    }

    #[test]
    fn test_detect_repo_no_match() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let result = detect_by_repo(&pf, "other/repo");
        assert_eq!(result.slug, None);
        assert_eq!(result.confidence, "none");
    }

    // ── detect_by_subject ─────────────────────────────────────────

    #[test]
    fn test_detect_subject_single_match() {
        let pf = ProjectFile {
            projects: vec![
                make_project("keystone", &[]),
                make_project("plant-caravan", &[]),
            ],
        };
        let result = detect_by_subject(&pf, "Fix keystone build failure");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "heuristic");
    }

    #[test]
    fn test_detect_subject_ambiguous() {
        // Use names that both substring-match the subject
        let mut p1 = make_project("proj-a", &[]);
        p1.name = Some("Cloud Platform".to_string());
        let mut p2 = make_project("proj-b", &[]);
        p2.name = Some("Cloud Storage".to_string());
        let pf = ProjectFile {
            projects: vec![p1, p2],
        };
        // "cloud" matches both names
        let result = detect_by_subject(&pf, "cloud migration plan");
        assert_eq!(result.slug, None);
        assert_eq!(result.confidence, "none");
    }

    #[test]
    fn test_detect_subject_no_match() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &[])],
        };
        let result = detect_by_subject(&pf, "unrelated topic");
        assert_eq!(result.slug, None);
        assert_eq!(result.confidence, "none");
    }

    #[test]
    fn test_detect_subject_by_name() {
        let mut p = make_project("pc", &[]);
        p.name = Some("Plant Caravan".to_string());
        let pf = ProjectFile { projects: vec![p] };
        let result = detect_by_subject(&pf, "Plant Caravan sensor issue");
        assert_eq!(result.slug, Some("pc".to_string()));
        assert_eq!(result.confidence, "heuristic");
    }

    // ── build_repo_map ────────────────────────────────────────────

    #[test]
    fn test_build_repo_map() {
        let pf = ProjectFile {
            projects: vec![
                make_project("keystone", &["ncrmro/keystone", "ncrmro/nixos-config"]),
                make_project("caravan", &["ncrmro/plant-caravan"]),
            ],
        };
        let map = build_repo_map(&pf);
        assert_eq!(map.get("ncrmro/keystone"), Some(&"keystone".to_string()));
        assert_eq!(
            map.get("ncrmro/plant-caravan"),
            Some(&"caravan".to_string())
        );
        assert_eq!(map.len(), 3);
    }

    // ── Status: milestone sorting ────────────────────────────────

    fn make_milestone(title: &str, due_on: Option<&str>) -> MilestoneStatus {
        MilestoneStatus {
            repo: "test/repo".to_string(),
            title: title.to_string(),
            number: 1,
            due_on: due_on.map(String::from),
            open_issues: 5,
            closed_issues: 3,
            completion_pct: 37,
            flags: vec![],
        }
    }

    #[test]
    fn test_milestone_sort_due_dates_ascending() {
        let mut milestones = vec![
            make_milestone("Late", Some("2026-06-01")),
            make_milestone("Early", Some("2026-01-15")),
            make_milestone("Mid", Some("2026-03-10")),
        ];
        sort_milestones(&mut milestones);
        assert_eq!(milestones[0].title, "Early");
        assert_eq!(milestones[1].title, "Mid");
        assert_eq!(milestones[2].title, "Late");
    }

    #[test]
    fn test_milestone_sort_none_last() {
        let mut milestones = vec![
            make_milestone("No date", None),
            make_milestone("Has date", Some("2026-01-01")),
            make_milestone("Also no date", None),
        ];
        sort_milestones(&mut milestones);
        assert_eq!(milestones[0].title, "Has date");
        // None entries sorted by title
        assert_eq!(milestones[1].title, "Also no date");
        assert_eq!(milestones[2].title, "No date");
    }

    // ── Status: staleness computation ────────────────────────────

    #[test]
    fn test_stale_pr_detection() {
        let prs = vec![
            PrStatus {
                repo: "test/repo".to_string(),
                number: 1,
                title: "Fresh PR".to_string(),
                draft: false,
                author: "user".to_string(),
                head_ref: "feat/fresh".to_string(),
                milestone: None,
                created_at: "2026-04-14T00:00:00Z".to_string(),
                age_days: 1,
                flags: vec![],
            },
            PrStatus {
                repo: "test/repo".to_string(),
                number: 2,
                title: "Stale PR".to_string(),
                draft: false,
                author: "user".to_string(),
                head_ref: "feat/stale".to_string(),
                milestone: None,
                created_at: "2026-01-01T00:00:00Z".to_string(),
                age_days: 104,
                flags: vec!["stale".to_string()],
            },
        ];

        let attention = compute_attention(&[], &[], &prs, &[]);
        assert_eq!(attention.stale_prs.len(), 1);
        assert_eq!(
            attention.stale_prs[0]
                .get("number")
                .and_then(|n| n.as_u64()),
            Some(2)
        );
    }

    // ── Status: attention section generation ─────────────────────

    #[test]
    fn test_attention_issues_without_milestone() {
        let issues = vec![
            IssueStatus {
                repo: "test/repo".to_string(),
                number: 10,
                title: "Has milestone".to_string(),
                state: "open".to_string(),
                milestone: Some("v1.0".to_string()),
                labels: vec![],
                assignees: vec![],
                created_at: "2026-04-01T00:00:00Z".to_string(),
                age_days: 14,
            },
            IssueStatus {
                repo: "test/repo".to_string(),
                number: 11,
                title: "No milestone".to_string(),
                state: "open".to_string(),
                milestone: None,
                labels: vec![],
                assignees: vec![],
                created_at: "2026-04-01T00:00:00Z".to_string(),
                age_days: 14,
            },
        ];

        let attention = compute_attention(&[], &issues, &[], &[]);
        assert_eq!(attention.issues_without_milestone.len(), 1);
        assert_eq!(
            attention.issues_without_milestone[0]
                .get("number")
                .and_then(|n| n.as_u64()),
            Some(11)
        );
    }

    #[test]
    fn test_attention_milestones_without_due_date() {
        let milestones = vec![
            make_milestone("Dated", Some("2026-06-01")),
            make_milestone("Undated", None),
        ];
        let attention = compute_attention(&milestones, &[], &[], &[]);
        assert_eq!(attention.milestones_without_due_date.len(), 1);
        assert_eq!(
            attention.milestones_without_due_date[0]
                .get("title")
                .and_then(|t| t.as_str()),
            Some("Undated")
        );
    }

    #[test]
    fn test_attention_stale_and_merged_branches() {
        let branches = vec![
            BranchStatus {
                repo: "test/repo".to_string(),
                name: "feat/stale".to_string(),
                owner: "user".to_string(),
                pr_number: None,
                pr_state: None,
                worktree_path: None,
                checkout_path: None,
                commits_ahead: 3,
                last_commit_age_days: 30,
                merged: false,
                flags: vec!["stale".to_string()],
            },
            BranchStatus {
                repo: "test/repo".to_string(),
                name: "feat/merged".to_string(),
                owner: "user".to_string(),
                pr_number: Some(5),
                pr_state: Some("closed".to_string()),
                worktree_path: None,
                checkout_path: None,
                commits_ahead: 0,
                last_commit_age_days: 2,
                merged: true,
                flags: vec!["cleanup-candidate".to_string()],
            },
        ];

        let attention = compute_attention(&[], &[], &[], &branches);
        assert_eq!(attention.stale_branches.len(), 1);
        assert_eq!(
            attention.stale_branches[0]
                .get("name")
                .and_then(|n| n.as_str()),
            Some("feat/stale")
        );
        assert_eq!(attention.merged_branches_to_cleanup.len(), 1);
        assert_eq!(
            attention.merged_branches_to_cleanup[0]
                .get("name")
                .and_then(|n| n.as_str()),
            Some("feat/merged")
        );
    }

    // ── Status: slug detection from repo URL ─────────────────────

    #[test]
    fn test_slug_detection_from_github_url() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let result = detect_by_repo(&pf, "https://github.com/ncrmro/keystone.git");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "exact");
    }

    #[test]
    fn test_slug_detection_from_ssh_url() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let result = detect_by_repo(&pf, "git@github.com:ncrmro/keystone.git");
        assert_eq!(result.slug, Some("keystone".to_string()));
    }

    // ── Status: GraphQL response parsing ─────────────────────────

    #[test]
    fn test_parse_github_milestones_from_json() {
        let data = serde_json::json!({
            "milestones": {
                "nodes": [
                    {
                        "title": "v0.5",
                        "number": 3,
                        "dueOn": "2026-05-01T00:00:00Z",
                        "open": {"totalCount": 4},
                        "closed": {"totalCount": 6}
                    },
                    {
                        "title": "Backlog",
                        "number": 1,
                        "dueOn": null,
                        "open": {"totalCount": 10},
                        "closed": {"totalCount": 0}
                    }
                ]
            }
        });

        let milestones = parse_github_milestones(&data, "ncrmro/keystone");
        assert_eq!(milestones.len(), 2);
        assert_eq!(milestones[0].title, "v0.5");
        assert_eq!(milestones[0].number, 3);
        assert_eq!(
            milestones[0].due_on,
            Some("2026-05-01T00:00:00Z".to_string())
        );
        assert_eq!(milestones[0].open_issues, 4);
        assert_eq!(milestones[0].closed_issues, 6);
        assert_eq!(milestones[0].completion_pct, 60);
        assert!(milestones[0].flags.is_empty());

        assert_eq!(milestones[1].title, "Backlog");
        assert!(milestones[1].due_on.is_none());
        assert!(milestones[1].flags.contains(&"no-due-date".to_string()));
    }

    #[test]
    fn test_parse_github_issues_from_json() {
        let data = serde_json::json!({
            "issues": {
                "nodes": [
                    {
                        "number": 42,
                        "title": "Fix the widget",
                        "createdAt": "2026-04-01T12:00:00Z",
                        "labels": {"nodes": [{"name": "bug"}, {"name": "priority"}]},
                        "assignees": {"nodes": [{"login": "ncrmro"}]},
                        "milestone": {"title": "v0.5"}
                    }
                ]
            }
        });

        let issues = parse_github_issues(&data, "ncrmro/keystone");
        assert_eq!(issues.len(), 1);
        assert_eq!(issues[0].number, 42);
        assert_eq!(issues[0].title, "Fix the widget");
        assert_eq!(issues[0].labels, vec!["bug", "priority"]);
        assert_eq!(issues[0].assignees, vec!["ncrmro"]);
        assert_eq!(issues[0].milestone, Some("v0.5".to_string()));
    }

    #[test]
    fn test_parse_github_prs_from_json() {
        let data = serde_json::json!({
            "pullRequests": {
                "nodes": [
                    {
                        "number": 100,
                        "title": "Add feature X",
                        "isDraft": true,
                        "createdAt": "2026-04-10T08:00:00Z",
                        "author": {"login": "ncrmro"},
                        "headRefName": "feat/feature-x",
                        "milestone": null
                    }
                ]
            }
        });

        let prs = parse_github_prs(&data, "ncrmro/keystone");
        assert_eq!(prs.len(), 1);
        assert_eq!(prs[0].number, 100);
        assert_eq!(prs[0].title, "Add feature X");
        assert!(prs[0].draft);
        assert_eq!(prs[0].author, "ncrmro");
        assert_eq!(prs[0].head_ref, "feat/feature-x");
        assert!(prs[0].milestone.is_none());
        assert!(prs[0].flags.contains(&"draft".to_string()));
    }
}
