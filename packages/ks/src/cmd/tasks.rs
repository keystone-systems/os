//! `ks task` — unified task management for humans and agents.
//!
//! Manages TASKS.yaml: add, complete, list, prune, and AI-powered ingest
//! and prioritization. Tasks are created from `ks notifications` sources
//! or manually. Prioritization proposals include rationale and can be
//! reviewed before acceptance.

use std::io::Read;
use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};

// ── CLI definition ────────────────────────────────────────────────────

#[derive(Args)]
pub struct TaskArgs {
    #[command(subcommand)]
    pub command: Option<TaskCommand>,

    /// Output as JSON instead of human-readable table.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand)]
pub enum TaskCommand {
    /// Add a new task.
    Add {
        /// Task description.
        description: String,

        /// Task name (kebab-case). Auto-generated from description if omitted.
        #[arg(long)]
        name: Option<String>,

        /// Source type (email, github-issue, github-pr, manual).
        #[arg(long, default_value = "manual")]
        source: String,

        /// Source reference for deduplication.
        #[arg(long)]
        source_ref: Option<String>,

        /// Associated project.
        #[arg(long)]
        project: Option<String>,
    },

    /// Mark a task as in-progress.
    Start {
        /// Task name to start.
        name: String,
    },

    /// Mark a task as completed.
    Done {
        /// Task name to complete.
        name: String,
    },

    /// Mark a task as blocked.
    Block {
        /// Task name to block.
        name: String,

        /// Reason for blocking.
        #[arg(long)]
        reason: Option<String>,
    },

    /// Ingest notifications into tasks. Reads JSON from stdin or file.
    /// Outputs tasks to add as JSON (for AI review) or applies directly.
    Ingest {
        /// Path to notifications JSON (from `ks notifications fetch`). Reads stdin if omitted.
        #[arg(long)]
        file: Option<PathBuf>,

        /// Apply tasks directly without AI review (used by task-loop automation).
        #[arg(long)]
        apply: bool,
    },

    /// Generate a prioritization proposal for pending tasks.
    /// Outputs JSON with rationale for each task ranking.
    Prioritize,

    /// Show or accept a prioritization proposal.
    Proposal {
        /// Accept the current proposal and apply the new ordering.
        #[arg(long)]
        accept: bool,
    },

    /// Remove completed tasks older than a threshold.
    Prune {
        /// Remove all completed tasks (default: only those older than 30 days).
        #[arg(long)]
        all: bool,
    },
}

// ── Data model ────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TaskFile {
    pub tasks: Vec<Task>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub name: String,
    pub description: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_ref: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workflow: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub needs: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub blocked_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
}

/// A prioritization proposal from the AI, with rationale per task.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PrioritizationProposal {
    pub proposed_at: String,
    pub items: Vec<ProposalItem>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProposalItem {
    pub rank: u32,
    pub name: String,
    pub rationale: String,
}

/// Input format for `ks tasks ingest --apply`: tasks the AI decided to create.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct IngestResult {
    pub tasks: Vec<IngestTask>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct IngestTask {
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub source_ref: Option<String>,
    #[serde(default)]
    pub project: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
}

// ── Paths ─────────────────────────────────────────────────────────────

fn tasks_file_path() -> PathBuf {
    if let Ok(p) = std::env::var("KS_TASKS_FILE") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let home_path = PathBuf::from(&home).join("TASKS.yaml");
    if home_path.exists() {
        return home_path;
    }
    let cwd_path = PathBuf::from("TASKS.yaml");
    if cwd_path.exists() {
        return cwd_path;
    }
    home_path
}

fn proposal_path() -> PathBuf {
    if let Ok(p) = std::env::var("KS_PROPOSAL_FILE") {
        return PathBuf::from(p);
    }
    let state_dir = std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{home}/.local/state")
    });
    PathBuf::from(state_dir).join("ks/tasks/proposal.json")
}

// ── Core operations (testable, path-parameterized) ────────────────────

