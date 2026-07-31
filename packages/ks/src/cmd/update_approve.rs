//! `ks update --approve` — Walker-triggered, channel-aware update flow
//! with narrow polkit-elevated activation.
//!
//! Spec: REQ-019.31 (specs/REQ-019-ks-cli.md). Privilege boundary
//! initially defined in issue #487.
//!
//! ```text
//! walker → uwsm app -- systemd-inhibit … systemd-cat
//!                          --identifier=ks-update ks update --approve
//!                                                          [user session]
//!             ├─ pre-flight: refuse if local != origin           [user]
//!             ├─ resolve channel target ref via GitHub API       [user]
//!             ├─ ks approve … -- ks activate <canonical(current)>  ← polkit (warm)
//!             │     └─ canonicalize /run/current-system to its
//!             │       /nix/store closure path (validate_store_path
//!             │       rejects symlinks); ks activate short-circuits
//!             │       because the closure already matches; polkit
//!             │       caches credential under auth_admin_keep
//!             ├─ notify-send "Building <target>…"                [user]
//!             ├─ nix flake update keystone                       [user]
//!             │     --override-input keystone github:.../<rev>
//!             ├─ git commit -m "chore: bump keystone to <ref>"   [user]
//!             │     CAPTURE bump_sha = HEAD
//!             ├─ nix build                                       [user]
//!             ├─ ks approve … -- ks activate <store-path>        ← polkit (cache hit)
//!             │     └─ keystone-approve-exec → ks activate       [root]
//!             ├─ git push origin <branch>                        [user, soft fail]
//!             └─ notify success/failure                          [user]
//! ```
//!
//! Why early-auth + lock-first?
//!
//! The previous order was build-then-prompt: the user clicked Walker →
//! Update and waited 1–2 minutes (silent nix build) before the polkit
//! dialog appeared. By that point the user had often context-switched
//! away and the dialog timed out (exit 127, "Not authorized"), so an
//! otherwise-clean run failed at the auth step. Today's order asks
//! permission first, surfaces a "Building…" notification immediately
//! after auth, and spends the cache window on actual work instead of
//! dead build time.
//!
//! In-sync invariant:
//!
//! Before any side effect, the consumer flake's working tree MUST be
//! clean and the current branch MUST equal `origin/<branch>`. The
//! supervised flow refuses to start otherwise. This buys us:
//!
//! - Rollback is unambiguous: the bump commit is always HEAD, has
//!   exactly one parent, and touches only `flake.lock`. A failure
//!   between commit and successful activation rewinds with
//!   `git reset --hard HEAD~1` after verifying HEAD == bump_sha.
//! - Comprehensibility: when the dialog refuses up front, the user
//!   sees one concrete reason ("ahead of origin", "behind origin",
//!   "uncommitted changes") instead of a partially-applied update
//!   that activated but couldn't push.
//!
//! Atomicity contract (lock-first with rollback on failure):
//!
//! 0. Pre-flight: ensure consumer flake is in sync with origin.
//! 1. Resolve target ref (no filesystem mutation).
//! 2. Warm the polkit credential via a no-op `ks activate
//!    <canonical(current)>`. We canonicalize `/run/current-system`
//!    first because `cmd::activate::validate_store_path` rejects
//!    arguments outside `/nix/store/` (defense-in-depth). The
//!    activation then short-circuits in `cmd::activate::execute`
//!    because the closure already matches current-system; only side
//!    effect is polkit caching the credential under `auth_admin_keep`
//!    for ~5 min.
//! 3. notify-send "Building <target>…" so the user has feedback during
//!    the build phase.
//! 4. Bump `flake.lock` (`nix flake update keystone --override-input
//!    keystone github:.../<rev>`) and commit it. Capture HEAD as
//!    `bump_sha`. NOT pushed yet.
//! 5. `nix build` against the consumer flake's
//!    `nixosConfigurations.<host>.config.system.build.toplevel`. The
//!    lock is correct, so no per-build `--override-input keystone`
//!    needed; local file-source overrides MAY still be layered.
//! 6. `ks activate <store-path>` via [`cmd::approve::run_and_wait`].
//!    The polkit cache from step 2 should cover this prompt; if it
//!    has expired, the user may be prompted again (degraded UX, not
//!    a failure).
//! 7. On activation success: `git push origin <branch>` (best-effort,
//!    soft fail), notify-send "complete".
//! 8. On any failure between steps 4 and 6 success:
//!    `rollback_lock_bump(bump_sha)` — verifies HEAD == bump_sha then
//!    `git reset --hard HEAD~1`. Refuses if HEAD diverged. notify-send
//!    "failed" with a journal pointer.
//!
//! Failure modes:
//!
//! - Step 0 fails → pre-flight refused to start. No side effects.
//! - Step 2 fails (user cancelled or auth failed) → consumer flake
//!   untouched. Next click retries from scratch.
//! - Steps 4 fails (lock update or commit) → working tree may have a
//!   modified `flake.lock` if the failure happened mid-step. The
//!   rollback path runs `git reset --hard HEAD` then a final
//!   `git checkout -- flake.lock` to restore clean state.
//! - Steps 5–6 fail → bump commit exists; rollback resets `HEAD~1`,
//!   leaving the consumer flake exactly as it was before the run.
//! - Step 6 succeeds, step 7 push fails → KEEP the bump commit. System
//!   is on the new closure, lock matches; only the remote is behind.
//!   User pushes by hand. This matches the previous best-effort push
//!   contract.
//!
//! Never confuse this code path with `cmd::update::update_locked`. That
//! is the terminal-only `ks update --lock` flow with full-fleet semantics
//! (pull all managed repos, deploy multiple hosts, sudo-cached
//! activation). This module is consumer-OS-style: one host, one channel
//! target, polkit-elevated activation.

use anyhow::{anyhow, Context, Result};
use std::path::Path;

use crate::cmd::update_menu::{fetch_latest_release, Channel};
use crate::cmd::{self, util};
use crate::repo;

/// Single-host update result for the supervised flow. Returned to
/// `run_update_command` so the JSON envelope shape stays consistent
/// with `cmd::update::UpdateResult`.
#[derive(Debug)]
pub(crate) struct ApproveUpdateOutcome {
    pub host: String,
    pub channel: &'static str,
    pub target_ref: String,
    pub store_path: String,
    /// True when the lock changed and was committed.
    pub lock_advanced: bool,
    /// True when the commit was pushed to origin.
    pub pushed: bool,
}

