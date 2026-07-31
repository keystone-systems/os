//! `ks agent loop` — autonomous task loop replacing task-loop.sh.
//!
//! Runs fetch → ingest → prioritize → execute stages in sequence.
//! Uses flock to prevent concurrent runs and checks a pause file
//! before proceeding. AI tools (claude, gemini, codex) are invoked
//! as subprocesses.

use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use anyhow::{Context, Result};
use clap::Args;
use serde::{Deserialize, Serialize};

use crate::cmd::notifications;
use crate::cmd::tasks;

// ── CLI definition ────────────────────────────────────────────────────

#[derive(Args)]
pub struct AgentLoopArgs {
    /// Maximum number of tasks to execute per run.
    #[arg(long, default_value = "3")]
    pub max_tasks: u32,

    /// Run fetch/ingest/prioritize but skip task execution.
    #[arg(long)]
    pub dry_run: bool,
}

// ── Configuration (from environment) ──────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct StageConfig {
    #[serde(default)]
    profile: Option<String>,
    #[serde(default)]
    provider: Option<String>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    fallback_model: Option<String>,
    #[serde(default)]
    effort: Option<String>,
}

/// Profile entry: per-provider settings within a named profile.
type ProfileCatalog =
    std::collections::HashMap<String, std::collections::HashMap<String, StageConfig>>;

/// Resolved runtime configuration for a single AI invocation.
#[derive(Debug, Clone)]
struct ResolvedRuntime {
    provider: String,
    profile: String,
    model: String,
    fallback_model: String,
    effort: String,
}

// ── Paths ─────────────────────────────────────────────────────────────

fn state_dir() -> PathBuf {
    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
            PathBuf::from(home).join(".local/state")
        });
    base.join("ks/agent-loop")
}

fn lock_path() -> PathBuf {
    state_dir().join("agent-loop.lock")
}

fn pause_path() -> PathBuf {
    state_dir().join("paused")
}

fn task_logs_dir() -> PathBuf {
    state_dir().join("logs/tasks")
}

fn tasks_file_path() -> PathBuf {
    if let Ok(p) = std::env::var("KS_TASKS_FILE") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join("TASKS.yaml")
}

// ── Environment config loading ────────────────────────────────────────

fn load_stage_config(env_var: &str) -> StageConfig {
    std::env::var(env_var)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn load_profiles() -> ProfileCatalog {
    std::env::var("KS_AGENT_PROFILES_JSON")
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn agent_name() -> String {
    std::env::var("KS_AGENT_NAME").unwrap_or_else(|_| "unknown".to_string())
}

// ── Runtime resolution ────────────────────────────────────────────────

/// Pick the first non-empty value from a list of Option<&str>.
fn first_non_empty<'a>(values: &[Option<&'a str>]) -> &'a str {
    for s in values.iter().flatten() {
        if !s.is_empty() {
            return s;
        }
    }
    ""
}

fn stage_builtin_profile(stage: &str) -> &'static str {
    match stage {
        "ingest" | "prioritize" => "fast",
        "execute" => "medium",
        _ => "",
    }
}

fn resolve_runtime(
    stage: &str,
    task_overrides: &StageConfig,
    defaults: &StageConfig,
    profiles: &ProfileCatalog,
) -> ResolvedRuntime {
    let stage_cfg = match stage {
        "ingest" => load_stage_config("KS_AGENT_INGEST_JSON"),
        "prioritize" => load_stage_config("KS_AGENT_PRIORITIZE_JSON"),
        "execute" => load_stage_config("KS_AGENT_EXECUTE_JSON"),
        _ => StageConfig::default(),
    };
    let builtin_profile = stage_builtin_profile(stage);

    let provider = first_non_empty(&[
        task_overrides.provider.as_deref(),
        stage_cfg.provider.as_deref(),
        defaults.provider.as_deref(),
        Some("claude"),
    ])
    .to_string();

    let profile = first_non_empty(&[
        task_overrides.profile.as_deref(),
        stage_cfg.profile.as_deref(),
        defaults.profile.as_deref(),
        Some(builtin_profile),
    ])
    .to_string();

    // Look up profile config for the resolved provider
    let profile_cfg = profiles
        .get(&profile)
        .and_then(|p| p.get(&provider))
        .cloned()
        .unwrap_or_default();

    let model = first_non_empty(&[
        task_overrides.model.as_deref(),
        stage_cfg.model.as_deref(),
        defaults.model.as_deref(),
        profile_cfg.model.as_deref(),
    ])
    .to_string();

    let fallback_model = first_non_empty(&[
        task_overrides.fallback_model.as_deref(),
        stage_cfg.fallback_model.as_deref(),
        defaults.fallback_model.as_deref(),
        profile_cfg.fallback_model.as_deref(),
    ])
    .to_string();

    let effort = first_non_empty(&[
        task_overrides.effort.as_deref(),
        stage_cfg.effort.as_deref(),
        defaults.effort.as_deref(),
        profile_cfg.effort.as_deref(),
    ])
    .to_string();

    ResolvedRuntime {
        provider,
        profile,
        model,
        fallback_model,
        effort,
    }
}

