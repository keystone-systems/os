//! `ks approve` command — privileged allowlisted execution.
//!
//! Two entry points:
//!
//! - [`execute`] is the interactive `ks approve …` CLI invocation. It
//!   resolves the helper, validates the policy, then `exec()`-replaces
//!   the current process with `pkexec`/`sudo` running the helper. Used
//!   when a human (or agent) types `ks approve` at the terminal — the
//!   helper inherits the TTY and the process tree collapses cleanly.
//!
//! - [`run_and_wait`] is the orchestrator-callable variant. Same policy
//!   resolution, but spawns the helper as a child and **waits** for it
//!   to exit, returning the [`ExitStatus`]. Used by flows like
//!   `cmd::update_approve` that need to perform follow-up work
//!   *only on activation success*. With `execute`'s exec-replacement
//!   semantics the orchestrator's post-activation steps (relock, commit,
//!   push) would have to run *before* the privileged step, which
//!   violates the atomicity contract — a failed activation would leave
//!   the lock advanced.

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::env;
use std::ffi::OsString;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};

#[derive(Debug, Deserialize)]
struct ApprovalMatch {
    #[serde(rename = "displayName")]
    display_name: String,
    reason: String,
}

fn find_executable(name: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    for entry in env::split_paths(&path) {
        let candidate = entry.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn resolve_approval_helper() -> Result<PathBuf> {
    if let Some(helper) = find_executable("keystone-approve-exec") {
        return Ok(helper);
    }

    let fallback = PathBuf::from("/run/current-system/sw/bin/keystone-approve-exec");
    if fallback.is_file() {
        return Ok(fallback);
    }

    Err(anyhow!(
        "keystone-approve-exec is not available in PATH. Enable keystone.security.privilegedApproval on this host first."
    ))
}

fn has_graphical_session() -> bool {
    env::var_os("DISPLAY").is_some()
        || env::var_os("WAYLAND_DISPLAY").is_some()
        || env::var_os("XDG_SESSION_TYPE").is_some()
}

fn is_root_user() -> Result<bool> {
    let output = Command::new("id")
        .arg("-u")
        .output()
        .context("Failed to check effective user id")?;

    if !output.status.success() {
        return Err(anyhow!("Failed to check effective user id"));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim() == "0")
}

fn validate_request(
    helper: &PathBuf,
    reason: &str,
    requested_argv: &[String],
) -> Result<ApprovalMatch> {
    let output = Command::new(helper)
        .arg("--validate")
        .arg("--reason")
        .arg(reason)
        .arg("--")
        .args(requested_argv)
        .output()
        .context("Failed to validate approval request")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            "Approval request rejected".to_string()
        };
        return Err(anyhow!(detail));
    }

    serde_json::from_slice(&output.stdout).context("Failed to parse approval policy response")
}

fn exec_command(program: PathBuf, args: Vec<OsString>) -> Result<()> {
    let error = Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .exec();
    Err(anyhow!(error)).context("Failed to launch approval helper")
}

/// Common pre-flight: validate inputs, resolve helper, validate against
/// policy, print the dialog header, and build the helper argv. Shared
/// by both [`execute`] (exec-replace) and [`run_and_wait`] (spawn-wait).
fn prepare_invocation(reason: &str, requested_argv: &[String]) -> Result<(PathBuf, Vec<OsString>)> {
    if reason.trim().is_empty() {
        anyhow::bail!("--reason is required")
    }
    if requested_argv.is_empty() {
        anyhow::bail!("Missing command after --")
    }

    let helper = resolve_approval_helper()?;
    let matched = validate_request(&helper, reason, requested_argv)?;

    println!("Approval request: {}", matched.display_name);
    println!("Requested reason: {}", reason);
    println!("Policy reason: {}", matched.reason);

    let mut args = vec![
        OsString::from("--reason"),
        OsString::from(reason),
        OsString::from("--"),
    ];
    args.extend(requested_argv.iter().map(OsString::from));

    Ok((helper, args))
}

/// Choose the program + argv that should be run for the approval flow,
/// given the helper path and pre-built helper args. Returns
/// `(program, argv)` ready to hand to `exec` or `spawn`.
fn select_program(helper: PathBuf, helper_args: Vec<OsString>) -> Result<(PathBuf, Vec<OsString>)> {
    if is_root_user()? || env::var_os("KS_APPROVE_EXECUTING").is_some() {
        return Ok((helper, helper_args));
    }

    if has_graphical_session() && find_executable("pkexec").is_some() {
        let mut pkexec_args = vec![helper.into_os_string()];
        pkexec_args.extend(helper_args);
        return Ok((PathBuf::from("pkexec"), pkexec_args));
    }

    let mut sudo_args = vec![helper.into_os_string()];
    sudo_args.extend(helper_args);
    Ok((PathBuf::from("sudo"), sudo_args))
}

pub fn execute(reason: &str, requested_argv: &[String]) -> Result<()> {
    let (helper, helper_args) = prepare_invocation(reason, requested_argv)?;
    let (program, argv) = select_program(helper, helper_args)?;
    exec_command(program, argv)
}

/// Spawn-and-wait variant of [`execute`]. Returns the helper's
/// [`ExitStatus`] so the caller can decide whether to proceed with
/// follow-up work. Used by `cmd::update_approve::run_supervised_update`
/// to gate post-activation steps (relock, commit, push) on actual
/// activation success.
///
/// Policy is identical to [`execute`]: the same helper resolution,
/// allowlist validation, and pkexec/sudo branching apply. The only
/// difference is that this returns control to the caller instead of
/// `exec()`-replacing the process.
pub fn run_and_wait(reason: &str, requested_argv: &[String]) -> Result<ExitStatus> {
    let (helper, helper_args) = prepare_invocation(reason, requested_argv)?;
    let (program, argv) = select_program(helper, helper_args)?;
    let status = Command::new(&program)
        .args(&argv)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("failed to spawn approval helper via {}", program.display()))?;
    Ok(status)
}