/// Build the system closure for `host` using the current `flake.lock`.
/// The lock-first flow bumps `flake.lock` to the target rev BEFORE this
/// is called, so `nix build` resolves the keystone input from the lock
/// — no per-build `--override-input keystone` needed. Local file-source
/// overrides (dev-mode `repo::local_override_args`) are still layered.
/// Returns the realized store path of the system toplevel.
async fn build_locked(repo_root: &Path, host: &str, target_label: &str) -> Result<String> {
    let override_args = repo::local_override_args(repo_root).await?;

    let target = format!(
        "{}#nixosConfigurations.{}.config.system.build.toplevel",
        repo_root.display(),
        host
    );

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("build")
        .arg("--no-link")
        .arg("--print-out-paths")
        .arg(&target);
    for arg in &override_args {
        cmd.arg(arg);
    }
    cmd.current_dir(repo_root);

    eprintln!("Building {host} system closure for keystone@{target_label}…\n  target: {target}",);

    let output = cmd
        .output()
        .await
        .context("failed to invoke nix build for supervised update")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nix build failed:\n{}", stderr);
    }

    let path = String::from_utf8_lossy(&output.stdout)
        .lines()
        .find(|line| !line.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| anyhow!("nix build emitted no store path"))?;
    Ok(path)
}

/// Lock the keystone input to a fully-formed `--override-input` value.
/// Caller is responsible for shape: channel mode passes
/// `github:ncrmro/keystone/<rev>`; override mode (REQ-019.31f) passes
/// the user-supplied flag value (`github:.../<branch>`,
/// `path:/...worktree`, etc.) directly. Pre-2025 versions of this
/// helper took a bare `<rev>` and wrapped it internally — that broke
/// the override path because the flag value already includes the
/// `github:ncrmro/keystone/` prefix and double-wrapping produced
/// `github:ncrmro/keystone/github:ncrmro/keystone/<branch>`.
///
/// CRITICAL: pin the lock via `--override-input` rather than running a
/// bare `nix flake update keystone`. For consumer flakes that declare
/// `keystone.url = "github:ncrmro/keystone"`, the bare update would
/// re-resolve the input to the default-branch tip, which can drift
/// from the channel-resolved rev in two ways:
///   1. Stable channel: the target is a tag commit (often older than
///      `main`); `update keystone` would jump to `main` tip and the lock
///      would diverge from the activated closure.
///   2. Unstable channel: between `resolve_target_ref` and this call,
///      a new commit may land on `main`; `update keystone` would pick
///      it up, locking to a rev we never built.
///
/// Use the modern `nix flake update <input>` form rather than the
/// deprecated `nix flake lock --update-input <input>` alias: nix 2.20+
/// rejects `--flake <path>` after the deprecated alias.
///
/// Self-cleaning on failure: `nix flake update` may write to
/// `flake.lock` before returning non-zero. We restore the working tree
/// to `HEAD` so a partial relock can't strand the consumer flake in a
/// state the next run's `ensure_in_sync` pre-flight refuses.
async fn relock_keystone_input(repo_root: &Path, pinned: &str) -> Result<()> {
    let status = tokio::process::Command::new("nix")
        .args([
            "flake",
            "update",
            "keystone",
            "--override-input",
            "keystone",
            pinned,
        ])
        .current_dir(repo_root)
        .status()
        .await
        .context("failed to invoke nix flake update for keystone input")?;
    if !status.success() {
        if let Err(re) = restore_flake_lock(repo_root).await {
            eprintln!("Warning: failed to restore flake.lock after relock failure: {re:#}",);
        }
        anyhow::bail!(
            "nix flake update keystone --override-input keystone {pinned} exited {:?}",
            status.code()
        );
    }
    Ok(())
}

/// Returns true when `flake.lock` has unstaged or staged changes
/// relative to HEAD. We use this to decide whether the relock actually
/// moved anything; if not, no commit / push is needed.
//
// CRITICAL: fail closed when `git status` itself errors. The previous
// implementation `output.status.success() && !output.stdout.is_empty()`
// silently treated git failures (not a worktree, missing git binary,
// permissions error, …) as "clean" and skipped the commit/push step
// while still letting the orchestrator continue. That hid genuine
// configuration breakage from the user. Bail loudly instead so the
// supervised update fails closed and the dialog reports something
// concrete. The orchestrator's atomicity contract is preserved
// because activation already succeeded — but a stale lock left
// uncommitted is still a regression we want surfaced, not swallowed.
async fn flake_lock_dirty(repo_root: &Path) -> Result<bool> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain", "--", "flake.lock"])
        .output()
        .await
        .context("failed to inspect flake.lock status")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "git status --porcelain -- flake.lock exited {:?} in {}: {}",
            output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
    }
    Ok(!output.stdout.is_empty())
}

async fn commit_lock(repo_root: &Path, target_ref: &str) -> Result<()> {
    let add_status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["add", "flake.lock"])
        .status()
        .await
        .context("failed to stage flake.lock")?;
    if !add_status.success() {
        anyhow::bail!("git add flake.lock exited {:?}", add_status.code());
    }
    let msg = format!("chore: bump keystone to {target_ref}");
    let commit_status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["commit", "-m", &msg])
        .status()
        .await
        .context("failed to commit flake.lock")?;
    if !commit_status.success() {
        anyhow::bail!("git commit exited {:?}", commit_status.code());
    }
    Ok(())
}