// ── Provider invocation ───────────────────────────────────────────────

/// Build the command argv for the given provider and prompt.
fn build_provider_command(runtime: &ResolvedRuntime, prompt: &str) -> Vec<String> {
    match runtime.provider.as_str() {
        "claude" => {
            let mut cmd = vec![
                "claude".to_string(),
                "--print".to_string(),
                "--output-format".to_string(),
                "json".to_string(),
                "--dangerously-skip-permissions".to_string(),
            ];
            if !runtime.model.is_empty() {
                cmd.push("--model".to_string());
                cmd.push(runtime.model.clone());
            }
            if !runtime.fallback_model.is_empty() {
                cmd.push("--fallback-model".to_string());
                cmd.push(runtime.fallback_model.clone());
            }
            if !runtime.effort.is_empty() {
                cmd.push("--effort".to_string());
                cmd.push(runtime.effort.clone());
            }
            cmd.push(prompt.to_string());
            cmd
        }
        "gemini" => {
            let mut cmd = vec![
                "gemini".to_string(),
                "--prompt".to_string(),
                prompt.to_string(),
                "--yolo".to_string(),
            ];
            if !runtime.model.is_empty() {
                cmd.push("-m".to_string());
                cmd.push(runtime.model.clone());
            }
            cmd
        }
        "codex" => {
            let mut cmd = vec![
                "codex".to_string(),
                "exec".to_string(),
                "--full-auto".to_string(),
            ];
            if !runtime.model.is_empty() {
                cmd.push("-m".to_string());
                cmd.push(runtime.model.clone());
            }
            cmd.push(prompt.to_string());
            cmd
        }
        other => {
            eprintln!("ERROR: unsupported provider '{other}'");
            vec![]
        }
    }
}

/// Run a provider command, streaming output to stderr (journald) and an optional log file.
/// Returns the process exit code (0 on success).
async fn run_provider(runtime: &ResolvedRuntime, prompt: &str, log_path: Option<&PathBuf>) -> i32 {
    use tokio::io::{AsyncBufReadExt, BufReader};

    let argv = build_provider_command(runtime, prompt);
    if argv.is_empty() {
        return 1;
    }

    eprintln!(
        "  provider={} profile={} model={} fallback={} effort={}",
        runtime.provider,
        if runtime.profile.is_empty() {
            "none"
        } else {
            &runtime.profile
        },
        if runtime.model.is_empty() {
            "provider-default"
        } else {
            &runtime.model
        },
        if runtime.fallback_model.is_empty() {
            "none"
        } else {
            &runtime.fallback_model
        },
        if runtime.effort.is_empty() {
            "none"
        } else {
            &runtime.effort
        },
    );

    let program = &argv[0];
    let args = &argv[1..];

    // Prepare log file if requested
    let log_file = log_path.and_then(|lp| {
        if let Some(parent) = lp.parent() {
            fs::create_dir_all(parent).ok();
        }
        fs::File::create(lp).ok()
    });

    let child = tokio::process::Command::new(program)
        .args(args)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn();

    let mut child = match child {
        Ok(c) => c,
        Err(e) => {
            eprintln!("  Failed to spawn {program}: {e}");
            return 127;
        }
    };

    // Stream stdout and stderr line-by-line to stderr (journald) and log file
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let log_file = std::sync::Arc::new(std::sync::Mutex::new(log_file));

    let log_clone = log_file.clone();
    let stdout_task = tokio::spawn(async move {
        if let Some(stdout) = stdout {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                eprintln!("{line}");
                if let Ok(mut guard) = log_clone.lock() {
                    if let Some(ref mut f) = *guard {
                        use std::io::Write;
                        let _ = writeln!(f, "{line}");
                    }
                }
            }
        }
    });

    let log_clone = log_file.clone();
    let stderr_task = tokio::spawn(async move {
        if let Some(stderr) = stderr {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                eprintln!("{line}");
                if let Ok(mut guard) = log_clone.lock() {
                    if let Some(ref mut f) = *guard {
                        use std::io::Write;
                        let _ = writeln!(f, "{line}");
                    }
                }
            }
        }
    });

    let _ = tokio::join!(stdout_task, stderr_task);

    match child.wait().await {
        Ok(status) => status.code().unwrap_or(1),
        Err(e) => {
            eprintln!("  Failed to wait for {program}: {e}");
            1
        }
    }
}