pub fn load_tasks_from(path: &PathBuf) -> Result<TaskFile> {
    if !path.exists() {
        return Ok(TaskFile { tasks: vec![] });
    }
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let tasks: TaskFile = serde_yaml::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(tasks)
}

pub fn save_tasks_to(task_file: &TaskFile, path: &PathBuf) -> Result<()> {
    let content = serde_yaml::to_string(task_file)?;
    let output = format!("---\n{content}");
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    std::fs::write(path, output).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Add a task, deduplicating by source_ref and name. Returns true if added.
pub fn add_task(task_file: &mut TaskFile, task: Task) -> bool {
    if let Some(ref sref) = task.source_ref {
        if task_file
            .tasks
            .iter()
            .any(|t| t.source_ref.as_deref() == Some(sref))
        {
            return false;
        }
    }
    if task_file.tasks.iter().any(|t| t.name == task.name) {
        return false;
    }
    task_file.tasks.push(task);
    true
}

/// Mark a task as in-progress. Returns true if found.
pub fn start_task(task_file: &mut TaskFile, name: &str) -> bool {
    if let Some(t) = task_file.tasks.iter_mut().find(|t| t.name == name) {
        t.status = "in_progress".to_string();
        t.started_at = Some(iso_now());
        true
    } else {
        false
    }
}

/// Mark a task as completed. Returns true if found.
pub fn complete_task(task_file: &mut TaskFile, name: &str) -> bool {
    if let Some(t) = task_file.tasks.iter_mut().find(|t| t.name == name) {
        t.status = "completed".to_string();
        t.completed_at = Some(iso_now());
        true
    } else {
        false
    }
}

/// Mark a task as blocked. Returns true if found.
pub fn block_task(task_file: &mut TaskFile, name: &str, reason: Option<&str>) -> bool {
    if let Some(t) = task_file.tasks.iter_mut().find(|t| t.name == name) {
        t.status = "blocked".to_string();
        t.blocked_reason = reason.map(String::from);
        true
    } else {
        false
    }
}

/// Prune completed tasks. Returns count removed.
pub fn prune_tasks(task_file: &mut TaskFile, all: bool) -> usize {
    let before = task_file.tasks.len();
    if all {
        task_file.tasks.retain(|t| t.status != "completed");
    } else {
        let cutoff = crate::time::chrono_days_ago(30);
        task_file.tasks.retain(|t| {
            if t.status != "completed" {
                return true;
            }
            match &t.completed_at {
                Some(ts) => ts.as_str() >= cutoff.as_str(),
                None => true,
            }
        });
    }
    before - task_file.tasks.len()
}

/// Apply a prioritization proposal to reorder pending tasks.
pub fn apply_proposal(task_file: &mut TaskFile, proposal: &PrioritizationProposal) {
    let mut all_tasks: Vec<Task> = task_file.tasks.drain(..).collect();
    let mut pending: Vec<Task> = Vec::new();
    let mut others: Vec<Task> = Vec::new();

    for task in all_tasks.drain(..) {
        if task.status == "pending" {
            pending.push(task);
        } else {
            others.push(task);
        }
    }

    // Reorder pending by proposal rank
    let mut reordered: Vec<Task> = Vec::new();
    for item in &proposal.items {
        if let Some(idx) = pending.iter().position(|t| t.name == item.name) {
            reordered.push(pending.remove(idx));
        }
    }
    reordered.append(&mut pending); // unmentioned pending tasks at the end

    // Reconstruct: in_progress, pending (reordered), blocked, completed
    task_file.tasks = others
        .iter()
        .filter(|t| t.status == "in_progress")
        .cloned()
        .chain(reordered)
        .chain(others.iter().filter(|t| t.status == "blocked").cloned())
        .chain(others.iter().filter(|t| t.status == "completed").cloned())
        .collect();
}

/// Apply ingest results: add tasks from AI output, deduplicating.
/// Returns (added_count, skipped_count).
pub fn apply_ingest(task_file: &mut TaskFile, ingest: &IngestResult) -> (usize, usize) {
    let mut added = 0;
    let mut skipped = 0;

    for it in &ingest.tasks {
        let task = Task {
            name: it.name.clone(),
            description: it.description.clone(),
            status: "pending".to_string(),
            project: it.project.clone(),
            source: it.source.clone(),
            source_ref: it.source_ref.clone(),
            model: it.model.clone(),
            workflow: None,
            needs: None,
            blocked_reason: None,
            created_at: Some(iso_now()),
            started_at: None,
            completed_at: None,
        };
        if add_task(task_file, task) {
            added += 1;
        } else {
            skipped += 1;
        }
    }

    (added, skipped)
}

// ── Entry point ───────────────────────────────────────────────────────

pub async fn execute(args: &TaskArgs) -> Result<()> {
    match &args.command {
        None => execute_list(args.json),
        Some(TaskCommand::Add {
            description,
            name,
            source,
            source_ref,
            project,
        }) => execute_add(
            description,
            name.as_deref(),
            source,
            source_ref.as_deref(),
            project.as_deref(),
        ),
        Some(TaskCommand::Start { name }) => execute_start(name),
        Some(TaskCommand::Done { name }) => execute_done(name),
        Some(TaskCommand::Block { name, reason }) => execute_block(name, reason.as_deref()),
        Some(TaskCommand::Ingest { file, apply }) => execute_ingest(file.as_ref(), *apply).await,
        Some(TaskCommand::Prioritize) => execute_prioritize().await,
        Some(TaskCommand::Proposal { accept }) => execute_proposal(*accept),
        Some(TaskCommand::Prune { all }) => execute_prune(*all),
    }
}

// ── List ──────────────────────────────────────────────────────────────

fn execute_list(json: bool) -> Result<()> {
    let path = tasks_file_path();
    let task_file = load_tasks_from(&path)?;

    if json {
        println!("{}", serde_json::to_string_pretty(&task_file.tasks)?);
        return Ok(());
    }

    if task_file.tasks.is_empty() {
        println!("No tasks.");
        return Ok(());
    }

    let pending: Vec<_> = task_file
        .tasks
        .iter()
        .filter(|t| t.status == "pending")
        .collect();
    let in_progress: Vec<_> = task_file
        .tasks
        .iter()
        .filter(|t| t.status == "in_progress")
        .collect();
    let blocked: Vec<_> = task_file
        .tasks
        .iter()
        .filter(|t| t.status == "blocked")
        .collect();
    let errored: Vec<_> = task_file
        .tasks
        .iter()
        .filter(|t| t.status == "error")
        .collect();
    let completed: Vec<_> = task_file
        .tasks
        .iter()
        .filter(|t| t.status == "completed")
        .collect();

    if !in_progress.is_empty() {
        println!("In Progress ({}):", in_progress.len());
        for t in &in_progress {
            print_task(t);
        }
        println!();
    }

    if !pending.is_empty() {
        println!("Pending ({}):", pending.len());
        for t in &pending {
            print_task(t);
        }
        println!();
    }

    if !blocked.is_empty() {
        println!("Blocked ({}):", blocked.len());
        for t in &blocked {
            let reason = t.blocked_reason.as_deref().unwrap_or("");
            println!("  {} — {}", t.name, t.description);
            if !reason.is_empty() {
                println!("    reason: {reason}");
            }
        }
        println!();
    }

    if !errored.is_empty() {
        println!("Errored ({}):", errored.len());
        for t in &errored {
            print_task(t);
        }
        println!();
    }

    println!("Completed: {}", completed.len());
    Ok(())
}

fn print_task(task: &Task) {
    let project = task.project.as_deref().unwrap_or("");
    let source = task.source.as_deref().unwrap_or("");
    let prefix = if !project.is_empty() {
        format!("[{project}] ")
    } else if !source.is_empty() {
        format!("({source}) ")
    } else {
        String::new()
    };
    println!("  {} {}{}", task.name, prefix, task.description);
}

// ── Add ───────────────────────────────────────────────────────────────

fn execute_add(
    description: &str,
    name: Option<&str>,
    source: &str,
    source_ref: Option<&str>,
    project: Option<&str>,
) -> Result<()> {
    let path = tasks_file_path();
    let mut task_file = load_tasks_from(&path)?;

    let task_name = name
        .map(String::from)
        .unwrap_or_else(|| slugify(description));
    let task = Task {
        name: task_name.clone(),
        description: description.to_string(),
        status: "pending".to_string(),
        project: project.map(String::from),
        source: Some(source.to_string()),
        source_ref: source_ref.map(String::from),
        model: None,
        workflow: None,
        needs: None,
        blocked_reason: None,
        created_at: Some(iso_now()),
        started_at: None,
        completed_at: None,
    };

    if add_task(&mut task_file, task) {
        save_tasks_to(&task_file, &path)?;
        println!("Added: {task_name}");
    } else {
        eprintln!("Task '{task_name}' already exists, skipping.");
    }
    Ok(())
}

// ── Start / Done / Block ──────────────────────────────────────────────

fn execute_start(name: &str) -> Result<()> {
    let path = tasks_file_path();
    let mut task_file = load_tasks_from(&path)?;
    if start_task(&mut task_file, name) {
        save_tasks_to(&task_file, &path)?;
        println!("Started: {name}");
    } else {
        eprintln!("Task '{name}' not found.");
    }
    Ok(())
}

fn execute_done(name: &str) -> Result<()> {
    let path = tasks_file_path();
    let mut task_file = load_tasks_from(&path)?;
    if complete_task(&mut task_file, name) {
        save_tasks_to(&task_file, &path)?;
        println!("Completed: {name}");
    } else {
        eprintln!("Task '{name}' not found.");
    }
    Ok(())
}

fn execute_block(name: &str, reason: Option<&str>) -> Result<()> {
    let path = tasks_file_path();
    let mut task_file = load_tasks_from(&path)?;
    if block_task(&mut task_file, name, reason) {
        save_tasks_to(&task_file, &path)?;
        println!("Blocked: {name}");
    } else {
        eprintln!("Task '{name}' not found.");
    }
    Ok(())
}

// ── Ingest ────────────────────────────────────────────────────────────

/// Ingest notifications into tasks.
///
/// Without --apply: reads notifications JSON, outputs a prompt + context
/// for an AI to decide which notifications become tasks. The AI should
/// return an IngestResult JSON.
///
/// With --apply: reads IngestResult JSON from stdin and adds tasks.
async fn execute_ingest(file: Option<&PathBuf>, apply: bool) -> Result<()> {
    let path = tasks_file_path();

    if apply {
        // Read IngestResult JSON from stdin
        let mut buf = String::new();
        std::io::stdin().read_to_string(&mut buf)?;
        let ingest: IngestResult =
            serde_json::from_str(&buf).context("failed to parse ingest JSON from stdin")?;

        let mut task_file = load_tasks_from(&path)?;
        let (added, skipped) = apply_ingest(&mut task_file, &ingest);
        save_tasks_to(&task_file, &path)?;

        let result = serde_json::json!({
            "added": added,
            "skipped": skipped,
            "total": task_file.tasks.len(),
        });
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    // Read notifications JSON
    let notifications_json = match file {
        Some(f) => {
            std::fs::read_to_string(f).with_context(|| format!("failed to read {}", f.display()))?
        }
        None => {
            let mut buf = String::new();
            std::io::stdin().read_to_string(&mut buf)?;
            buf
        }
    };

    // Load current tasks for context
    let task_file = load_tasks_from(&path)?;
    let existing_refs: Vec<&str> = task_file
        .tasks
        .iter()
        .filter_map(|t| t.source_ref.as_deref())
        .collect();

    // Output structured context for AI consumption
    let output = serde_json::json!({
        "action": "ingest",
        "instructions": "Review these notifications and decide which are actionable tasks. \
            Return JSON matching the IngestResult schema: {\"tasks\": [{\"name\": \"kebab-case-name\", \
            \"description\": \"what to do\", \"source\": \"email|github|forgejo\", \
            \"source_ref\": \"unique-ref\", \"project\": \"optional-project\"}]}. \
            Skip notifications that already have a matching source_ref in existing_refs. \
            Skip automated notifications, newsletters, and CI status. \
            Any message containing 'ping' MUST create a reply-with-pong task.",
        "notifications": serde_json::from_str::<serde_json::Value>(&notifications_json)
            .unwrap_or(serde_json::json!([])),
        "existing_refs": existing_refs,
        "response_schema": {
            "type": "object",
            "properties": {
                "tasks": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["name", "description"],
                        "properties": {
                            "name": {"type": "string"},
                            "description": {"type": "string"},
                            "source": {"type": "string"},
                            "source_ref": {"type": "string"},
                            "project": {"type": "string"},
                            "model": {"type": "string"}
                        }
                    }
                }
            }
        }
    });

    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}