async fn current_branch(repo_root: &Path) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["symbolic-ref", "--short", "HEAD"])
        .output()
        .await
        .context("failed to read current branch")?;
    if !output.status.success() {
        anyhow::bail!("not on a branch (detached HEAD?)");
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Pre-flight gate for the supervised update flow. Refuse to start
/// unless the consumer flake is in sync with origin.
///
/// CRITICAL invariant: before we touch anything, `local == remote`. The
/// supervised flow's only mutation is exactly one new commit (the
/// keystone lock bump) on the activation-success branch, so the final
/// `git push` is a guaranteed fast-forward by exactly one commit. This
/// removes the failure mode where the orchestrator activated against
/// the new closure but then tripped on a non-fast-forward push because
/// `master` was ahead of `origin/master` — leaving the host updated
/// and the consumer flake out of sync from the perspective of any
/// other agent that goes to relock.
///
/// Refusing up front is also the only error mode the user can act on
/// without inspecting logs: the dialog can name a single concrete
/// reason ("uncommitted changes", "ahead of origin", "behind origin"),
/// and the user knows what command to run before retrying.
///
/// Three sub-checks, in order:
///
/// 1. Working tree is clean. `git status --porcelain` exits 0 and
///    produces no output.
/// 2. `git fetch origin <branch>` is non-fatal — offline use is OK,
///    we just compare against the cached ref. If the fetch succeeds,
///    the next check uses fresh data.
/// 3. `<branch>` and `origin/<branch>` resolve to the same commit. If
///    not equal, bail with both shas in the error so the user can tell
///    whether they're ahead (push) or behind (pull).
async fn ensure_in_sync(repo_root: &Path) -> Result<()> {
    let branch = current_branch(repo_root).await?;

    // Sub-check 1: clean working tree. We use the bare
    // `git status --porcelain` (no path filter) because ANY uncommitted
    // change — not just to flake.lock — would either get mixed into the
    // bump commit or block the commit altogether. Refuse and let the
    // user clean up.
    let status_output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain"])
        .output()
        .await
        .context("failed to inspect consumer flake working tree")?;
    if !status_output.status.success() {
        let stderr = String::from_utf8_lossy(&status_output.stderr);
        anyhow::bail!(
            "git status --porcelain exited {:?} in {}: {}",
            status_output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
    }
    if !status_output.stdout.is_empty() {
        let porcelain = String::from_utf8_lossy(&status_output.stdout);
        anyhow::bail!(
            "consumer flake has uncommitted changes at {}; commit or stash before updating:\n{}",
            repo_root.display(),
            porcelain.trim_end()
        );
    }

    // Sub-check 2: refresh origin/<branch> so the comparison below
    // sees the current remote tip. Non-fatal: if the user is offline
    // we still want to compare against whatever ref we have cached —
    // refusing the update entirely on a transient network blip would
    // be more frustrating than the staleness risk it guards.
    let fetch_status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["fetch", "origin"])
        .arg(&branch)
        .status()
        .await;
    match fetch_status {
        Ok(s) if !s.success() => {
            eprintln!(
                "Warning: git fetch origin {branch} exited {:?}; comparing against cached ref",
                s.code()
            );
        }
        Err(e) => {
            eprintln!(
                "Warning: failed to spawn git fetch origin {branch}: {e:#}; comparing against cached ref"
            );
        }
        _ => {}
    }

    // Sub-check 3: local branch == origin/<branch>. Both sides must
    // resolve. A missing origin ref is a hard error here because we
    // have no defensible way to push a fast-forward into a branch we
    // don't know exists.
    let local_sha = rev_parse(repo_root, &branch).await?;
    let remote_ref = format!("origin/{branch}");
    let remote_sha = rev_parse(repo_root, &remote_ref).await.with_context(|| {
        format!(
            "could not resolve {remote_ref}; ensure the branch is published before running supervised update"
        )
    })?;
    if local_sha == remote_sha {
        return Ok(());
    }

    // Auto-resolve is gated on the default branch only. Feature branches
    // often carry intentional divergence (in-progress rebases, force-pushed
    // history); silently rebasing them onto origin can destroy state.
    let default_branch = git_default_branch(repo_root).await?;
    if branch != default_branch {
        anyhow::bail!(
            "consumer flake branch {branch} ({local_sha}) is out of sync with origin/{branch} ({remote_sha}); \
             pull or push before updating (auto-resolve only runs on the default branch '{default_branch}')"
        );
    }

    let local_is_ancestor = git_is_ancestor(repo_root, &local_sha, &remote_sha).await?;
    let remote_is_ancestor = git_is_ancestor(repo_root, &remote_sha, &local_sha).await?;

    match (local_is_ancestor, remote_is_ancestor) {
        (true, _) => {
            eprintln!("consumer flake {branch} is behind origin/{branch}; fast-forwarding");
            git_run(repo_root, &["merge", "--ff-only", &remote_ref])
                .await
                .with_context(|| format!("fast-forward of {branch} failed"))?;
        }
        (_, true) => {
            // Strictly ahead — push_lock at end of update will publish.
        }
        (false, false) => {
            eprintln!("consumer flake {branch} has diverged from origin/{branch}; rebasing");
            git_run(repo_root, &["rebase", &remote_ref])
                .await
                .with_context(|| {
                    format!(
                        "rebase of {branch} onto {remote_ref} failed; resolve conflicts and retry"
                    )
                })?;
        }
    }
    Ok(())
}

/// `git merge-base --is-ancestor`: exit 0 = ancestor, exit 1 = not, anything
/// else = error. Used to classify the local/remote relationship into
/// behind / ahead / diverged.
async fn git_is_ancestor(repo_root: &Path, anc: &str, desc: &str) -> Result<bool> {
    let status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["merge-base", "--is-ancestor", anc, desc])
        .status()
        .await
        .with_context(|| format!("failed to invoke git merge-base --is-ancestor {anc} {desc}"))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        other => anyhow::bail!(
            "git merge-base --is-ancestor {anc} {desc} exited {:?} in {}",
            other,
            repo_root.display()
        ),
    }
}

/// Run a git subcommand, bailing on non-zero. Inherits stdio so the user
/// (and journal, when invoked via systemd-cat) sees git's progress and
/// any conflict output verbatim.
async fn git_run(repo_root: &Path, args: &[&str]) -> Result<()> {
    let status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(args)
        .status()
        .await
        .with_context(|| format!("failed to invoke git {}", args.join(" ")))?;
    if !status.success() {
        anyhow::bail!(
            "git {} exited {:?} in {}",
            args.join(" "),
            status.code(),
            repo_root.display()
        );
    }
    Ok(())
}

/// Resolve the repo's default branch via `git symbolic-ref --short
/// refs/remotes/origin/HEAD` (e.g. `origin/master` → `master`). Surfaces
/// an error if origin/HEAD is unset rather than guessing a name —
/// misidentifying the default would silently disable the safety gate.
async fn git_default_branch(repo_root: &Path) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        .output()
        .await
        .context("failed to invoke git symbolic-ref refs/remotes/origin/HEAD")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "git symbolic-ref refs/remotes/origin/HEAD exited {:?} in {}: {} \
             (run `git remote set-head origin -a` to populate)",
            output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
    }
    let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stripped = raw.strip_prefix("origin/").unwrap_or(&raw);
    Ok(stripped.to_string())
}