// ── Guard ─────────────────────────────────────────────────────────────

/// Acquire an exclusive flock on the lock file. Returns the open File
/// (must be kept alive for the duration of the loop).
fn acquire_lock() -> Result<Option<fs::File>> {
    use std::os::unix::io::AsRawFd;

    let dir = state_dir();
    fs::create_dir_all(&dir)?;

    let lock_file = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(lock_path())?;

    // Non-blocking flock
    let rc = unsafe { libc::flock(lock_file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        eprintln!("Task loop already running, skipping");
        return Ok(None);
    }
    Ok(Some(lock_file))
}

/// Check if the pause file exists. Returns true if paused.
fn is_paused() -> bool {
    let pf = pause_path();
    if pf.exists() {
        if let Ok(content) = fs::read_to_string(&pf) {
            eprintln!("Task loop is paused:");
            for line in content.lines() {
                eprintln!("  {line}");
            }
        }
        true
    } else {
        false
    }
}

// ── Fetch stage ───────────────────────────────────────────────────────

/// Fetch notifications via the reusable `fetch_sources()` helper.
/// Writes sources.json for the ingest deepwork workflow and returns entries.
async fn run_fetch() -> Result<Vec<notifications::SourceEntry>> {
    eprintln!("Stage: fetch");

    let (entries, _manifest_sources) = match notifications::fetch_sources(None).await {
        Ok(result) => result,
        Err(e) => {
            eprintln!("  WARNING: Fetch failed: {e}");
            return Ok(vec![]);
        }
    };

    eprintln!("  Fetched {} source entries", entries.len());

    // Write sources.json for the ingest deepwork workflow to consume
    if !entries.is_empty() {
        let deepwork_dir = PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".to_string()))
            .join(".deepwork");
        fs::create_dir_all(&deepwork_dir).ok();
        let sources_json = serde_json::to_string_pretty(&entries)?;
        fs::write(deepwork_dir.join("sources.json"), &sources_json).ok();
    }

    Ok(entries)
}

// ── Ingest stage ──────────────────────────────────────────────────────

async fn run_ingest(defaults: &StageConfig, profiles: &ProfileCatalog) -> Result<bool> {
    eprintln!("Stage: ingest");

    let runtime = resolve_runtime("ingest", &StageConfig::default(), defaults, profiles);
    let exit_code = run_provider(&runtime, "/deepwork task_loop ingest", None).await;

    if exit_code != 0 {
        eprintln!("  WARNING: Ingest step failed (exit {exit_code}), continuing...");
        return Ok(false);
    }
    Ok(true)
}

// ── Prioritize stage ──────────────────────────────────────────────────

async fn run_prioritize(defaults: &StageConfig, profiles: &ProfileCatalog) -> Result<bool> {
    eprintln!("Stage: prioritize");

    let runtime = resolve_runtime("prioritize", &StageConfig::default(), defaults, profiles);
    let exit_code = run_provider(&runtime, "/deepwork task_loop prioritize", None).await;

    if exit_code != 0 {
        eprintln!("  WARNING: Prioritize step failed (exit {exit_code}), continuing...");
        return Ok(false);
    }
    Ok(true)
}

// ── Execute stage ─────────────────────────────────────────────────────

async fn run_execute(
    max_tasks: u32,
    defaults: &StageConfig,
    profiles: &ProfileCatalog,
) -> Result<(u32, u32, u32)> {
    eprintln!("Stage: execute (max_tasks={max_tasks})");

    let tasks_path = tasks_file_path();
    let logs_dir = task_logs_dir();
    fs::create_dir_all(&logs_dir).ok();

    let mut completed = 0u32;
    let mut failed = 0u32;
    let mut blocked = 0u32;
    let mut attempted: Vec<String> = Vec::new();
    let mut task_count = 0u32;

    while task_count < max_tasks {
        // Reload tasks each iteration (previous task may have modified the file)
        let mut task_file = tasks::load_tasks_from(&tasks_path)?;

        // Find next pending task
        let next_task = task_file
            .tasks
            .iter()
            .find(|t| t.status == "pending" && !attempted.contains(&t.name))
            .cloned();

        let task = match next_task {
            Some(t) => t,
            None => {
                eprintln!("  No more pending tasks");
                break;
            }
        };

        // Prevent infinite loops
        if attempted.contains(&task.name) {
            break;
        }
        attempted.push(task.name.clone());

        // Check dependency satisfaction
        if let Some(ref needs) = task.needs {
            if !needs.is_empty() {
                let all_met = needs.iter().all(|need| {
                    task_file
                        .tasks
                        .iter()
                        .any(|t| t.name == *need && t.status == "completed")
                });
                if !all_met {
                    eprintln!("  Skipping {} (unmet dependencies)", task.name);
                    tasks::block_task(&mut task_file, &task.name, Some("unmet dependencies"));
                    tasks::save_tasks_to(&task_file, &tasks_path)?;
                    blocked += 1;
                    continue;
                }
            }
        }

        task_count += 1;

        // Mark as in-progress
        tasks::start_task(&mut task_file, &task.name);
        tasks::save_tasks_to(&task_file, &tasks_path)?;

        // Build prompt
        let workflow = task.workflow.as_deref().unwrap_or("");
        let prompt = if !workflow.is_empty() && workflow != "null" {
            format!(
                "/deepwork {workflow}\n\nTask: {}\nDescription: {}",
                task.name, task.description
            )
        } else {
            format!(
                "Execute this task.\n\nTask: {}\nDescription: {}",
                task.name, task.description
            )
        };

        // Resolve runtime
        let task_overrides = StageConfig {
            provider: task.source.clone().filter(|s| !s.is_empty()),
            model: task.model.clone(),
            ..Default::default()
        };
        let runtime = resolve_runtime("execute", &task_overrides, defaults, profiles);

        // Set up log file
        let timestamp = chrono::Utc::now().format("%Y-%m-%d_%H%M%S");
        let log_path = logs_dir.join(format!("{timestamp}_{}.log", sanitize_filename(&task.name)));

        eprintln!("  Executing task: {}", task.name);
        let start = Instant::now();

        let exit_code = run_provider(&runtime, &prompt, Some(&log_path)).await;
        let duration = start.elapsed();

        // Reload and update status
        let mut task_file = tasks::load_tasks_from(&tasks_path)?;
        if exit_code == 0 {
            tasks::complete_task(&mut task_file, &task.name);
            completed += 1;
            eprintln!(
                "  Task {} completed ({:.1}s, log: {})",
                task.name,
                duration.as_secs_f64(),
                log_path.display()
            );
        } else {
            // Mark as error
            if let Some(t) = task_file.tasks.iter_mut().find(|t| t.name == task.name) {
                t.status = "error".to_string();
            }
            failed += 1;
            eprintln!(
                "  Task {} errored (exit {exit_code}, {:.1}s, log: {})",
                task.name,
                duration.as_secs_f64(),
                log_path.display()
            );
        }
        tasks::save_tasks_to(&task_file, &tasks_path)?;
    }

    Ok((completed, failed, blocked))
}

// ── Filename sanitization ─────────────────────────────────────────────

/// Sanitize a task name into a safe filename component.
/// Keeps [a-zA-Z0-9_-], replaces everything else with '_'.
fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

// ── Log rotation ──────────────────────────────────────────────────────

fn rotate_logs() {
    let logs_dir = task_logs_dir();
    if !logs_dir.exists() {
        return;
    }
    let mut logs: Vec<_> = fs::read_dir(&logs_dir)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "log"))
        .collect();

    // Sort by modification time (newest first), fall back to path order
    logs.sort_by(|a, b| {
        let a_time = fs::metadata(a.path()).and_then(|m| m.modified()).ok();
        let b_time = fs::metadata(b.path()).and_then(|m| m.modified()).ok();
        b_time.cmp(&a_time)
    });
    for entry in logs.iter().skip(20) {
        fs::remove_file(entry.path()).ok();
    }
}