// ── Prioritize ────────────────────────────────────────────────────────

/// Output pending tasks as a structured prompt for AI prioritization.
/// The AI should return a PrioritizationProposal JSON.
async fn execute_prioritize() -> Result<()> {
    let path = tasks_file_path();
    let task_file = load_tasks_from(&path)?;

    let pending: Vec<&Task> = task_file
        .tasks
        .iter()
        .filter(|t| t.status == "pending")
        .collect();

    if pending.is_empty() {
        println!("No pending tasks to prioritize.");
        return Ok(());
    }

    let output = serde_json::json!({
        "action": "prioritize",
        "instructions": "Rank these pending tasks by priority. Consider urgency, dependencies, \
            project importance, and source type (PR reviews and email replies are typically \
            time-sensitive). Return JSON matching the PrioritizationProposal schema. \
            Include a short rationale (1-2 sentences) explaining why each task is ranked where it is.",
        "pending_tasks": pending,
        "response_schema": {
            "type": "object",
            "required": ["proposed_at", "items"],
            "properties": {
                "proposed_at": {"type": "string", "description": "ISO 8601 timestamp"},
                "items": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["rank", "name", "rationale"],
                        "properties": {
                            "rank": {"type": "integer"},
                            "name": {"type": "string"},
                            "rationale": {"type": "string"}
                        }
                    }
                }
            }
        }
    });

    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}