/// Resolve `<refspec>` to a commit SHA via `git rev-parse`. Pulled out
/// so `ensure_in_sync` can compare local and remote tips with a single
/// helper that produces a comparable string (vs. parsing porcelain
/// output).
async fn rev_parse(repo_root: &Path, refspec: &str) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["rev-parse", refspec])
        .output()
        .await
        .with_context(|| format!("failed to invoke git rev-parse {refspec}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "git rev-parse {refspec} exited {:?} in {}: {}",
            output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Push the new lock commit. Best-effort — a failed push is logged but
/// does not fail the whole update because the local activation already
/// succeeded. The user can resolve the push by hand.
async fn push_lock(repo_root: &Path, branch: &str) -> Result<bool> {
    let status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["push", "origin"])
        .arg(branch)
        .status()
        .await
        .context("failed to invoke git push")?;
    if !status.success() {
        eprintln!(
            "Warning: git push origin {branch} exited {:?} — local lock advanced but remote is behind. Push by hand to sync.",
            status.code()
        );
        return Ok(false);
    }
    Ok(true)
}

/// Build the privileged invocation that will be sent through
/// `ks approve … -- ks activate <path>`. Centralised so the test can
/// assert the exact argv shape the broker sees.
pub(crate) fn elevated_argv(store_path: &str) -> Vec<String> {
    vec![
        "ks".to_string(),
        "activate".to_string(),
        store_path.to_string(),
    ]
}

/// Compose the human-readable reason shown in the polkit dialog. The
/// allowlist also has a static `displayName` ("Install Keystone update")
/// — this string is the per-request `Requested reason:` line, which
/// names the host so a user with multiple machines can tell which one
/// the dialog is for.
pub(crate) fn approval_reason(host_label: &str) -> String {
    format!("Install Keystone update on {host_label}")
}

/// Decide whether the orchestrator should proceed to the post-activation
/// (lock-mutation) phase, given the privileged child's exit status.
///
/// Returns `true` only when the child exited with a zero status. Any
/// non-zero exit (including signal termination, reported by `code()` as
/// `None`) MUST keep the lock untouched — this is the atomicity guarantee
/// the activate-then-mutate ordering buys us.
///
/// Pulled out as a pure function so the activation-failure branch is
/// unit-testable without mocking pkexec/keystone-approve-exec.
fn should_advance_lock(status: &std::process::ExitStatus) -> bool {
    status.success()
}

/// Drive the activation step through `cmd::approve::run_and_wait`. The
/// orchestrator-callable variant of the broker spawns the helper and
/// waits for it to exit, so we can inspect the [`std::process::ExitStatus`]
/// and gate post-activation work (push) on actual activation success.
/// The interactive `cmd::approve::execute` path would `exec()`-replace
/// this process and force us to perform that follow-up work *before*
/// the privileged step — which is exactly the atomicity bug the
/// orchestrator-callable variant exists to avoid.
fn activate_via_broker(reason: &str, store_path: &str) -> Result<bool> {
    let argv = elevated_argv(store_path);
    let status = cmd::approve::run_and_wait(reason, &argv)?;
    if !should_advance_lock(&status) {
        // Only log the failure here. Whether a rollback is performed
        // depends on caller state (was a bump committed or did the
        // lock no-op?), so the rollback decision and its corresponding
        // log line live in `run_supervised_update`'s error path.
        eprintln!("ks activate failed (exit {:?}).", status.code());
        return Ok(false);
    }
    Ok(true)
}

/// Warm the polkit credential cache by firing a no-op activation. The
/// allowlist matches `["ks", "activate", …]` (prefix). We canonicalize
/// `/run/current-system` to its underlying `/nix/store/<closure>` first,
/// because `cmd::activate::validate_store_path` rejects any argument
/// that isn't under `/nix/store/` (defense in depth — the symlink
/// itself isn't a store path). The helper then validates `["ks",
/// "activate", "/nix/store/<closure>"]`, execs `ks activate <closure>`
/// as root, and `cmd::activate::execute` short-circuits because the
/// closure already matches `/run/current-system`.
///
/// Net effect: the user sees the polkit dialog within seconds of
/// Walker dispatch, authenticates once, and polkit caches the
/// credential under `auth_admin_keep` (configured by
/// `keystone.security.privilegedApproval` — see
/// `modules/os/privileged-approval.nix:112`). The cache (~5 min default)
/// covers the build and final activation prompt without re-asking.
///
/// On user cancellation / auth failure the helper returns non-zero;
/// this function returns Ok(false) and the caller aborts the run with
/// no side effects on the consumer flake. We treat this as the user
/// explicitly declining the update.
fn warm_polkit_cache(host_label: &str) -> Result<bool> {
    let current = std::fs::canonicalize("/run/current-system").context(
        "failed to canonicalize /run/current-system for the warm approval payload — \
         the host has no current system generation?",
    )?;
    let current_str = current.to_str().ok_or_else(|| {
        anyhow!(
            "/run/current-system canonical path {} is not valid UTF-8",
            current.display()
        )
    })?;
    let argv = elevated_argv(current_str);
    let reason = approval_reason(host_label);
    eprintln!("Requesting approval for the upcoming activation (warming polkit cache)…");
    let status = cmd::approve::run_and_wait(&reason, &argv)?;
    if !status.success() {
        eprintln!(
            "Polkit approval cancelled or failed (exit {:?}) — aborting update.",
            status.code()
        );
        return Ok(false);
    }
    Ok(true)
}

/// Best-effort desktop notification surfaced after the early polkit
/// approval, before the build phase begins. Bridges the silent
/// build-phase wait with feedback so the user knows the update is
/// progressing. Gated on `KS_UPDATE_NOTIFY=1` (set by the launcher in
/// `cmd::update_menu::start_update_session`) so direct CLI invocations
/// stay quiet on the desktop. Failures are swallowed — this is purely
/// UX feedback.
fn notify_build_phase(target_label: &str) {
    if std::env::var_os("KS_UPDATE_NOTIFY").is_none() {
        return;
    }
    let body = format!("Building keystone@{target_label}…");
    let _ = util::notify_send("Keystone update", &body, "normal");
}

/// Bump the keystone input in `flake.lock` to `target_rev` and commit
/// it on the current branch. Returns `(lock_advanced, bump_sha)`:
///
/// - `lock_advanced = true` and `bump_sha = Some(sha)` when the lock
///   moved and a new commit landed.
/// - `lock_advanced = false` and `bump_sha = None` when the lock was
///   already at `target_rev` (no relock changes, no commit). In that
///   case the caller has nothing to roll back.
///
/// Transactional contract: if any inner step (`relock_keystone_input`,
/// `flake_lock_dirty`, `commit_lock`) fails partway, this function
/// restores `flake.lock` to its `HEAD` state via
/// `git checkout HEAD -- flake.lock` — both the working tree and the
/// index are reset, so a subsequent `ensure_in_sync` pre-flight on
/// the next run still sees a clean tree. Without this, a partial
/// `nix flake update` (lock modified, commit not yet made) or a
/// `commit` failure after `git add` would strand the consumer flake
/// in a state the next run refuses to start from.
async fn bump_lock_and_commit(
    repo_root: &Path,
    target_rev: &str,
    target_label: &str,
) -> Result<(bool, Option<String>)> {
    match bump_lock_and_commit_inner(repo_root, target_rev, target_label).await {
        Ok(result) => Ok(result),
        Err(e) => {
            if let Err(restore_err) = restore_flake_lock(repo_root).await {
                eprintln!(
                    "Warning: failed to restore flake.lock after bump failure: {restore_err:#}. \
                     Working tree may be dirty; resolve manually before retrying.",
                );
            }
            Err(e)
        }
    }
}

async fn bump_lock_and_commit_inner(
    repo_root: &Path,
    target_rev: &str,
    target_label: &str,
) -> Result<(bool, Option<String>)> {
    let pinned = format!("github:ncrmro/keystone/{target_rev}");
    relock_keystone_input(repo_root, &pinned).await?;
    if !flake_lock_dirty(repo_root).await? {
        eprintln!("flake.lock already pinned at {target_rev} — no commit needed.");
        return Ok((false, None));
    }
    commit_lock(repo_root, target_label).await?;
    let sha = rev_parse(repo_root, "HEAD").await?;
    eprintln!("Committed flake.lock bump (HEAD={sha}).");
    Ok((true, Some(sha)))
}

/// Restore `flake.lock` from `HEAD` into both the index and the
/// working tree. Used to roll back partial bump failures (mid-relock
/// or mid-commit). After this call, `git status -- flake.lock`
/// produces no output and the next supervised run's `ensure_in_sync`
/// pre-flight passes again.
async fn restore_flake_lock(repo_root: &Path) -> Result<()> {
    let status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["checkout", "HEAD", "--", "flake.lock"])
        .status()
        .await
        .context("failed to invoke git checkout HEAD -- flake.lock")?;
    if !status.success() {
        anyhow::bail!("git checkout HEAD -- flake.lock exited {:?}", status.code());
    }
    Ok(())
}