// ── Entry point ───────────────────────────────────────────────────────

pub async fn execute(args: &AgentLoopArgs) -> Result<()> {
    let name = agent_name();
    eprintln!(
        "ks agent loop: agent={name} max_tasks={} dry_run={}",
        args.max_tasks, args.dry_run
    );

    // Guard: flock
    let _lock = match acquire_lock()? {
        Some(f) => f,
        None => return Ok(()), // another instance is running
    };

    // Guard: pause
    if is_paused() {
        return Ok(());
    }

    // Change to $HOME as working directory (matches task-loop.sh behavior)
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    std::env::set_current_dir(&home).with_context(|| format!("failed to chdir to {home}"))?;

    let defaults = load_stage_config("KS_AGENT_DEFAULTS_JSON");
    let profiles = load_profiles();

    // Stage 1: Fetch
    let sources = run_fetch().await?;

    // Stage 2: Ingest (skip when no source data to avoid wasting LLM calls)
    if sources.is_empty() {
        eprintln!("Stage: ingest (skipped — no source items)");
    } else {
        let _ingest_ok = run_ingest(&defaults, &profiles).await?;
    }

    // Stage 3: Prioritize
    let tasks_path = tasks_file_path();
    let has_pending = if tasks_path.exists() {
        let tf = tasks::load_tasks_from(&tasks_path)?;
        tf.tasks.iter().any(|t| t.status == "pending")
    } else {
        false
    };

    if has_pending {
        let _prio_ok = run_prioritize(&defaults, &profiles).await?;
    } else {
        eprintln!("Stage: prioritize (skipped — no pending tasks)");
    }

    // Stage 4: Execute
    if args.dry_run {
        eprintln!("Stage: execute (skipped — dry-run mode)");
    } else {
        let tf = tasks::load_tasks_from(&tasks_path)?;
        let pending = tf.tasks.iter().filter(|t| t.status == "pending").count();
        if pending == 0 {
            eprintln!("No pending tasks after ingest, done");
        } else {
            let (completed, failed, blocked) =
                run_execute(args.max_tasks, &defaults, &profiles).await?;
            eprintln!(
                "Execute complete: {completed} completed, {failed} failed, {blocked} blocked"
            );
        }
    }

    rotate_logs();
    eprintln!("ks agent loop: done");
    Ok(())
}