// ── Proposal ──────────────────────────────────────────────────────────

fn execute_proposal(accept: bool) -> Result<()> {
    let path = proposal_path();

    if accept {
        if !path.exists() {
            eprintln!("No proposal to accept. Run prioritization first.");
            return Ok(());
        }

        let content = std::fs::read_to_string(&path)?;
        let proposal: PrioritizationProposal = serde_json::from_str(&content)?;

        let tasks_path = tasks_file_path();
        let mut task_file = load_tasks_from(&tasks_path)?;
        apply_proposal(&mut task_file, &proposal);
        save_tasks_to(&task_file, &tasks_path)?;

        std::fs::remove_file(&path).ok();
        println!(
            "Accepted prioritization. {} pending tasks reordered.",
            proposal.items.len()
        );
        return Ok(());
    }

    if !path.exists() {
        println!("No pending proposal.");
        return Ok(());
    }

    let content = std::fs::read_to_string(&path)?;
    let proposal: PrioritizationProposal = serde_json::from_str(&content)?;

    println!("Prioritization proposal ({})\n", proposal.proposed_at);
    for item in &proposal.items {
        println!("  {}. {} — {}", item.rank, item.name, item.rationale);
    }
    println!("\nAccept with: ks tasks proposal --accept");
    Ok(())
}