/// Rewind the bump commit if HEAD still equals `expected_sha`. Refuses
/// if HEAD diverged (someone committed in parallel between our commit
/// and the failure point) — we surface a clear error instead of
/// destroying the user's work via `git reset --hard`.
///
/// On success the working tree is at the pre-bump SHA and is clean.
async fn rollback_lock_bump(repo_root: &Path, expected_sha: &str) -> Result<()> {
    let head_now = rev_parse(repo_root, "HEAD").await?;
    if head_now != expected_sha {
        anyhow::bail!(
            "rollback refused: HEAD ({head_now}) diverged from the bump commit ({expected_sha}). \
             Resolve manually — your work is intact."
        );
    }
    let status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["reset", "--hard", "HEAD~1"])
        .status()
        .await
        .context("failed to invoke git reset for rollback")?;
    if !status.success() {
        anyhow::bail!("git reset --hard HEAD~1 exited {:?}", status.code());
    }
    eprintln!("Rolled back flake.lock bump.");
    Ok(())
}

/// Resolve the supervised flow's target rev/label. In override mode
/// (REQ-019.31f) the flag value is used directly so callers can point
/// at unpublished worktrees (`path:/…`) or feature branches
/// (`github:…/<branch>`) without going through the channel API. In
/// channel mode we hit the existing GitHub release / branch lookup.
async fn resolve_target(
    channel: Channel,
    target_override: Option<&str>,
) -> Result<(String, String)> {
    match target_override {
        Some(value) => Ok((value.to_string(), value.to_string())),
        None => {
            let info = fetch_latest_release(channel).await.with_context(|| {
                format!("failed to resolve {} channel target", channel.as_str())
            })?;
            if info.latest_rev.trim().is_empty() {
                anyhow::bail!(
                    "{} channel returned no commit sha for target {}",
                    channel.as_str(),
                    info.latest_tag
                );
            }
            // CRITICAL: prefer `latest_name` (e.g., `main@<shortsha>`)
            // for the audit-trail label. `latest_tag` for unstable is
            // the literal "main" — losing the resolved SHA. Stable
            // channels coincide on the tag.
            let target_label = if info.latest_name.is_empty() {
                info.latest_tag.clone()
            } else {
                info.latest_name.clone()
            };
            eprintln!(
                "Resolved {} channel target: {target_label} ({})",
                channel.as_str(),
                info.latest_rev,
            );
            Ok((info.latest_rev, target_label))
        }
    }
}

/// Cleanup the consumer flake at end-of-run.
///
/// - Override mode (REQ-019.31f) ALWAYS restores `flake.lock` from
///   HEAD: success or failure both end with a clean working tree, no
///   commits, nothing to push.
/// - Channel mode rolls back the bump commit on failure (when one
///   was created) so the consumer flake is back at the pre-update
///   SHA.
/// - Channel mode on success leaves the bump commit in place — the
///   caller's push step picks it up.
async fn cleanup_after_outcome(
    repo_root: &Path,
    target_override: Option<&str>,
    bump_sha: Option<&str>,
    failed: bool,
) {
    if target_override.is_some() {
        if let Err(restore_err) = restore_flake_lock(repo_root).await {
            eprintln!(
                "Warning: failed to restore flake.lock after override-mode {}: \
                 {restore_err:#}. Working tree may be dirty.",
                if failed { "failure" } else { "success" }
            );
        }
        return;
    }
    if failed {
        if let Some(sha) = bump_sha {
            if let Err(rollback_err) = rollback_lock_bump(repo_root, sha).await {
                eprintln!("Warning: rollback failed: {rollback_err:#}. Manual cleanup required.");
            }
        }
    }
}