// ── Tests ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_first_non_empty() {
        assert_eq!(first_non_empty(&[None, Some(""), Some("claude")]), "claude");
        assert_eq!(first_non_empty(&[Some("gemini"), Some("claude")]), "gemini");
        assert_eq!(first_non_empty(&[None, None]), "");
    }

    #[test]
    fn test_stage_builtin_profile() {
        assert_eq!(stage_builtin_profile("ingest"), "fast");
        assert_eq!(stage_builtin_profile("prioritize"), "fast");
        assert_eq!(stage_builtin_profile("execute"), "medium");
        assert_eq!(stage_builtin_profile("unknown"), "");
    }

    #[test]
    fn test_build_provider_command_claude() {
        let runtime = ResolvedRuntime {
            provider: "claude".to_string(),
            profile: "fast".to_string(),
            model: "haiku".to_string(),
            fallback_model: "sonnet".to_string(),
            effort: "low".to_string(),
        };
        let cmd = build_provider_command(&runtime, "test prompt");
        assert_eq!(cmd[0], "claude");
        assert!(cmd.contains(&"--print".to_string()));
        assert!(cmd.contains(&"--dangerously-skip-permissions".to_string()));
        assert!(cmd.contains(&"--model".to_string()));
        assert!(cmd.contains(&"haiku".to_string()));
        assert!(cmd.contains(&"--fallback-model".to_string()));
        assert!(cmd.contains(&"sonnet".to_string()));
        assert!(cmd.contains(&"--effort".to_string()));
        assert!(cmd.contains(&"low".to_string()));
        assert_eq!(cmd.last().unwrap(), "test prompt");
    }

    #[test]
    fn test_build_provider_command_gemini() {
        let runtime = ResolvedRuntime {
            provider: "gemini".to_string(),
            profile: "".to_string(),
            model: "auto-gemini-3".to_string(),
            fallback_model: "".to_string(),
            effort: "".to_string(),
        };
        let cmd = build_provider_command(&runtime, "do stuff");
        assert_eq!(cmd[0], "gemini");
        assert!(cmd.contains(&"--prompt".to_string()));
        assert!(cmd.contains(&"--yolo".to_string()));
        assert!(cmd.contains(&"-m".to_string()));
        assert!(cmd.contains(&"auto-gemini-3".to_string()));
    }

    #[test]
    fn test_build_provider_command_codex() {
        let runtime = ResolvedRuntime {
            provider: "codex".to_string(),
            profile: "".to_string(),
            model: "".to_string(),
            fallback_model: "".to_string(),
            effort: "".to_string(),
        };
        let cmd = build_provider_command(&runtime, "fix bug");
        assert_eq!(cmd[0], "codex");
        assert!(cmd.contains(&"exec".to_string()));
        assert!(cmd.contains(&"--full-auto".to_string()));
        assert!(!cmd.contains(&"-m".to_string())); // no model specified
        assert_eq!(cmd.last().unwrap(), "fix bug");
    }

    #[test]
    fn test_resolve_runtime_defaults() {
        let defaults = StageConfig::default();
        let profiles = ProfileCatalog::new();
        let task = StageConfig::default();

        // Set the stage env vars won't be present in tests, so stage_cfg will be default
        let runtime = resolve_runtime("execute", &task, &defaults, &profiles);
        assert_eq!(runtime.provider, "claude");
        assert_eq!(runtime.profile, "medium");
    }

    #[test]
    fn test_resolve_runtime_task_overrides() {
        let defaults = StageConfig {
            provider: Some("claude".to_string()),
            model: Some("sonnet".to_string()),
            ..Default::default()
        };
        let profiles = ProfileCatalog::new();
        let task = StageConfig {
            provider: Some("gemini".to_string()),
            ..Default::default()
        };

        let runtime = resolve_runtime("execute", &task, &defaults, &profiles);
        assert_eq!(runtime.provider, "gemini");
        assert_eq!(runtime.model, "sonnet"); // falls through to defaults since task has no model
    }

    #[test]
    fn test_resolve_runtime_with_profiles() {
        let defaults = StageConfig::default();
        let fast_claude = StageConfig {
            model: Some("haiku".to_string()),
            effort: Some("low".to_string()),
            ..Default::default()
        };
        let mut fast = std::collections::HashMap::new();
        fast.insert("claude".to_string(), fast_claude);
        let mut profiles = ProfileCatalog::new();
        profiles.insert("fast".to_string(), fast);

        let task = StageConfig::default();

        let runtime = resolve_runtime("ingest", &task, &defaults, &profiles);
        assert_eq!(runtime.profile, "fast");
        assert_eq!(runtime.model, "haiku");
        assert_eq!(runtime.effort, "low");
    }

    #[test]
    fn test_sanitize_filename() {
        assert_eq!(sanitize_filename("review-pr-372"), "review-pr-372");
        assert_eq!(sanitize_filename("fix_bug_123"), "fix_bug_123");
        assert_eq!(sanitize_filename("../etc/passwd"), "___etc_passwd");
        assert_eq!(sanitize_filename("task with spaces"), "task_with_spaces");
        assert_eq!(sanitize_filename("task/sub/path"), "task_sub_path");
    }
}