// ── Prune ─────────────────────────────────────────────────────────────

fn execute_prune(all: bool) -> Result<()> {
    let path = tasks_file_path();
    let mut task_file = load_tasks_from(&path)?;
    let removed = prune_tasks(&mut task_file, all);
    save_tasks_to(&task_file, &path)?;
    println!(
        "Pruned {removed} completed tasks ({} remaining).",
        task_file.tasks.len()
    );
    Ok(())
}

// ── Helpers ───────────────────────────────────────────────────────────

pub fn iso_now() -> String {
    crate::time::iso_now()
}

pub fn slugify(text: &str) -> String {
    text.to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-")
        .chars()
        .take(60)
        .collect()
}

// ── Tests ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    fn make_task(name: &str, status: &str) -> Task {
        Task {
            name: name.to_string(),
            description: format!("Test task: {name}"),
            status: status.to_string(),
            project: None,
            source: None,
            source_ref: None,
            model: None,
            workflow: None,
            needs: None,
            blocked_reason: None,
            created_at: None,
            started_at: None,
            completed_at: None,
        }
    }

    fn make_task_with_ref(name: &str, source_ref: &str) -> Task {
        let mut t = make_task(name, "pending");
        t.source_ref = Some(source_ref.to_string());
        t
    }

    // ── slugify ───────────────────────────────────────────────────

    #[test]
    fn test_slugify_basic() {
        assert_eq!(slugify("Review PR #355"), "review-pr-355");
    }

    #[test]
    fn test_slugify_special_chars() {
        assert_eq!(slugify("Fix login (staging)!"), "fix-login-staging");
    }

    #[test]
    fn test_slugify_truncation() {
        let long = "a".repeat(100);
        assert_eq!(slugify(&long).len(), 60);
    }

    // ── YAML round-trip ───────────────────────────────────────────

    #[test]
    fn test_yaml_round_trip() {
        let task_file = TaskFile {
            tasks: vec![
                make_task("task-one", "pending"),
                make_task("task-two", "completed"),
            ],
        };

        let tmp = NamedTempFile::new().unwrap();
        save_tasks_to(&task_file, &tmp.path().to_path_buf()).unwrap();

        let loaded = load_tasks_from(&tmp.path().to_path_buf()).unwrap();
        assert_eq!(loaded.tasks.len(), 2);
        assert_eq!(loaded.tasks[0].name, "task-one");
        assert_eq!(loaded.tasks[1].status, "completed");
    }

    #[test]
    fn test_load_missing_file() {
        let path = PathBuf::from("/tmp/nonexistent-ks-test-tasks.yaml");
        let result = load_tasks_from(&path).unwrap();
        assert!(result.tasks.is_empty());
    }

    // ── add_task deduplication ─────────────────────────────────────

    #[test]
    fn test_add_task_basic() {
        let mut tf = TaskFile { tasks: vec![] };
        let task = make_task("new-task", "pending");
        assert!(add_task(&mut tf, task));
        assert_eq!(tf.tasks.len(), 1);
    }

    #[test]
    fn test_add_task_dedup_by_name() {
        let mut tf = TaskFile {
            tasks: vec![make_task("existing", "pending")],
        };
        let dup = make_task("existing", "pending");
        assert!(!add_task(&mut tf, dup));
        assert_eq!(tf.tasks.len(), 1);
    }

    #[test]
    fn test_add_task_dedup_by_source_ref() {
        let mut tf = TaskFile {
            tasks: vec![make_task_with_ref("old-task", "email-42-user@host")],
        };
        let dup = make_task_with_ref("new-name", "email-42-user@host");
        assert!(!add_task(&mut tf, dup));
        assert_eq!(tf.tasks.len(), 1);
    }

    #[test]
    fn test_add_task_different_ref_ok() {
        let mut tf = TaskFile {
            tasks: vec![make_task_with_ref("task-a", "ref-a")],
        };
        let new = make_task_with_ref("task-b", "ref-b");
        assert!(add_task(&mut tf, new));
        assert_eq!(tf.tasks.len(), 2);
    }

    // ── complete / block ──────────────────────────────────────────

    #[test]
    fn test_start_task() {
        let mut tf = TaskFile {
            tasks: vec![make_task("my-task", "pending")],
        };
        assert!(start_task(&mut tf, "my-task"));
        assert_eq!(tf.tasks[0].status, "in_progress");
        assert!(tf.tasks[0].started_at.is_some());
    }

    #[test]
    fn test_start_task_not_found() {
        let mut tf = TaskFile { tasks: vec![] };
        assert!(!start_task(&mut tf, "missing"));
    }

    #[test]
    fn test_complete_task() {
        let mut tf = TaskFile {
            tasks: vec![make_task("fix-bug", "pending")],
        };
        assert!(complete_task(&mut tf, "fix-bug"));
        assert_eq!(tf.tasks[0].status, "completed");
        assert!(tf.tasks[0].completed_at.is_some());
    }

    #[test]
    fn test_complete_task_not_found() {
        let mut tf = TaskFile { tasks: vec![] };
        assert!(!complete_task(&mut tf, "missing"));
    }

    #[test]
    fn test_block_task() {
        let mut tf = TaskFile {
            tasks: vec![make_task("blocked-task", "pending")],
        };
        assert!(block_task(
            &mut tf,
            "blocked-task",
            Some("waiting for deploy")
        ));
        assert_eq!(tf.tasks[0].status, "blocked");
        assert_eq!(
            tf.tasks[0].blocked_reason.as_deref(),
            Some("waiting for deploy")
        );
    }

    // ── prune ─────────────────────────────────────────────────────

    #[test]
    fn test_prune_all() {
        let mut tf = TaskFile {
            tasks: vec![
                make_task("pending-task", "pending"),
                make_task("done-task", "completed"),
                make_task("done-old", "completed"),
            ],
        };
        let removed = prune_tasks(&mut tf, true);
        assert_eq!(removed, 2);
        assert_eq!(tf.tasks.len(), 1);
        assert_eq!(tf.tasks[0].name, "pending-task");
    }

    #[test]
    fn test_prune_preserves_recent() {
        let mut t = make_task("recent", "completed");
        t.completed_at = Some(iso_now()); // just now
        let mut tf = TaskFile { tasks: vec![t] };
        let removed = prune_tasks(&mut tf, false);
        assert_eq!(removed, 0);
        assert_eq!(tf.tasks.len(), 1);
    }

    #[test]
    fn test_prune_removes_old() {
        let mut t = make_task("old", "completed");
        t.completed_at = Some("2020-01-01T00:00:00Z".to_string());
        let mut tf = TaskFile { tasks: vec![t] };
        let removed = prune_tasks(&mut tf, false);
        assert_eq!(removed, 1);
    }

    // ── apply_proposal ────────────────────────────────────────────

    #[test]
    fn test_apply_proposal_reorders() {
        let mut tf = TaskFile {
            tasks: vec![
                make_task("low-pri", "pending"),
                make_task("high-pri", "pending"),
                make_task("done", "completed"),
            ],
        };

        let proposal = PrioritizationProposal {
            proposed_at: "2026-04-13T00:00:00Z".to_string(),
            items: vec![
                ProposalItem {
                    rank: 1,
                    name: "high-pri".to_string(),
                    rationale: "Urgent".to_string(),
                },
                ProposalItem {
                    rank: 2,
                    name: "low-pri".to_string(),
                    rationale: "Can wait".to_string(),
                },
            ],
        };

        apply_proposal(&mut tf, &proposal);

        assert_eq!(tf.tasks[0].name, "high-pri"); // reordered first
        assert_eq!(tf.tasks[1].name, "low-pri");
        assert_eq!(tf.tasks[2].name, "done"); // completed at end
    }

    #[test]
    fn test_apply_proposal_preserves_in_progress() {
        let mut tf = TaskFile {
            tasks: vec![
                make_task("wip", "in_progress"),
                make_task("pending-a", "pending"),
                make_task("pending-b", "pending"),
            ],
        };

        let proposal = PrioritizationProposal {
            proposed_at: "2026-04-13T00:00:00Z".to_string(),
            items: vec![
                ProposalItem {
                    rank: 1,
                    name: "pending-b".to_string(),
                    rationale: "Higher priority".to_string(),
                },
                ProposalItem {
                    rank: 2,
                    name: "pending-a".to_string(),
                    rationale: "Lower priority".to_string(),
                },
            ],
        };

        apply_proposal(&mut tf, &proposal);

        assert_eq!(tf.tasks[0].name, "wip"); // in_progress stays first
        assert_eq!(tf.tasks[1].name, "pending-b");
        assert_eq!(tf.tasks[2].name, "pending-a");
    }

    // ── apply_ingest ──────────────────────────────────────────────

    #[test]
    fn test_apply_ingest_adds_new() {
        let mut tf = TaskFile { tasks: vec![] };
        let ingest = IngestResult {
            tasks: vec![IngestTask {
                name: "reply-to-ping".to_string(),
                description: "Reply with pong".to_string(),
                source: Some("email".to_string()),
                source_ref: Some("email-99-user@host".to_string()),
                project: None,
                model: Some("haiku".to_string()),
            }],
        };

        let (added, skipped) = apply_ingest(&mut tf, &ingest);
        assert_eq!(added, 1);
        assert_eq!(skipped, 0);
        assert_eq!(tf.tasks[0].name, "reply-to-ping");
        assert_eq!(tf.tasks[0].model, Some("haiku".to_string()));
    }

    #[test]
    fn test_apply_ingest_dedup() {
        let mut tf = TaskFile {
            tasks: vec![make_task_with_ref("existing", "email-42-user@host")],
        };
        let ingest = IngestResult {
            tasks: vec![
                IngestTask {
                    name: "new-task-same-ref".to_string(),
                    description: "Duplicate ref".to_string(),
                    source: Some("email".to_string()),
                    source_ref: Some("email-42-user@host".to_string()),
                    project: None,
                    model: None,
                },
                IngestTask {
                    name: "genuinely-new".to_string(),
                    description: "New task".to_string(),
                    source: Some("github".to_string()),
                    source_ref: Some("https://github.com/o/r/issues/1".to_string()),
                    project: None,
                    model: None,
                },
            ],
        };

        let (added, skipped) = apply_ingest(&mut tf, &ingest);
        assert_eq!(added, 1);
        assert_eq!(skipped, 1);
        assert_eq!(tf.tasks.len(), 2);
    }

    // ── IngestResult JSON parsing ─────────────────────────────────

    #[test]
    fn test_ingest_result_parse() {
        let json = r#"{
            "tasks": [
                {"name": "fix-bug", "description": "Fix the bug", "source": "github", "source_ref": "http://example.com/1"},
                {"name": "reply-email", "description": "Reply to email"}
            ]
        }"#;

        let result: IngestResult = serde_json::from_str(json).unwrap();
        assert_eq!(result.tasks.len(), 2);
        assert_eq!(
            result.tasks[0].source_ref,
            Some("http://example.com/1".to_string())
        );
        assert_eq!(result.tasks[1].source, None);
    }

    // ── PrioritizationProposal JSON parsing ───────────────────────

    #[test]
    fn test_proposal_parse() {
        let json = r#"{
            "proposed_at": "2026-04-13T12:00:00Z",
            "items": [
                {"rank": 1, "name": "urgent-task", "rationale": "Production is down"},
                {"rank": 2, "name": "review-pr", "rationale": "Teammate waiting on review"}
            ]
        }"#;

        let proposal: PrioritizationProposal = serde_json::from_str(json).unwrap();
        assert_eq!(proposal.items.len(), 2);
        assert_eq!(proposal.items[0].rationale, "Production is down");
    }

    // Time tests moved to crate::time::tests
}