/// Top-level entry. Spec: REQ-019.31. Order:
///
/// 1. Pre-flight (in-sync) → refuse unless local == origin.
/// 2. Resolve target: channel API or `target_override` if Some.
/// 3. **Early polkit warm.** Fires the dialog within ~2 s of Walker
///    dispatch. User cancellation aborts cleanly.
/// 4. notify-send "Building …" (gated on `KS_UPDATE_NOTIFY=1`).
/// 5. Lock change. Channel mode: bump + commit, capture `bump_sha`.
///    Override mode (REQ-019.31f): working-tree-only relock, no commit.
/// 6. `nix build` against the bumped/dirty lock.
/// 7. `ks activate` via broker. Polkit cache from step 3 should hit.
/// 8. On success in channel mode: best-effort `git push`. Override
///    mode skips push.
/// 9. Cleanup: channel mode rolls back the bump commit on failure
///    (`rollback_lock_bump`). Override mode unconditionally restores
///    the working-tree lock (`restore_flake_lock`) on success or
///    failure so the consumer flake ends clean.
pub(crate) async fn run_supervised_update(
    flake_override: Option<&Path>,
    target_override: Option<&str>,
) -> Result<ApproveUpdateOutcome> {
    let repo_root = repo::find_repo(flake_override)?;
    let host = repo::resolve_current_host(&repo_root)
        .await?
        .ok_or_else(|| anyhow!("could not resolve current host from repo registry"))?;

    let channel = Channel::current();
    if let Some(value) = target_override {
        eprintln!(
            "Running supervised update for host {} with --keystone override {} \
             (channel {} ignored; no commit, no push)",
            host,
            value,
            channel.as_str()
        );
    } else {
        eprintln!(
            "Running supervised update for host {} on channel {}",
            host,
            channel.as_str()
        );
    }

    // Step 1: pre-flight in-sync check.
    ensure_in_sync(&repo_root).await?;

    // Step 2: resolve target (channel API or override).
    let (target_rev, target_label) = resolve_target(channel, target_override).await?;

    let host_label = util::hostname_label();

    // Step 3: warm the polkit cache. User cancellation aborts cleanly.
    let warmed = warm_polkit_cache(&host_label)?;
    if !warmed {
        anyhow::bail!(
            "approval cancelled or failed for {} on host {}; no changes made",
            target_label,
            host
        );
    }

    // Step 4: surface "building" notification.
    notify_build_phase(&target_label);

    // Step 5: lock change.
    //
    // - Channel mode: relock + commit; `bump_sha` lets us roll back on
    //   later failure.
    // - Override mode: working-tree-only relock so the consumer flake
    //   carries no commit a future `git push` could publish; the
    //   matching `restore_flake_lock` runs unconditionally below.
    let bump_sha = match target_override {
        Some(_) => {
            relock_keystone_input(&repo_root, &target_rev).await?;
            None
        }
        None => {
            bump_lock_and_commit(&repo_root, &target_rev, &target_label)
                .await?
                .1
        }
    };
    let lock_advanced = bump_sha.is_some();

    // Steps 6 + 7: build and activate.
    let outcome = run_build_and_activate(&repo_root, &host, &target_label, &host_label).await;
    let failed = outcome.is_err();
    cleanup_after_outcome(&repo_root, target_override, bump_sha.as_deref(), failed).await;
    let store_path = outcome.map_err(|e| {
        e.context(format!(
            "supervised update failed for {} on host {}",
            target_label, host
        ))
    })?;

    // Step 8: push only in channel mode. Override mode never publishes.
    // A network blip in channel mode does NOT trigger rollback — the
    // system is on the new closure, the lock matches, and only the
    // remote is behind.
    let pushed = if target_override.is_none() && lock_advanced {
        let branch = current_branch(&repo_root).await?;
        match push_lock(&repo_root, &branch).await {
            Ok(p) => p,
            Err(e) => {
                eprintln!(
                    "Warning: git push for branch {branch} failed to spawn: {e:#} — local lock advanced but remote is behind. Push by hand to sync.",
                );
                false
            }
        }
    } else {
        false
    };

    Ok(ApproveUpdateOutcome {
        host,
        channel: channel.as_str(),
        target_ref: target_label,
        store_path,
        lock_advanced,
        pushed,
    })
}

/// Steps 6 + 7 of `run_supervised_update`, factored out so a single
/// `?`-style early return covers both the build and activation paths
/// from the orchestrator's perspective. Any failure here propagates up
/// and triggers `rollback_lock_bump` in the caller.
async fn run_build_and_activate(
    repo_root: &Path,
    host: &str,
    target_label: &str,
    host_label: &str,
) -> Result<String> {
    // Step 6: build against the bumped lock.
    let store_path = build_locked(repo_root, host, target_label).await?;
    eprintln!("Built closure: {store_path}");

    // Step 7: activate via the privileged broker. Polkit cache from
    // the warm step should hit; if not, the user re-prompts.
    let reason = approval_reason(host_label);
    eprintln!("Requesting activation of {store_path}…");
    let activated = activate_via_broker(&reason, &store_path)?;
    if !activated {
        anyhow::bail!("activation was not approved or failed");
    }
    Ok(store_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn elevated_argv_is_exactly_ks_activate_path() {
        // CRITICAL: the privileged-approval allowlist matches on argv
        // shape `["ks", "activate", <prefix>]`. If anyone reorders or
        // injects an extra arg here, the broker rejects the request
        // with "command is not allowlisted" and Walker → Update fails
        // silently. This test pins the contract.
        let argv = elevated_argv("/nix/store/abcdef-system-x");
        assert_eq!(argv, vec!["ks", "activate", "/nix/store/abcdef-system-x"]);
    }

    #[test]
    fn elevated_argv_contains_no_git_verbs() {
        // Defense in depth: the producer-side workflow does git pull,
        // commit, push as the user. The privileged child must never
        // see a git verb because root has no SSH credentials.
        let argv = elevated_argv("/nix/store/x");
        for forbidden in ["pull", "push", "commit", "fetch", "clone", "lock"] {
            assert!(
                !argv.iter().any(|a| a == forbidden),
                "argv leaked git verb {forbidden}: {argv:?}"
            );
        }
    }

    #[test]
    fn should_advance_lock_only_on_zero_exit() {
        // CRITICAL atomicity guard for issue #487: the orchestrator
        // MUST NOT mutate flake.lock unless the privileged ks-activate
        // child returned a zero exit status. ExitStatus has no
        // public constructor, so we shell out to /usr/bin/env true /
        // false (or `sh -c "exit N"`) to manufacture the two cases.
        //
        // Without this guard, a polkit-declined or ks-activate-failed
        // run would leave flake.lock advanced to a rev that was never
        // promoted to /run/current-system, contradicting the
        // activate-then-mutate contract documented at the top of
        // this module.
        let success = std::process::Command::new("sh")
            .args(["-c", "exit 0"])
            .status()
            .expect("spawn `sh -c 'exit 0'` for atomicity test");
        assert!(
            should_advance_lock(&success),
            "zero exit should permit lock advance"
        );

        let failure = std::process::Command::new("sh")
            .args(["-c", "exit 7"])
            .status()
            .expect("spawn `sh -c 'exit 7'` for atomicity test");
        assert!(
            !should_advance_lock(&failure),
            "non-zero exit MUST block lock advance (atomicity invariant for issue #487)"
        );
    }

    #[test]
    fn approval_reason_names_the_host() {
        // The polkit dialog shows the displayName from the allowlist
        // statically; the per-request reason is what tells the user
        // which machine they're approving. Empty / generic reasons
        // would let a Mac-style "approve anywhere" social-engineer
        // the user into hitting yes on the wrong host.
        let reason = approval_reason("ncrmro-laptop");
        assert!(reason.contains("ncrmro-laptop"), "reason: {reason}");
        assert!(reason.contains("Keystone update"), "reason: {reason}");
    }

    /// Build a working consumer-flake fixture: a bare "remote" repo
    /// alongside a "local" repo that has cloned + tracked it. Returns
    /// the (TempDir, local-repo-path, remote-repo-path) — TempDir keeps
    /// both alive for the test's duration. The local repo is on
    /// branch `master` with one commit, in sync with origin.
    ///
    /// CRITICAL: tests MUST pass `--initial-branch=master` to git init
    /// and rely on the bare remote's HEAD pointing there. Some host
    /// environments default to `main`; pinning the branch keeps the
    /// fixture deterministic.
    fn make_in_sync_fixture() -> (tempfile::TempDir, std::path::PathBuf, std::path::PathBuf) {
        let tmp = tempfile::tempdir().expect("create tempdir for in-sync fixture");
        let local = tmp.path().join("local");
        let remote = tmp.path().join("remote.git");

        // Remote: bare repo on `master`.
        let s = std::process::Command::new("git")
            .args(["init", "--bare", "--initial-branch=master"])
            .arg(&remote)
            .status()
            .expect("git init --bare");
        assert!(s.success(), "git init --bare failed");

        // Local: regular repo on `master`, with one commit.
        let s = std::process::Command::new("git")
            .args(["init", "--initial-branch=master"])
            .arg(&local)
            .status()
            .expect("git init local");
        assert!(s.success(), "git init local failed");

        // Identity, lest commit refuse on hosts without global config.
        for (k, v) in [
            ("user.email", "test@example.invalid"),
            ("user.name", "Test"),
            ("commit.gpgsign", "false"),
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(["config", k, v])
                .status()
                .expect("git config");
            assert!(s.success(), "git config {k} failed");
        }

        std::fs::write(local.join("flake.lock"), "{}").expect("write flake.lock");
        for args in [
            vec!["add", "flake.lock"],
            vec!["commit", "-m", "init"],
            vec!["remote", "add", "origin"],
        ] {
            let mut cmd = std::process::Command::new("git");
            cmd.arg("-C").arg(&local).args(&args);
            if args == vec!["remote", "add", "origin"] {
                cmd.arg(&remote);
            }
            let s = cmd.status().expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }
        let s = std::process::Command::new("git")
            .arg("-C")
            .arg(&local)
            .args(["push", "-u", "origin", "master"])
            .status()
            .expect("git push");
        assert!(s.success(), "git push -u origin master failed");

        // `resolve_default_branch_from_origin_head` requires refs/remotes/origin/HEAD
        // to be a symbolic ref. `git clone` sets this automatically; `git init` +
        // `git remote add` + `git push` does not, so we set it explicitly here.
        let s = std::process::Command::new("git")
            .arg("-C")
            .arg(&local)
            .args([
                "symbolic-ref",
                "refs/remotes/origin/HEAD",
                "refs/remotes/origin/master",
            ])
            .status()
            .expect("git symbolic-ref");
        assert!(
            s.success(),
            "git symbolic-ref refs/remotes/origin/HEAD failed"
        );

        (tmp, local, remote)
    }

    #[tokio::test]
    async fn ensure_in_sync_passes_when_clean_and_matching_origin() {
        // Happy path. Working tree clean, local == origin/<branch>.
        // ensure_in_sync MUST return Ok so the orchestrator can proceed
        // to channel resolution and build.
        let (_tmp, local, _remote) = make_in_sync_fixture();
        ensure_in_sync(&local)
            .await
            .expect("clean + in-sync should pass");
    }

    #[tokio::test]
    async fn ensure_in_sync_refuses_dirty_working_tree() {
        // CRITICAL: refuse if the working tree has uncommitted changes.
        // Otherwise, either the bump commit would absorb them (silent
        // data loss into a chore commit) or the commit would fail
        // partway and leave the host activated against a closure whose
        // lock isn't recorded anywhere.
        let (_tmp, local, _remote) = make_in_sync_fixture();
        std::fs::write(local.join("dirty.txt"), "uncommitted\n").expect("write dirty file");

        let err = ensure_in_sync(&local)
            .await
            .expect_err("dirty working tree must be rejected");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("uncommitted changes"),
            "error should name the failure mode: {msg}"
        );
    }

    #[tokio::test]
    async fn ensure_in_sync_refuses_when_local_is_ahead_of_origin() {
        // The exact failure mode that motivated this commit: local
        // had two cherry-picked commits beyond origin, so the supervised
        // flow's post-activation `git push` tripped on a non-fast-forward.
        // Refuse up front instead.
        //
        // CRITICAL: since f23ccaf2 auto-resolves ahead/behind/diverged on
        // the default branch, this test exercises a non-default feature
        // branch where the hard-refuse semantics still apply.
        let (_tmp, local, _remote) = make_in_sync_fixture();

        // Switch to a feature branch and publish it so `origin/feature`
        // exists, then add a local-only commit on top.
        for args in [
            vec!["switch", "-c", "feature"],
            vec!["push", "-u", "origin", "feature"],
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }

        // Add a commit locally without pushing.
        std::fs::write(local.join("ahead.txt"), "ahead\n").expect("write ahead file");
        for args in [vec!["add", "ahead.txt"], vec!["commit", "-m", "ahead"]] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }

        let err = ensure_in_sync(&local)
            .await
            .expect_err("ahead-of-origin must be rejected");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("out of sync"),
            "error should name the failure mode: {msg}"
        );
        assert!(
            msg.contains("feature"),
            "error should name the branch: {msg}"
        );
    }

    /// Helper: write a `flake.lock` change, stage + commit it on top of
    /// the in-sync fixture, return the resulting HEAD sha. Lets the
    /// rollback tests exercise the same shape `bump_lock_and_commit`
    /// produces (single-file, single-commit ahead of origin) without
    /// relying on a real `nix flake update`.
    async fn make_bump_commit(local: &Path, body: &str) -> String {
        std::fs::write(local.join("flake.lock"), body).expect("rewrite flake.lock");
        for args in [
            vec!["add", "flake.lock"],
            vec!["commit", "-m", "chore: bump keystone (test)"],
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(local)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }
        rev_parse(local, "HEAD").await.expect("rev-parse HEAD")
    }

    #[tokio::test]
    async fn rollback_lock_bump_resets_to_pre_bump_when_head_matches() {
        // Happy path: bump_sha == HEAD → reset --hard HEAD~1 lands us
        // back on the pre-bump SHA with a clean working tree. The
        // rollback path is what makes lock-first safe under failures
        // between the commit and a successful activation.
        let (_tmp, local, _remote) = make_in_sync_fixture();
        let pre_bump = rev_parse(&local, "HEAD").await.expect("rev-parse pre-bump");
        let bump_sha = make_bump_commit(&local, "{ \"new\": true }\n").await;
        assert_ne!(pre_bump, bump_sha, "fixture must produce a new commit");

        rollback_lock_bump(&local, &bump_sha)
            .await
            .expect("rollback should succeed when HEAD matches");

        let after = rev_parse(&local, "HEAD")
            .await
            .expect("rev-parse post-rollback");
        assert_eq!(after, pre_bump, "rollback should restore pre-bump SHA");

        // Working tree must be clean — the rollback restores the
        // pre-bump flake.lock contents.
        let status = std::process::Command::new("git")
            .arg("-C")
            .arg(&local)
            .args(["status", "--porcelain"])
            .output()
            .expect("git status");
        assert!(status.status.success(), "git status failed");
        assert!(
            status.stdout.is_empty(),
            "working tree must be clean after rollback: {}",
            String::from_utf8_lossy(&status.stdout)
        );
    }

    #[tokio::test]
    async fn rollback_lock_bump_refuses_when_head_diverged() {
        // Defensive guard: if someone (or a parallel agent) committed
        // between our bump and the rollback trigger, HEAD no longer
        // matches `expected_sha`. `git reset --hard HEAD~1` would
        // discard their work. Refuse and surface a clear error so the
        // user can resolve manually.
        let (_tmp, local, _remote) = make_in_sync_fixture();
        let bump_sha = make_bump_commit(&local, "{ \"bumped\": true }\n").await;

        // Drop another commit on top so HEAD != bump_sha.
        std::fs::write(local.join("other.txt"), "parallel work\n").expect("write other.txt");
        for args in [
            vec!["add", "other.txt"],
            vec!["commit", "-m", "parallel work"],
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }
        let head_after_parallel = rev_parse(&local, "HEAD")
            .await
            .expect("rev-parse parallel head");
        assert_ne!(
            head_after_parallel, bump_sha,
            "fixture must drift HEAD past the bump"
        );

        let err = rollback_lock_bump(&local, &bump_sha)
            .await
            .expect_err("rollback must refuse on diverged HEAD");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("diverged") || msg.contains("refused"),
            "error must name the divergence: {msg}"
        );

        // Diverged commit must still be present — we did NOT reset.
        let head_now = rev_parse(&local, "HEAD")
            .await
            .expect("rev-parse post-refusal");
        assert_eq!(
            head_now, head_after_parallel,
            "refusing rollback must leave HEAD untouched"
        );
    }

    #[tokio::test]
    async fn ensure_in_sync_refuses_when_local_is_behind_origin() {
        // Symmetric to the ahead case: if origin has commits the local
        // doesn't, the lock-bump commit would be on a stale base. The
        // user almost certainly wants `git pull --rebase` first.
        //
        // CRITICAL: since f23ccaf2 auto-resolves ahead/behind/diverged on
        // the default branch, this test exercises a non-default feature
        // branch where the hard-refuse semantics still apply.
        let (_tmp, local, remote) = make_in_sync_fixture();

        // Switch local to a feature branch and publish it so the
        // parallel clone can push a commit onto origin/feature.
        for args in [
            vec!["switch", "-c", "feature"],
            vec!["push", "-u", "origin", "feature"],
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }

        // Make a parallel clone, push a new commit on `feature`.
        let other = local.parent().unwrap().join("other");
        let s = std::process::Command::new("git")
            .args(["clone"])
            .arg(&remote)
            .arg(&other)
            .status()
            .expect("git clone other");
        assert!(s.success(), "git clone failed");
        for (k, v) in [
            ("user.email", "test@example.invalid"),
            ("user.name", "Test"),
            ("commit.gpgsign", "false"),
        ] {
            std::process::Command::new("git")
                .arg("-C")
                .arg(&other)
                .args(["config", k, v])
                .status()
                .expect("git config")
                .success()
                .then_some(())
                .expect("git config failed");
        }
        // Check out `feature` in the parallel clone before committing.
        let s = std::process::Command::new("git")
            .arg("-C")
            .arg(&other)
            .args(["switch", "feature"])
            .status()
            .expect("git switch feature");
        assert!(s.success(), "git switch feature failed");
        std::fs::write(other.join("behind.txt"), "behind\n").expect("write behind file");
        for args in [
            vec!["add", "behind.txt"],
            vec!["commit", "-m", "remote-ahead"],
            vec!["push", "origin", "feature"],
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&other)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }

        // Now `local` is behind `origin/feature`. ensure_in_sync should
        // refuse on the non-default branch. The fetch inside
        // ensure_in_sync will refresh origin/feature to the new tip.
        let err = ensure_in_sync(&local)
            .await
            .expect_err("behind-origin must be rejected");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("out of sync"),
            "error should name the failure mode: {msg}"
        );
        assert!(
            msg.contains("feature"),
            "error should name the branch: {msg}"
        );
    }
}
