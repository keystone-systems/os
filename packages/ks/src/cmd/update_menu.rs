//! `ks menu update ...` — Walker provider backend for the Keystone OS update
//! entry.
//!
//! Subcommands:
//!
//! - `status` — emit the raw state JSON (same shape the bash script used to
//!   produce via `load_state`). Used for diagnostics and consumed by the
//!   other subcommands in-process.
//! - `entries` — emit the Walker JSON entry array.
//! - `preview-summary` — emit the plain-text preview pane for the summary
//!   row.
//! - `preview-release-notes` — emit the plain-text preview pane for the
//!   release-notes row.
//! - `dispatch <value>` — handle a Walker activation. Activation values are
//!   restricted to the stable tokens listed in the `Activation values`
//!   block below (`run-update`, `noop`, `blocked-update-unavailable`,
//!   `blocked-keystone-unavailable`, and `open-release-page\t<url>`) so the
//!   Lua provider's single-quoted `%VALUE%` interpolation stays safe.
//!
//! Replaces the previous bash implementation at
//! `modules/desktop/home/scripts/keystone-update-menu.sh`.

use std::env;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::repo;

pub(crate) const RELEASE_OWNER: &str = "ncrmro";
pub(crate) const RELEASE_REPO: &str = "keystone";

// -----------------------------------------------------------------------------
// Channel
// -----------------------------------------------------------------------------

/// Release source the menu tracks. Selected by `keystone.update.channel` in
/// the Nix module, surfaced at runtime via `KS_UPDATE_CHANNEL` and
/// `/run/current-system/keystone-update-channel`. Fail-closed default is
/// `Stable` so an unset, empty, or unknown source never flips a host onto the
/// moving-main source implicitly.
///
/// Visible at crate scope so the Walker → Update orchestrator
/// (`cmd::update`) can resolve the same target the menu surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Channel {
    /// Tip of the highest `release/<M>.<m>` branch — the stabilized release
    /// line. Like a nixpkgs release channel, this tracks a moving branch
    /// head (fixes are backported onto the line) rather than a tagged
    /// release.
    Stable,
    /// `/repos/OWNER/REPO/branches/main` — HEAD of `main`, the moving
    /// development source.
    Unstable,
}

impl Channel {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "stable" => Some(Self::Stable),
            "unstable" => Some(Self::Unstable),
            _ => None,
        }
    }

    /// Resolve the active channel from KS_UPDATE_CHANNEL first, then the
    /// runtime pointer file written into `/run/current-system`. Any other
    /// value maps to `Stable` so a misconfigured runtime never quietly flips a
    /// host onto the moving-main source.
    pub(crate) fn current() -> Self {
        std::env::var("KS_UPDATE_CHANNEL")
            .ok()
            .as_deref()
            .and_then(Self::parse)
            .or_else(|| {
                repo::read_system_update_channel()
                    .as_deref()
                    .and_then(Self::parse)
            })
            .unwrap_or(Self::Stable)
    }

    pub(crate) fn as_str(&self) -> &'static str {
        match self {
            Self::Stable => "stable",
            Self::Unstable => "unstable",
        }
    }
}

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

/// Full state emitted when discovery succeeds. Field names match the shape
/// produced by the legacy bash `load_state` so downstream tooling (or humans
/// inspecting `ks menu update status`) sees the same structure.
///
/// `channel` is always populated (`"stable"` or `"unstable"`) so downstream
/// diagnostics always know which source produced `latest_*`.
#[derive(Debug, Serialize)]
struct OkState {
    ok: bool, // always true
    channel: String,
    repo_root: String,
    input_name: String,
    current_rev: String,
    current_tag: String,
    latest_tag: String,
    latest_name: String,
    latest_url: String,
    latest_published: String,
    latest_body: String,
    latest_rev: String,
    host_key: String,
    status_kind: String, // "up-to-date" | "behind" | "ahead"
    status_summary: String,
    update_reason: String,
    dirty: bool,
    update_allowed: bool,
}

/// Error state. Partial fields are populated when available so previews can
/// still render something useful. Every real construction site sets
/// `channel` explicitly from `Channel::current().as_str()` so an error
/// surface discloses which source the menu was attempting to track. `Default`
/// is derived only so the `..Default::default()` update syntax can fill the
/// Optional fields in each call site; a raw `ErrState::default()` would
/// produce an empty `channel` and is not a valid production value.
#[derive(Debug, Serialize, Default)]
struct ErrState {
    ok: bool, // always false
    #[serde(default)]
    channel: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_root: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    input_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    current_rev: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    current_tag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_tag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_published: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    dirty: Option<bool>,
    error: String,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum MenuState {
    Ok(OkState),
    Err(ErrState),
}

// -----------------------------------------------------------------------------
// Flake.lock parsing
// -----------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct FlakeLock {
    nodes: std::collections::HashMap<String, FlakeNode>,
    // The `root` attribute names the entry node; the legacy bash probe
    // anchored resolution there so the menu is immune to transitive
    // dependencies that happen to pin the same GitHub repo.
    #[serde(default = "default_root")]
    root: String,
}

fn default_root() -> String {
    "root".to_string()
}

#[derive(Debug, Deserialize)]
struct FlakeNode {
    locked: Option<FlakeLocked>,
    original: Option<FlakeOriginal>,
    /// Present on the root node; maps input names to node ids (either a
    /// direct string, or a resolution-path array for `follows` inputs).
    #[serde(default)]
    inputs: std::collections::HashMap<String, InputRef>,
}

/// A root-level input entry points either at a node name (direct input) or a
/// resolution path (a `follows` chain). We only care about the direct case
/// when identifying which input is the keystone one.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum InputRef {
    Direct(String),
    Path(Vec<String>),
}

impl InputRef {
    fn as_node_name(&self) -> Option<&str> {
        match self {
            InputRef::Direct(name) => Some(name.as_str()),
            InputRef::Path(_) => None,
        }
    }
}

#[derive(Debug, Deserialize)]
struct FlakeLocked {
    #[serde(rename = "type")]
    kind: Option<String>,
    rev: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FlakeOriginal {
    #[serde(rename = "type")]
    kind: Option<String>,
    owner: Option<String>,
    repo: Option<String>,
}

fn read_flake_lock(repo_root: &Path) -> Result<FlakeLock> {
    let path = repo_root.join("flake.lock");
    let bytes =
        std::fs::read(&path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes).with_context(|| format!("failed to parse {}", path.display()))
}

/// Find the consumer flake's direct input that points at
/// `{RELEASE_OWNER}/{RELEASE_REPO}` on GitHub.
///
/// Walks `nodes[<root>].inputs` (the entry node declared by `flake.lock`'s
/// top-level `root` attribute) rather than scanning every node, so a
/// transitive dependency that happens to also depend on `ncrmro/keystone`
/// can't cause us to read the wrong locked revision. Returns the **root
/// input name** (e.g., `"keystone"`) and the resolved node. Errors if zero
/// or multiple root inputs match — the legacy bash probe had the same
/// "exactly one" contract and silent ambiguity would quietly point the
/// menu at an unrelated pin.
fn find_keystone_input(lock: &FlakeLock) -> Result<(String, &FlakeNode)> {
    let root_node = lock
        .nodes
        .get(&lock.root)
        .ok_or_else(|| anyhow!("flake.lock root node '{}' missing", lock.root))?;

    let mut matches: Vec<(String, &FlakeNode)> = Vec::new();
    for (input_name, input_ref) in &root_node.inputs {
        let Some(node_name) = input_ref.as_node_name() else {
            // Skip `follows` paths — those resolve to another input, not a
            // direct GitHub source, so they cannot be the keystone input.
            continue;
        };
        let Some(node) = lock.nodes.get(node_name) else {
            continue;
        };
        let matches_keystone = node
            .original
            .as_ref()
            .map(|o| {
                o.kind.as_deref() == Some("github")
                    && o.owner.as_deref() == Some(RELEASE_OWNER)
                    && o.repo.as_deref() == Some(RELEASE_REPO)
            })
            .unwrap_or(false);
        if matches_keystone {
            matches.push((input_name.clone(), node));
        }
    }

    match matches.len() {
        0 => Err(anyhow!(
            "no root input pins {RELEASE_OWNER}/{RELEASE_REPO} on GitHub"
        )),
        1 => Ok(matches.into_iter().next().unwrap()),
        n => {
            let names: Vec<&str> = matches.iter().map(|(name, _)| name.as_str()).collect();
            Err(anyhow!(
                "found {n} root inputs pinning {RELEASE_OWNER}/{RELEASE_REPO}: {names:?}"
            ))
        }
    }
}

// -----------------------------------------------------------------------------
// Git helpers
// -----------------------------------------------------------------------------

/// Mirror the legacy bash `repo_is_clean` check. Uses
/// `git status --porcelain --untracked-files=normal` so a working tree with
/// untracked files is flagged as dirty — matching the previous behaviour and
/// preventing `ks update` from racing against in-flight local work.
fn git_status_clean(repo_root: &Path) -> bool {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain", "--untracked-files=normal"])
        .output();

    match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().is_empty(),
        _ => false,
    }
}

/// Sortable release-tag key. Field order drives the derived `Ord` over
/// `(major, minor, patch)`. Only strict `v<M>.<m>.<p>` tags parse — any tag
/// carrying a pre-release suffix (`-rc.1`, `-alpha.1`, etc.) is rejected.
#[derive(Debug, Clone, Eq, PartialEq, Ord, PartialOrd)]
struct ReleaseKey {
    major: u32,
    minor: u32,
    patch: u32,
}

/// Parse a release tag of shape `v<M>.<m>.<p>` into a sortable key.
/// Keystone's release pipeline owns the tag shape: strict semver, no
/// pre-release suffix, no build metadata. Anything else yields `None`
/// and is dropped at the call site.
fn parse_release_tag(tag: &str) -> Option<ReleaseKey> {
    let rest = tag.strip_prefix('v')?;
    // Reject anything carrying pre-release (`-`) or build (`+`) suffixes.
    // The release pipeline never emits either, and the menu should not
    // guess at their meaning.
    if rest.contains('-') || rest.contains('+') {
        return None;
    }
    let mut parts = rest.split('.');
    let major: u32 = parts.next()?.parse().ok()?;
    let minor: u32 = parts.next()?.parse().ok()?;
    let patch: u32 = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some(ReleaseKey {
        major,
        minor,
        patch,
    })
}

/// Try to resolve `rev` to a release tag via the local keystone checkout.
/// When multiple release tags point at the same rev, returns the highest
/// one by `ReleaseKey` order.
///
/// Only strict `v<major>.<minor>.<patch>` tags match — unstable tracks
/// `main@<sha>`, not a tag, so on the unstable channel this function's
/// output is informational only (it still surfaces a matching release tag
/// when one happens to point at the currently-locked rev).
///
/// Matches the legacy bash probe's semantics so `current_tag` cannot be
/// set by unrelated tags pointing at the same commit.
fn release_tag_for_rev(rev: &str, _channel: Channel) -> String {
    let keystone_root = match repo::resolve_keystone_repo() {
        Ok(path) => path,
        Err(_) => return String::new(),
    };
    let output = Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["tag", "--points-at", rev])
        .output();
    let raw = match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).to_string(),
        _ => return String::new(),
    };

    raw.lines()
        .map(str::trim)
        .filter_map(|tag| parse_release_tag(tag).map(|ver| (tag.to_string(), ver)))
        .max_by(|a, b| a.1.cmp(&b.1))
        .map(|(tag, _)| tag)
        .unwrap_or_default()
}

fn rev_exists_locally(rev: &str) -> bool {
    let Ok(keystone_root) = repo::resolve_keystone_repo() else {
        return false;
    };
    Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["cat-file", "-e", rev])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn rev_is_ancestor_of(ancestor: &str, descendant: &str) -> bool {
    let Ok(keystone_root) = repo::resolve_keystone_repo() else {
        return false;
    };
    Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["merge-base", "--is-ancestor", ancestor, descendant])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

// -----------------------------------------------------------------------------
// GitHub release fetch
// -----------------------------------------------------------------------------

/// Total budget for any single GitHub API call made by the menu backend.
/// Keep small: Walker calls `ks menu update entries` synchronously on menu
/// open, and a hung fetch stalls the whole desktop menu render. Fail fast
/// and surface an `ErrState` (which renders a visible "Keystone OS
/// unavailable" row) rather than hang.
const GITHUB_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
const GITHUB_CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(5);

/// Build a bounded reqwest client for GitHub API calls. Centralizing so
/// every call site picks up the same timeout + user-agent defaults.
fn github_client() -> Result<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(GITHUB_REQUEST_TIMEOUT)
        .connect_timeout(GITHUB_CONNECT_TIMEOUT)
        .user_agent("ks")
        .build()
        .context("failed to build GitHub reqwest client")
}

/// Normalized release metadata consumed by `load_state`. Both channels
/// produce this shape from a `/branches/<branch>` body — stable from the
/// highest `release/<M>.<m>` line, unstable from `main`. Keeping the
/// extraction pure (in `parse_branch_release`) means unit tests can
/// exercise the full path without an HTTP dep.
///
/// Crate-visible so `cmd::update` can drive the same channel-aware target
/// resolution the menu surfaces.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ReleaseInfo {
    pub(crate) latest_tag: String,
    pub(crate) latest_name: String,
    pub(crate) latest_url: String,
    pub(crate) latest_published: String,
    pub(crate) latest_body: String,
    pub(crate) latest_rev: String,
}

/// Fetch the release metadata for the active channel.
///
/// Both channels track a moving branch tip, so they share one fetch path
/// (`fetch_branch_tip`), which reads the commit SHA inline from
/// `GET /repos/OWNER/REPO/branches/<branch>` — no separate ref-to-sha
/// lookup.
///
/// - Stable resolves the highest `release/<M>.<m>` branch (the stabilized
///   line) via `highest_release_branch`, then reads its tip. When no
///   `release/*` branch is published yet, this errors so the menu renders
///   `Keystone OS unavailable`.
/// - Unstable reads the tip of `main` — the moving development source.
pub(crate) async fn fetch_latest_release(channel: Channel) -> Result<ReleaseInfo> {
    match channel {
        Channel::Stable => fetch_stable_latest_release().await,
        Channel::Unstable => fetch_branch_tip("main").await,
    }
}

async fn fetch_stable_latest_release() -> Result<ReleaseInfo> {
    let branch = highest_release_branch().await?;
    fetch_branch_tip(&branch).await
}

/// Sortable `release/<major>.<minor>` line key. The release line is the
/// branch granularity (`release/1.0`), so patch is not part of the key —
/// patch-level releases are commits *on* the line, not separate branches.
#[derive(Debug, Clone, Copy, Eq, PartialEq, Ord, PartialOrd)]
struct ReleaseLine {
    major: u32,
    minor: u32,
}

/// Parse a `release/<M>.<m>` branch name into a sortable line key. Anything
/// not matching that exact shape (extra components, pre-release/build
/// suffixes, non-numeric parts) yields `None` and is dropped at the call
/// site so an unrelated branch can never masquerade as a release line.
fn parse_release_branch(name: &str) -> Option<ReleaseLine> {
    let rest = name.strip_prefix("release/")?;
    if rest.contains('-') || rest.contains('+') {
        return None;
    }
    let mut parts = rest.split('.');
    let major: u32 = parts.next()?.parse().ok()?;
    let minor: u32 = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some(ReleaseLine { major, minor })
}

/// Pick the highest `release/<M>.<m>` branch from a list of branch names.
/// Returns `None` when no name matches the release-line shape.
fn pick_highest_release_branch(names: &[String]) -> Option<String> {
    names
        .iter()
        .filter_map(|name| parse_release_branch(name).map(|line| (name.clone(), line)))
        .max_by(|a, b| a.1.cmp(&b.1))
        .map(|(name, _)| name)
}

/// Resolve the highest `release/<M>.<m>` branch.
///
/// Uses `GET /git/matching-refs/heads/release/`, which returns *only* refs
/// under `refs/heads/release/` — so unrelated branches can never crowd a
/// release line off a paginated `/branches` listing, and there is nothing to
/// paginate (Keystone carries a handful of release lines at most). Returns an
/// empty array (not 404) when no release branch exists, which maps to the
/// fail-closed "stable line unavailable" error.
async fn highest_release_branch() -> Result<String> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/git/matching-refs/heads/release/",
        RELEASE_OWNER, RELEASE_REPO
    );
    let mut req = github_client()?
        .get(&url)
        .header("Accept", "application/vnd.github+json");
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        if !token.is_empty() {
            req = req.header("Authorization", format!("Bearer {token}"));
        }
    }
    let response = req.send().await.context("GitHub request failed")?;
    let json: Value = response
        .error_for_status()
        .context("GitHub returned non-success status")?
        .json()
        .await
        .context("GitHub response was not valid JSON")?;
    let names: Vec<String> = json
        .as_array()
        .ok_or_else(|| anyhow!("GitHub matching-refs response was not an array"))?
        .iter()
        .filter_map(|r| {
            r.get("ref")
                .and_then(|v| v.as_str())
                .and_then(|r| r.strip_prefix("refs/heads/"))
                .map(str::to_string)
        })
        .collect();
    pick_highest_release_branch(&names).ok_or_else(|| {
        anyhow!(
            "no release/<major>.<minor> branch is published yet — the stable line is unavailable"
        )
    })
}

/// Read the tip commit of `branch` from
/// `GET /repos/OWNER/REPO/branches/<branch>`. The response carries the
/// commit SHA inline, so no separate ref-to-sha lookup is needed. Shared by
/// both channels: stable passes the resolved `release/<M>.<m>` branch,
/// unstable passes `main`. The response shape:
///   { "name": "<branch>",
///     "commit": { "sha": "...",
///                 "html_url": "...",
///                 "commit": { "committer": {"date": "..."},
///                             "message": "..." } } }
async fn fetch_branch_tip(branch: &str) -> Result<ReleaseInfo> {
    // The branch name is interpolated with its literal `/` (e.g.
    // `release/1.0`). GitHub's `/branches/{branch}` endpoint matches the
    // slashed remainder of the path greedily, so a slashed name resolves
    // unencoded — percent-encoding the slash as `%2F` would instead 404.
    let url = format!(
        "https://api.github.com/repos/{}/{}/branches/{}",
        RELEASE_OWNER, RELEASE_REPO, branch
    );
    let mut req = github_client()?
        .get(&url)
        .header("Accept", "application/vnd.github+json");
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        if !token.is_empty() {
            req = req.header("Authorization", format!("Bearer {token}"));
        }
    }
    let response = req.send().await.context("GitHub request failed")?;
    let json: Value = response
        .error_for_status()
        .context("GitHub returned non-success status")?
        .json()
        .await
        .context("GitHub response was not valid JSON")?;
    parse_branch_release(&json, branch)
}

/// Pure extraction: map a `/branches/<branch>` body into `ReleaseInfo`. The
/// `latest_tag`/`latest_name` carry the branch label (`main`,
/// `release/1.0`) and its short sha — branch tracking has no tag to name.
/// Errors only when the commit SHA is missing, since without it the menu
/// cannot compare against the locked rev.
fn parse_branch_release(json: &Value, branch: &str) -> Result<ReleaseInfo> {
    let commit = json
        .get("commit")
        .ok_or_else(|| anyhow!("GitHub branch response missing 'commit' object"))?;
    let sha = commit
        .get("sha")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("GitHub branch response missing 'commit.sha'"))?
        .to_string();
    // `html_url` points at the commit on GitHub; fall back to the branch
    // tree view when the field is absent so the menu always has a link.
    let latest_url = commit
        .get("html_url")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .unwrap_or_else(|| {
            format!(
                "https://github.com/{}/{}/tree/{}",
                RELEASE_OWNER, RELEASE_REPO, branch
            )
        });
    let inner = commit.get("commit");
    let latest_published = inner
        .and_then(|c| c.get("committer"))
        .and_then(|c| c.get("date"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let message = inner
        .and_then(|c| c.get("message"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    // Display the first paragraph of the commit message (typically the
    // subject line) so the preview pane stays compact. `str::split_once`
    // on a blank-line separator matches the conventional commit shape.
    let latest_body = message
        .split_once("\n\n")
        .map(|(head, _)| head)
        .unwrap_or(&message)
        .trim()
        .to_string();
    let latest_body = if latest_body.is_empty() {
        "No commit message.".to_string()
    } else {
        latest_body
    };
    Ok(ReleaseInfo {
        latest_tag: branch.to_string(),
        latest_name: format!("{branch}@{}", short(&sha)),
        latest_url,
        latest_published,
        latest_body,
        latest_rev: sha,
    })
}

/// Thin wrapper retained for the unstable channel's `main` tracking and the
/// existing parse tests. Equivalent to `parse_branch_release(json, "main")`.
fn parse_unstable_branch(json: &Value) -> Result<ReleaseInfo> {
    parse_branch_release(json, "main")
}

// -----------------------------------------------------------------------------
// Host key resolution
// -----------------------------------------------------------------------------

/// Local-only precondition check used by dispatch to close the TOCTOU
/// window between entries-render and activation. Returns `Ok(())` when
/// the menu's update action can proceed, or `Err(reason)` with the same
/// user-facing text `load_state` would produce for the same failure
/// mode. Does **not** fetch from GitHub — `latest_tag` is stale by design
/// between render and dispatch, and a network hiccup should not block a
/// user whose local state is actually fine.
fn evaluate_local_gate(flake_override: Option<&Path>) -> Result<(), String> {
    let repo_root = repo::find_repo(flake_override)
        .map_err(|_| "Unable to locate the active system flake.".to_string())?;

    if !repo_root.join("flake.lock").exists() {
        return Err("The active system flake has no flake.lock.".into());
    }

    let lock =
        read_flake_lock(&repo_root).map_err(|err| format!("Unable to read flake.lock: {err}"))?;

    find_keystone_input(&lock).map_err(|err| {
        format!("Unable to find a Keystone GitHub input in the active system flake: {err}")
    })?;

    if !git_status_clean(&repo_root) {
        return Err("The active system flake has uncommitted changes.".into());
    }

    Ok(())
}

async fn current_host_key(repo_root: &Path) -> Option<String> {
    match repo::resolve_current_host(repo_root).await {
        Ok(Some(host)) => Some(host),
        _ => None,
    }
}

// -----------------------------------------------------------------------------
// State orchestration
// -----------------------------------------------------------------------------

async fn load_state(flake_override: Option<&Path>) -> MenuState {
    // Resolve once at the top so every MenuState::Err branch agrees on
    // which channel the user attempted — avoids a whole-function signature
    // sprawl and keeps the channel-aware error branches trivial.
    let channel = Channel::current();
    let channel_str = channel.as_str().to_string();

    let repo_root = match repo::find_repo(flake_override) {
        Ok(path) => path,
        Err(_) => {
            return MenuState::Err(ErrState {
                ok: false,
                channel: channel_str,
                error: "Unable to locate the active system flake.".into(),
                ..Default::default()
            });
        }
    };

    let repo_root_str = repo_root.display().to_string();

    if !repo_root.join("flake.lock").exists() {
        return MenuState::Err(ErrState {
            ok: false,
            channel: channel_str,
            repo_root: Some(repo_root_str),
            error: "The active system flake has no flake.lock.".into(),
            ..Default::default()
        });
    }

    let lock = match read_flake_lock(&repo_root) {
        Ok(lock) => lock,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                channel: channel_str,
                repo_root: Some(repo_root_str),
                error: format!("Unable to read flake.lock: {err}"),
                ..Default::default()
            });
        }
    };

    let (input_name, node) = match find_keystone_input(&lock) {
        Ok(pair) => pair,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                channel: channel_str,
                repo_root: Some(repo_root_str),
                error: format!(
                    "Unable to find a Keystone GitHub input in the active system flake: {err}"
                ),
                ..Default::default()
            });
        }
    };

    let Some(locked) = node.locked.as_ref() else {
        return MenuState::Err(ErrState {
            ok: false,
            channel: channel_str,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            error: "The Keystone input has no locked revision.".into(),
            ..Default::default()
        });
    };

    if locked.kind.as_deref() != Some("github") {
        return MenuState::Err(ErrState {
            ok: false,
            channel: channel_str,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            error: "The Keystone input is not locked to a GitHub source.".into(),
            ..Default::default()
        });
    }

    let Some(current_rev) = locked.rev.clone() else {
        return MenuState::Err(ErrState {
            ok: false,
            channel: channel_str,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            error: "Unable to read the locked Keystone revision from flake.lock.".into(),
            ..Default::default()
        });
    };

    let current_tag = release_tag_for_rev(&current_rev, channel);
    let dirty = !git_status_clean(&repo_root);

    let release = match fetch_latest_release(channel).await {
        Ok(r) => r,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                channel: channel_str,
                repo_root: Some(repo_root_str),
                input_name: Some(input_name),
                current_rev: Some(current_rev),
                current_tag: Some(current_tag),
                dirty: Some(dirty),
                error: format!("Unable to fetch the latest Keystone release from GitHub: {err}"),
                ..Default::default()
            });
        }
    };

    let ReleaseInfo {
        latest_tag,
        latest_name,
        latest_url,
        latest_published,
        latest_body,
        latest_rev,
    } = release;

    let host_key = current_host_key(&repo_root).await.unwrap_or_default();

    let (status_kind, status_summary) = if current_rev == latest_rev {
        (
            "up-to-date",
            "Locked release matches the latest published Keystone release.",
        )
    } else if !current_tag.is_empty() {
        ("behind", "A newer Keystone release is available on GitHub.")
    } else if rev_exists_locally(&current_rev)
        && rev_exists_locally(&latest_rev)
        && rev_is_ancestor_of(&latest_rev, &current_rev)
    {
        (
            "ahead",
            "The locked revision is newer than the latest published Keystone release.",
        )
    } else {
        (
            "behind",
            "The locked revision does not match the latest published Keystone release.",
        )
    };

    // `host_key` is retained for state inspection (surfaced by
    // `ks menu update status`) but is no longer a gating precondition for
    // offering the update entry. The dispatch path is `ks update` with no
    // explicit host, and ks resolves the current host on its own via the
    // keystone-system-flake pointer — so a hosts.nix that can't be read
    // here would still succeed at deploy time, and blocking the menu purely
    // on that lookup would produce spurious "Update unavailable" entries.
    let mut update_allowed = false;
    let update_reason = match status_kind {
        "behind" => {
            if dirty {
                "The active system flake has uncommitted changes.".to_string()
            } else {
                update_allowed = true;
                String::new()
            }
        }
        "up-to-date" => "The current host already uses the latest Keystone release.".to_string(),
        _ => "The current lock is newer than the latest published release, so Walker will not downgrade it automatically.".to_string(),
    };

    MenuState::Ok(OkState {
        ok: true,
        channel: channel_str,
        repo_root: repo_root_str,
        input_name,
        current_rev,
        current_tag,
        latest_tag,
        latest_name,
        latest_url,
        latest_published,
        latest_body,
        latest_rev,
        host_key,
        status_kind: status_kind.to_string(),
        status_summary: status_summary.to_string(),
        update_reason,
        dirty,
        update_allowed,
    })
}

// -----------------------------------------------------------------------------
// Rendering
// -----------------------------------------------------------------------------

/// Short sha: first 7 chars, handling short revs gracefully.
fn short(rev: &str) -> &str {
    if rev.len() >= 7 {
        &rev[..7]
    } else {
        rev
    }
}

fn render_preview_summary(state: &MenuState) -> String {
    match state {
        MenuState::Ok(s) => {
            let current_label = if !s.current_tag.is_empty() {
                s.current_tag.clone()
            } else {
                short(&s.current_rev).to_string()
            };
            let update_line = if s.update_allowed {
                "Update command: ks update".to_string()
            } else {
                format!("Update: {}", s.update_reason)
            };
            [
                "Keystone OS update status".to_string(),
                String::new(),
                // Surface the channel near the top so users inspecting
                // `ks menu update preview-summary` can immediately see
                // which release feed produced `latest_*`.
                format!("Channel: {}", s.channel),
                format!("Consumer flake: {}", s.repo_root),
                format!("Input: {}", s.input_name),
                format!("Current: {} ({})", current_label, short(&s.current_rev)),
                format!("Latest: {} ({})", s.latest_tag, short(&s.latest_rev)),
                format!("Status: {}", s.status_summary),
                update_line,
            ]
            .join("\n")
        }
        MenuState::Err(e) => {
            // Even the error path should disclose which channel was
            // attempted — useful when "Keystone OS unavailable" is actually
            // "branches/main returned 404 on unstable" and the user wants
            // to flip to stable.
            let mut lines: Vec<String> =
                vec!["Keystone OS update unavailable".to_string(), String::new()];
            if !e.channel.is_empty() {
                lines.push(format!("Channel: {}", e.channel));
                lines.push(String::new());
            }
            lines.push(e.error.clone());
            lines.join("\n")
        }
    }
}

fn render_preview_release_notes(state: &MenuState) -> String {
    match state {
        MenuState::Ok(s) => {
            let published = if s.latest_published.is_empty() {
                "Published: unknown".to_string()
            } else {
                format!("Published: {}", s.latest_published)
            };
            let name = if s.latest_name.is_empty() {
                s.latest_tag.clone()
            } else {
                s.latest_name.clone()
            };
            [
                name,
                format!("Ref: {}", s.latest_tag),
                published,
                String::new(),
                s.latest_body.clone(),
                String::new(),
                s.latest_url.clone(),
            ]
            .join("\n")
        }
        MenuState::Err(e) => {
            // Try to surface whatever release context we have even in the
            // partial-error case so the preview pane is useful.
            if let Some(latest_tag) = &e.latest_tag {
                let name = e.latest_name.clone().unwrap_or_else(|| latest_tag.clone());
                let published = e
                    .latest_published
                    .clone()
                    .filter(|s| !s.is_empty())
                    .map(|s| format!("Published: {s}"))
                    .unwrap_or_else(|| "Published: unknown".into());
                let body = e
                    .latest_body
                    .clone()
                    .unwrap_or_else(|| "No release notes available.".into());
                let url = e.latest_url.clone().unwrap_or_default();
                return [
                    name,
                    format!("Ref: {latest_tag}"),
                    published,
                    String::new(),
                    body,
                    String::new(),
                    url,
                ]
                .join("\n");
            }
            ["Keystone release notes unavailable", "", &e.error].join("\n")
        }
    }
}

// -----------------------------------------------------------------------------
// Activation values
// -----------------------------------------------------------------------------
//
// Walker's Lua provider single-quotes `%VALUE%` into a shell command. Free-
// form text containing a single quote, backslash, or control character would
// either break shell quoting or let an attacker inject into the dispatch
// argv. The activation values below are restricted to a fixed set of tokens
// so the Lua layer stays quoting-safe without encoding/decoding.
//
// For actions that carry a payload (currently only `open-release-page`), the
// payload must either:
//   (a) be a well-formed URL with no single quotes / whitespace, or
//   (b) be a stable tag that `dispatch` looks up fresh from `load_state`.
//
// Free-form error or reason strings MUST NOT be embedded in Values —
// `dispatch` re-reads state when it needs to render the text.

/// Activation tokens. Keep these stable; the Lua provider file and any
/// external callers rely on them being shell-safe single words.
const ACT_NOOP: &str = "noop";
const ACT_RUN_UPDATE: &str = "run-update";
const ACT_BLOCKED_UPDATE: &str = "blocked-update-unavailable";
const ACT_BLOCKED_KEYSTONE: &str = "blocked-keystone-unavailable";
const ACT_OPEN_RELEASE: &str = "open-release-page";

/// A URL is considered shell-safe for Walker dispatch if it contains only
/// characters that are always literal under both single-quote and no-quote
/// shell parsing: ASCII letters, digits, and a small set of URL punctuation.
/// GitHub release URLs always satisfy this; anything outside the allowlist
/// falls back to an empty value so the entry is filtered instead of
/// risking a quoting break.
fn url_is_shell_safe(url: &str) -> bool {
    !url.is_empty()
        && url.chars().all(|c| {
            c.is_ascii_alphanumeric()
                || matches!(
                    c,
                    ':' | '/' | '.' | '-' | '_' | '~' | '%' | '?' | '=' | '&' | '#' | '+'
                )
        })
}

fn render_entries_json(state: &MenuState) -> Result<String> {
    let entries: Vec<Value> = match state {
        MenuState::Ok(s) => {
            let current_label = if !s.current_tag.is_empty() {
                s.current_tag.clone()
            } else {
                short(&s.current_rev).to_string()
            };
            let mut entries = vec![serde_json::json!({
                "Text": format!("Current: {}", current_label),
                "Subtext": s.status_summary,
                "Value": ACT_NOOP,
                "Icon": "dialog-information-symbolic",
                "Preview": "ks menu update preview-summary",
                "PreviewType": "command",
            })];
            if url_is_shell_safe(&s.latest_url) {
                // Both channels track a moving branch tip, so the row links
                // to that tip commit and the subtext names the branch
                // (`main`, `release/1.0`) and channel. `latest_tag` carries
                // the branch label for both channels; naming the channel
                // keeps a flipped host visibly distinct from the stable line.
                let subtext = format!("Latest commit on {} ({} channel)", s.latest_tag, s.channel);
                entries.push(serde_json::json!({
                    "Text": format!("Latest: {}", s.latest_tag),
                    "Subtext": subtext,
                    "Value": format!("{ACT_OPEN_RELEASE}\t{}", s.latest_url),
                    "Icon": "software-update-available-symbolic",
                    "Preview": "ks menu update preview-release-notes",
                    "PreviewType": "command",
                }));
            }
            if s.update_allowed {
                entries.push(serde_json::json!({
                    "Text": "Update current host",
                    // Don't promise that `ks update` lands the host exactly on
                    // `latest_tag` — it relocks the consumer flake's inputs
                    // and the result may advance past the published release
                    // depending on how the input is configured. Describe the
                    // action, not the target revision.
                    "Subtext": "Run ks update to relock inputs and update this host",
                    "Value": ACT_RUN_UPDATE,
                    "Icon": "system-software-update-symbolic",
                    "Preview": "ks menu update preview-summary",
                    "PreviewType": "command",
                }));
            } else {
                entries.push(serde_json::json!({
                    "Text": "Update unavailable",
                    "Subtext": s.update_reason,
                    "Value": ACT_BLOCKED_UPDATE,
                    "Icon": "dialog-warning-symbolic",
                    "Preview": "ks menu update preview-summary",
                    "PreviewType": "command",
                }));
            }
            entries
        }
        MenuState::Err(e) => vec![serde_json::json!({
            "Text": "Keystone OS unavailable",
            "Subtext": e.error,
            "Value": ACT_BLOCKED_KEYSTONE,
            "Icon": "dialog-warning-symbolic",
            "Preview": "ks menu update preview-summary",
            "PreviewType": "command",
        })],
    };
    serde_json::to_string(&entries).context("failed to serialize entries")
}

// -----------------------------------------------------------------------------
// Dispatch
// -----------------------------------------------------------------------------

fn run_notify_send(summary: &str, body: &str) -> Result<()> {
    // `--` stops notify-send's option parsing so a summary / body that
    // starts with `-` (e.g., a reason string carrying a CLI flag) isn't
    // misread as a flag.
    let status = Command::new("notify-send")
        .args(["--app-name=Keystone", "--", summary, body])
        .status()
        .context("failed to invoke notify-send")?;
    if !status.success() {
        anyhow::bail!("notify-send exited with status {:?}", status.code());
    }
    Ok(())
}

fn xdg_open_detached(url: &str) -> Result<()> {
    // Spawn xdg-open and detach so Walker's dispatch process can exit.
    Command::new("xdg-open")
        .arg(url)
        .spawn()
        .context("failed to spawn xdg-open")?;
    Ok(())
}

fn command_or_name(name: &str) -> PathBuf {
    super::util::find_executable(name).unwrap_or_else(|| PathBuf::from(name))
}

fn update_session_command_with_paths(
    ks_bin: &Path,
    flake: Option<&Path>,
    uwsm: Option<PathBuf>,
    systemd_inhibit: PathBuf,
    systemd_cat: PathBuf,
) -> (PathBuf, Vec<OsString>) {
    let mut inner_args = vec![
        OsString::from("--what=sleep:shutdown:idle"),
        OsString::from("--why=Keystone OS update in progress"),
        OsString::from("--mode=block"),
        systemd_cat.into_os_string(),
        OsString::from("--identifier=ks-update"),
        ks_bin.as_os_str().to_os_string(),
        OsString::from("update"),
        OsString::from("--approve"),
    ];
    if let Some(flake_path) = flake {
        inner_args.push(OsString::from("--flake"));
        inner_args.push(flake_path.as_os_str().to_os_string());
    }

    match uwsm {
        Some(uwsm_bin) => {
            let mut args = vec![
                OsString::from("app"),
                OsString::from("--"),
                systemd_inhibit.into_os_string(),
            ];
            args.extend(inner_args);
            (uwsm_bin, args)
        }
        None => (systemd_inhibit, inner_args),
    }
}

fn update_session_command(
    ks_bin: &Path,
    flake: Option<&Path>,
    uwsm: Option<PathBuf>,
) -> (PathBuf, Vec<OsString>) {
    update_session_command_with_paths(
        ks_bin,
        flake,
        uwsm,
        command_or_name("systemd-inhibit"),
        command_or_name("systemd-cat"),
    )
}

/// Launch the update flow as a graphical-session app so `pkexec` can talk to
/// the desktop polkit agent instead of falling back to the broken user-service
/// `/dev/tty` path.
fn start_update_session(flake: Option<&Path>) -> Result<()> {
    let ks_bin = env::current_exe().context("failed to resolve current ks executable")?;
    let (program, args) =
        update_session_command(&ks_bin, flake, super::util::find_executable("uwsm"));

    Command::new(&program)
        .args(&args)
        .env("KS_UPDATE_NOTIFY", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("failed to spawn session update via {}", program.display()))?;
    Ok(())
}

/// Look up the current blocker text from fresh state. Called when the user
/// activates a blocked-* token and we need to render a meaningful notification
/// without having embedded the reason in the activation value.
async fn blocked_update_notification(flake: Option<&Path>) -> (String, String) {
    let state = load_state(flake).await;
    match &state {
        MenuState::Ok(s) if !s.update_allowed => (
            "Keystone update unavailable".to_string(),
            if s.update_reason.is_empty() {
                s.status_summary.clone()
            } else {
                s.update_reason.clone()
            },
        ),
        MenuState::Ok(_) => (
            "Keystone update unavailable".to_string(),
            "Status changed since the menu was rendered — open the Update menu to refresh."
                .to_string(),
        ),
        MenuState::Err(e) => ("Keystone OS unavailable".to_string(), e.error.clone()),
    }
}

async fn blocked_keystone_notification(flake: Option<&Path>) -> (String, String) {
    let state = load_state(flake).await;
    match &state {
        MenuState::Err(e) => ("Keystone OS unavailable".to_string(), e.error.clone()),
        MenuState::Ok(_) => (
            "Keystone OS unavailable".to_string(),
            "Status recovered — reopen the Update menu to refresh.".to_string(),
        ),
    }
}

async fn dispatch(value: &str, flake: Option<&Path>) -> Result<()> {
    // Activation values are restricted to a small set of stable tokens
    // (see the Activation values section above). `open-release-page` is the
    // only action that carries a payload, and its payload is a URL that has
    // already passed `url_is_shell_safe` at entries-render time.
    let mut parts = value.splitn(2, '\t');
    let action = parts.next().unwrap_or("");
    let payload = parts.next().unwrap_or("");

    match action {
        "" | ACT_NOOP => Ok(()),
        ACT_BLOCKED_UPDATE => {
            let (title, body) = blocked_update_notification(flake).await;
            run_notify_send(&title, &body)
        }
        ACT_BLOCKED_KEYSTONE => {
            let (title, body) = blocked_keystone_notification(flake).await;
            run_notify_send(&title, &body)
        }
        ACT_OPEN_RELEASE => {
            if !url_is_shell_safe(payload) {
                anyhow::bail!("open-release-page payload failed safety check");
            }
            xdg_open_detached(payload)
        }
        ACT_RUN_UPDATE => {
            // Close the TOCTOU window between entries-render and click: if
            // the user dirtied the tree after opening the menu, refuse
            // before launching the session update (otherwise the approval
            // round-trip ends with `ks update` failing — strictly worse
            // UX than refusing up front with the same reason).
            match evaluate_local_gate(flake) {
                Ok(()) => start_update_session(flake).or_else(|err| {
                    run_notify_send("Keystone update failed to start", &err.to_string())
                }),
                Err(reason) => run_notify_send("Keystone update unavailable", &reason),
            }
        }
        other => Err(anyhow!("unknown update menu action: {other}")),
    }
}

// -----------------------------------------------------------------------------
// Subcommand entry
// -----------------------------------------------------------------------------

#[derive(Debug, clap::Subcommand)]
pub enum UpdateMenuCommand {
    /// Emit the raw state JSON used by the other subcommands.
    Status,
    /// Emit the Walker entry array as JSON.
    Entries,
    /// Emit the plain-text summary preview pane.
    PreviewSummary,
    /// Emit the plain-text release-notes preview pane.
    PreviewReleaseNotes,
    /// Handle a Walker activation value.
    Dispatch {
        /// Activation value, possibly tab-separated for multi-arg actions.
        #[arg(default_value = "")]
        value: String,
    },
}

pub async fn execute(cmd: UpdateMenuCommand, flake: Option<&Path>) -> Result<()> {
    match cmd {
        UpdateMenuCommand::Status => {
            let state = load_state(flake).await;
            println!("{}", serde_json::to_string_pretty(&state)?);
            Ok(())
        }
        UpdateMenuCommand::Entries => {
            let state = load_state(flake).await;
            println!("{}", render_entries_json(&state)?);
            Ok(())
        }
        UpdateMenuCommand::PreviewSummary => {
            let state = load_state(flake).await;
            println!("{}", render_preview_summary(&state));
            Ok(())
        }
        UpdateMenuCommand::PreviewReleaseNotes => {
            let state = load_state(flake).await;
            println!("{}", render_preview_release_notes(&state));
            Ok(())
        }
        UpdateMenuCommand::Dispatch { value } => dispatch(&value, flake).await,
    }
}

// Silence dead-code warnings for helpers the linter may not see from tests
// elsewhere in the crate.
#[allow(dead_code)]
fn _keep(_: &PathBuf) {}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // Models a stable branch-tracking state: the consumer lock sits at an
    // older commit on the `release/1.0` line, and the latest is that line's
    // newer tip. `current_tag` is empty because a branch-tracking lock is
    // pinned to a commit, not a tag.
    fn ok_fixture() -> OkState {
        OkState {
            ok: true,
            channel: "stable".into(),
            repo_root: "/etc/nixos-config".into(),
            input_name: "keystone".into(),
            current_rev: "aaaaaaaabbbbbbbbccccccccddddddddeeeeeeee".into(),
            current_tag: String::new(),
            latest_tag: "release/1.0".into(),
            latest_name: "release/1.0@bbbbbbb".into(),
            latest_url:
                "https://github.com/ncrmro/keystone/commit/bbbbbbbbccccccccddddddddeeeeeeeeffffffff"
                    .into(),
            latest_published: "2026-04-01T10:00:00Z".into(),
            latest_body: "feat(menu): add Walker update menu".into(),
            latest_rev: "bbbbbbbbccccccccddddddddeeeeeeeeffffffff".into(),
            host_key: "mox".into(),
            status_kind: "behind".into(),
            status_summary: "A newer Keystone release is available on GitHub.".into(),
            update_reason: String::new(),
            dirty: false,
            update_allowed: true,
        }
    }

    fn key(major: u32, minor: u32, patch: u32) -> ReleaseKey {
        ReleaseKey {
            major,
            minor,
            patch,
        }
    }

    #[test]
    fn parse_release_tag_accepts_plain_semver() {
        assert_eq!(parse_release_tag("v0.8.0"), Some(key(0, 8, 0)));
        assert_eq!(parse_release_tag("v1.2.3"), Some(key(1, 2, 3)));
        assert_eq!(parse_release_tag("v10.20.300"), Some(key(10, 20, 300)));
    }

    #[test]
    fn parse_release_tag_rejects_malformed_shapes() {
        // Keystone's release pipeline emits strict `v<M>.<m>.<p>` tags only.
        // Any pre-release suffix, build metadata, over-long triple, or
        // missing-`v` form must be rejected so `current_tag` cannot be
        // populated by an unrelated tag that happens to point at the same
        // commit.
        assert_eq!(parse_release_tag("v1.2.3-rc.1"), None);
        assert_eq!(parse_release_tag("v1.2.3-foo"), None);
        assert_eq!(parse_release_tag("v1.2.3-alpha.1"), None);
        assert_eq!(parse_release_tag("v1.2.3+build.42"), None);
        assert_eq!(parse_release_tag("v1.2.3.4"), None);
        assert_eq!(parse_release_tag("1.2.3"), None);
        assert_eq!(parse_release_tag("v1.2"), None);
    }

    #[test]
    fn parse_release_tag_rejects_non_release_names() {
        assert_eq!(parse_release_tag("prod"), None);
        assert_eq!(parse_release_tag("release-candidate"), None);
        assert_eq!(parse_release_tag(""), None);
        assert_eq!(parse_release_tag("v"), None);
        assert_eq!(parse_release_tag("vAbC.1.2"), None);
    }

    #[test]
    fn parse_release_branch_accepts_release_lines() {
        assert_eq!(
            parse_release_branch("release/1.0"),
            Some(ReleaseLine { major: 1, minor: 0 })
        );
        assert_eq!(
            parse_release_branch("release/2.11"),
            Some(ReleaseLine {
                major: 2,
                minor: 11
            })
        );
        assert_eq!(
            parse_release_branch("release/10.4"),
            Some(ReleaseLine {
                major: 10,
                minor: 4
            })
        );
    }

    #[test]
    fn parse_release_branch_rejects_non_release_lines() {
        // Only `release/<M>.<m>` matches. Patch-level (`release/1.0.1`),
        // suffixed, prefix-mismatched, or non-numeric names are dropped so
        // an unrelated branch never masquerades as a release line.
        assert_eq!(parse_release_branch("main"), None);
        assert_eq!(parse_release_branch("release/1"), None);
        assert_eq!(parse_release_branch("release/1.0.1"), None);
        assert_eq!(parse_release_branch("release/1.0-rc.1"), None);
        assert_eq!(parse_release_branch("release/1.x"), None);
        assert_eq!(parse_release_branch("releases/1.0"), None);
        assert_eq!(parse_release_branch("feat/release/1.0"), None);
        assert_eq!(parse_release_branch(""), None);
    }

    #[test]
    fn pick_highest_release_branch_orders_numerically() {
        // String ordering would rank "release/1.9" above "release/1.10";
        // the numeric key must not. Non-release branches are ignored.
        let names: Vec<String> = [
            "main",
            "release/1.0",
            "release/1.9",
            "release/1.10",
            "release/2.0",
            "feat/x",
            "dependabot/nix/foo",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        assert_eq!(
            pick_highest_release_branch(&names),
            Some("release/2.0".to_string())
        );
    }

    #[test]
    fn pick_highest_release_branch_none_when_no_release_line() {
        let names: Vec<String> = ["main", "feat/x", "dependabot/nix/foo"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(pick_highest_release_branch(&names), None);
    }

    #[test]
    fn parse_branch_release_labels_release_branch() {
        // The stable channel passes a `release/<M>.<m>` branch; the parsed
        // info must carry that branch as the ref label and `<branch>@<sha>`
        // as the display name.
        let sha = "ccddeeff00112233445566778899aabbccddeeff";
        let payload = serde_json::json!({
            "name": "release/1.0",
            "commit": {
                "sha": sha,
                "html_url": format!("https://github.com/ncrmro/keystone/commit/{sha}"),
                "commit": {
                    "committer": { "date": "2026-06-10T09:00:00Z" },
                    "message": "fix(desktop): backported stabilization fix",
                }
            }
        });
        let info = parse_branch_release(&payload, "release/1.0").unwrap();
        assert_eq!(info.latest_tag, "release/1.0");
        assert_eq!(info.latest_name, format!("release/1.0@{}", &sha[..7]));
        assert_eq!(info.latest_rev, sha);
    }

    #[test]
    fn parse_branch_release_tree_url_fallback_uses_branch() {
        // A missing `commit.html_url` must fall back to the *branch* tree
        // view, not a hardcoded `main`, so the stable line links correctly.
        let payload = serde_json::json!({
            "name": "release/1.0",
            "commit": {
                "sha": "0000000000000000000000000000000000000003",
                "commit": { "committer": { "date": "2026-06-10T09:00:00Z" }, "message": "x" }
            }
        });
        let info = parse_branch_release(&payload, "release/1.0").unwrap();
        assert_eq!(
            info.latest_url,
            "https://github.com/ncrmro/keystone/tree/release/1.0"
        );
    }

    #[test]
    fn short_returns_first_seven_chars() {
        assert_eq!(short("aaaaaaaabbbbbbbbccccccccddddddddeeeeeeee"), "aaaaaaa");
        assert_eq!(short("abc"), "abc");
        assert_eq!(short(""), "");
    }

    #[test]
    fn update_session_command_uses_uwsm_and_journald_when_available() {
        let (program, args) = update_session_command_with_paths(
            Path::new("/run/current-system/sw/bin/ks"),
            Some(Path::new("/tmp/test flake")),
            Some(PathBuf::from("/run/current-system/sw/bin/uwsm")),
            PathBuf::from("/run/current-system/sw/bin/systemd-inhibit"),
            PathBuf::from("/run/current-system/sw/bin/systemd-cat"),
        );
        let rendered: Vec<String> = args
            .iter()
            .map(|arg| arg.to_string_lossy().into_owned())
            .collect();
        assert_eq!(program, PathBuf::from("/run/current-system/sw/bin/uwsm"));
        assert_eq!(
            rendered[0..3],
            ["app", "--", "/run/current-system/sw/bin/systemd-inhibit"]
        );
        assert!(rendered.contains(&"--identifier=ks-update".to_string()));
        assert!(rendered.contains(&"/run/current-system/sw/bin/ks".to_string()));
        assert!(rendered.contains(&"--approve".to_string()));
        assert!(rendered.contains(&"--flake".to_string()));
        assert!(rendered.contains(&"/tmp/test flake".to_string()));
    }

    #[test]
    fn update_session_command_falls_back_without_uwsm() {
        let (program, args) = update_session_command_with_paths(
            Path::new("/run/current-system/sw/bin/ks"),
            None,
            None,
            PathBuf::from("/run/current-system/sw/bin/systemd-inhibit"),
            PathBuf::from("/run/current-system/sw/bin/systemd-cat"),
        );
        let rendered: Vec<String> = args
            .iter()
            .map(|arg| arg.to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            program,
            PathBuf::from("/run/current-system/sw/bin/systemd-inhibit")
        );
        assert!(rendered.contains(&"--identifier=ks-update".to_string()));
        assert!(rendered.contains(&"/run/current-system/sw/bin/ks".to_string()));
    }

    // CRITICAL: env mutation is process-global; serialise KS_UPDATE_CHANNEL
    // guard usage with a mutex so parallel tests don't observe each other's
    // env state. Same pattern as SKIP_NIX_EVAL_LOCK in repo.rs.
    static CHANNEL_ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    struct ChannelEnvGuard {
        _lock: std::sync::MutexGuard<'static, ()>,
        prior: Option<String>,
        prior_file: Option<std::ffi::OsString>,
        _tempdir: tempfile::TempDir,
    }
    impl ChannelEnvGuard {
        fn new(value: Option<&str>) -> Self {
            let lock = CHANNEL_ENV_LOCK.lock().unwrap_or_else(|p| p.into_inner());
            let prior = std::env::var("KS_UPDATE_CHANNEL").ok();
            let prior_file = std::env::var_os("KEYSTONE_UPDATE_CHANNEL_FILE");
            let tempdir = tempfile::tempdir().expect("temp runtime dir");
            let runtime_file = tempdir.path().join("keystone-update-channel");
            std::env::set_var("KEYSTONE_UPDATE_CHANNEL_FILE", &runtime_file);
            match value {
                Some(v) => std::env::set_var("KS_UPDATE_CHANNEL", v),
                None => std::env::remove_var("KS_UPDATE_CHANNEL"),
            }
            Self {
                _lock: lock,
                prior,
                prior_file,
                _tempdir: tempdir,
            }
        }
    }
    impl Drop for ChannelEnvGuard {
        fn drop(&mut self) {
            match self.prior.as_deref() {
                Some(v) => std::env::set_var("KS_UPDATE_CHANNEL", v),
                None => std::env::remove_var("KS_UPDATE_CHANNEL"),
            }
            match self.prior_file.as_deref() {
                Some(v) => std::env::set_var("KEYSTONE_UPDATE_CHANNEL_FILE", v),
                None => std::env::remove_var("KEYSTONE_UPDATE_CHANNEL_FILE"),
            }
        }
    }

    #[test]
    fn channel_current_defaults_to_stable() {
        let _guard = ChannelEnvGuard::new(None);
        assert_eq!(Channel::current(), Channel::Stable);
        assert_eq!(Channel::current().as_str(), "stable");
    }

    #[test]
    fn channel_current_reads_unstable_env() {
        let _guard = ChannelEnvGuard::new(Some("unstable"));
        assert_eq!(Channel::current(), Channel::Unstable);
        assert_eq!(Channel::current().as_str(), "unstable");
    }

    #[test]
    fn channel_current_reads_runtime_file_when_env_missing() {
        let _guard = ChannelEnvGuard::new(None);
        let path = std::env::var("KEYSTONE_UPDATE_CHANNEL_FILE").unwrap();
        std::fs::write(path, "unstable\n").unwrap();
        assert_eq!(Channel::current(), Channel::Unstable);
        assert_eq!(Channel::current().as_str(), "unstable");
    }

    #[test]
    fn channel_current_rejects_unknown_value() {
        // Fail-closed: any value other than exactly "unstable" maps to
        // Stable. A misconfigured env never silently flips a host onto
        // the moving-main source. Verifies the guarantee across the usual
        // suspects: empty, typos, capitalisation, neighbours, legacy names.
        for val in [
            "",
            "beta",
            "Unstable",
            "UNSTABLE",
            "stable",
            "nightly",
            "pre-release",
            "unstable ",
        ] {
            let _guard = ChannelEnvGuard::new(Some(val));
            assert_eq!(
                Channel::current(),
                Channel::Stable,
                "value {val:?} must fail-closed to Stable"
            );
        }
    }

    #[test]
    fn channel_current_env_overrides_runtime_file() {
        let _guard = ChannelEnvGuard::new(Some("unstable"));
        let path = std::env::var("KEYSTONE_UPDATE_CHANNEL_FILE").unwrap();
        std::fs::write(path, "stable\n").unwrap();
        assert_eq!(Channel::current(), Channel::Unstable);
    }

    #[test]
    fn ok_state_includes_channel() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = serde_json::to_value(&state).unwrap();
        // Untagged enum serialization means OkState's fields are at the
        // top level of the object. The fixture pins channel to "stable"
        // so we check against that value.
        assert_eq!(rendered["channel"], "stable");
    }

    #[test]
    fn err_state_includes_channel_when_populated() {
        let state = MenuState::Err(ErrState {
            ok: false,
            channel: "unstable".into(),
            error: "Simulated failure.".into(),
            ..Default::default()
        });
        let rendered = serde_json::to_value(&state).unwrap();
        assert_eq!(rendered["channel"], "unstable");
    }

    #[test]
    fn preview_summary_shows_channel_line() {
        let mut fixture = ok_fixture();
        fixture.channel = "unstable".into();
        let rendered = render_preview_summary(&MenuState::Ok(fixture));
        assert!(
            rendered.contains("Channel: unstable"),
            "preview summary must disclose the active channel, got:\n{rendered}"
        );
    }

    #[test]
    fn entries_latest_subtext_unstable_describes_main_commit() {
        // The unstable channel's `latest_url` points to the tip commit on
        // `main`, so the subtext describes a commit on that branch.
        let mut fixture = ok_fixture();
        fixture.channel = "unstable".into();
        fixture.latest_tag = "main".into();
        fixture.latest_name = format!("main@{}", short(&fixture.latest_rev));
        let rendered = render_entries_json(&MenuState::Ok(fixture)).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        assert_eq!(arr[1]["Text"], "Latest: main");
        assert_eq!(
            arr[1]["Subtext"],
            "Latest commit on main (unstable channel)"
        );
    }

    #[test]
    fn entries_latest_subtext_stable_describes_release_branch_commit() {
        // The stable channel tracks the tip of the highest `release/<M>.<m>`
        // line, so the row links to that tip commit and the subtext names
        // the branch. Naming the channel keeps the row visibly distinct from
        // the unstable variant.
        let fixture = ok_fixture();
        assert_eq!(fixture.channel, "stable");
        let rendered = render_entries_json(&MenuState::Ok(fixture)).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        assert_eq!(arr[1]["Text"], "Latest: release/1.0");
        assert_eq!(
            arr[1]["Subtext"],
            "Latest commit on release/1.0 (stable channel)"
        );
    }

    #[test]
    fn entries_ok_state_has_three_entries_with_update_row() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        assert_eq!(arr.len(), 3);
        // current_tag is empty under branch tracking, so the current row
        // falls back to the short rev.
        assert_eq!(arr[0]["Text"], "Current: aaaaaaa");
        assert_eq!(arr[1]["Text"], "Latest: release/1.0");
        assert_eq!(arr[2]["Text"], "Update current host");
        assert_eq!(arr[2]["Value"], ACT_RUN_UPDATE);
        assert!(
            arr[1]["Value"]
                .as_str()
                .unwrap()
                .starts_with(&format!("{ACT_OPEN_RELEASE}\t")),
            "latest entry must open the release-line commit on activation"
        );
    }

    #[test]
    fn entries_blocks_when_update_not_allowed() {
        let mut fixture = ok_fixture();
        fixture.update_allowed = false;
        fixture.update_reason = "The active system flake has uncommitted changes.".into();
        let state = MenuState::Ok(fixture);
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        let blocked = &arr[2];
        assert_eq!(blocked["Text"], "Update unavailable");
        // The Value MUST be a stable token — blocker text is rendered at
        // dispatch time by re-reading state (see the `Activation values`
        // block). Embedding free-form text here would break Lua's single-
        // quoted shell wrapping when the text contains a quote.
        assert_eq!(blocked["Value"], ACT_BLOCKED_UPDATE);
        assert_eq!(
            blocked["Subtext"],
            "The active system flake has uncommitted changes."
        );
    }

    #[test]
    fn entries_err_state_surfaces_error() {
        let state = MenuState::Err(ErrState {
            ok: false,
            error: "No flake.lock found.".into(),
            ..Default::default()
        });
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["Text"], "Keystone OS unavailable");
        assert_eq!(arr[0]["Subtext"], "No flake.lock found.");
        assert_eq!(arr[0]["Value"], ACT_BLOCKED_KEYSTONE);
    }

    #[test]
    fn entries_skip_release_row_when_url_is_unsafe() {
        // A release URL with a shell metachar (e.g. a single quote from a
        // hypothetical GitHub glitch) must not be embedded into the Value —
        // render_entries_json should drop that entry rather than risk
        // breaking Lua's single-quoted Action.
        let mut fixture = ok_fixture();
        fixture.latest_url = "https://github.com/owner/repo/commit/v0'8".into();
        let state = MenuState::Ok(fixture);
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        // Current + Update entries remain, but the Latest (commit-link)
        // entry is filtered because the URL failed the safety check.
        assert_eq!(arr.len(), 2);
        assert_eq!(arr[0]["Text"], "Current: aaaaaaa");
        assert_eq!(arr[1]["Value"], ACT_RUN_UPDATE);
    }

    #[test]
    fn url_is_shell_safe_accepts_real_release_urls() {
        assert!(url_is_shell_safe(
            "https://github.com/ncrmro/keystone/releases/tag/v0.8.0"
        ));
        assert!(url_is_shell_safe(
            "https://github.com/owner/repo/releases/tag/v1.2.3-rc1+build.42"
        ));
    }

    #[test]
    fn url_is_shell_safe_rejects_quote_and_space() {
        assert!(!url_is_shell_safe("https://github.com/owner/repo/tag/v0'8"));
        assert!(!url_is_shell_safe("https://github.com/a b"));
        assert!(!url_is_shell_safe(""));
        assert!(!url_is_shell_safe("https://github.com/owner/repo\n"));
    }

    #[test]
    fn preview_summary_ok_formats_key_fields() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = render_preview_summary(&state);
        assert!(rendered.contains("Keystone OS update status"));
        assert!(rendered.contains("Consumer flake: /etc/nixos-config"));
        assert!(rendered.contains("Current: aaaaaaa (aaaaaaa)"));
        assert!(rendered.contains("Latest: release/1.0 (bbbbbbb)"));
        assert!(rendered.contains("Update command: ks update"));
    }

    #[test]
    fn preview_summary_shows_blocker_when_update_not_allowed() {
        let mut fixture = ok_fixture();
        fixture.update_allowed = false;
        fixture.update_reason = "Working tree dirty.".into();
        let rendered = render_preview_summary(&MenuState::Ok(fixture));
        assert!(rendered.contains("Update: Working tree dirty."));
        assert!(!rendered.contains("Update command: ks update"));
    }

    #[test]
    fn preview_release_notes_renders_body_and_url() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = render_preview_release_notes(&state);
        assert!(rendered.contains("release/1.0@bbbbbbb"));
        assert!(rendered.contains("Ref: release/1.0"));
        assert!(rendered.contains("Published: 2026-04-01T10:00:00Z"));
        assert!(rendered.contains("add Walker update menu"));
        assert!(rendered.contains(
            "https://github.com/ncrmro/keystone/commit/bbbbbbbbccccccccddddddddeeeeeeeeffffffff"
        ));
    }

    #[test]
    fn preview_release_notes_uses_partial_err_state_when_available() {
        let state = MenuState::Err(ErrState {
            ok: false,
            latest_tag: Some("v0.8.0".into()),
            latest_body: Some("Release notes body".into()),
            latest_url: Some("https://example/release".into()),
            error: "Could not resolve release commit".into(),
            ..Default::default()
        });
        let rendered = render_preview_release_notes(&state);
        // Partial render should surface the ref even though the overall state
        // is errored out.
        assert!(rendered.contains("Ref: v0.8.0"));
        assert!(rendered.contains("Release notes body"));
        assert!(rendered.contains("https://example/release"));
    }

    fn parse_lock(raw: &str) -> FlakeLock {
        serde_json::from_str(raw).expect("test fixture must be valid flake.lock JSON")
    }

    #[test]
    fn find_keystone_input_walks_root_inputs_and_ignores_transitive() {
        // Simulates a consumer flake whose direct input `keystone` is the
        // real ncrmro/keystone pin, while `other/keystone-fork` is an
        // unrelated node that *also* has original.owner=ncrmro repo=keystone
        // (as could happen with a transitive dep that pins the same repo).
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {
                    "inputs": {
                        "keystone": "keystone",
                        "nixpkgs": "nixpkgs"
                    }
                },
                "keystone": {
                    "locked": {"type": "github", "rev": "aaaaaaaa"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "transitive_keystone": {
                    "locked": {"type": "github", "rev": "ffffffff"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "nixpkgs": {
                    "locked": {"type": "github", "rev": "cccccccc"},
                    "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let (name, node) = find_keystone_input(&lock).expect("should find exactly one root match");
        assert_eq!(name, "keystone");
        assert_eq!(
            node.locked.as_ref().unwrap().rev.as_deref(),
            Some("aaaaaaaa")
        );
    }

    #[test]
    fn find_keystone_input_errors_when_no_root_input_matches() {
        // Root declares only a nixpkgs input; the keystone node exists only
        // as a transitive dep. We must not silently return it.
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {"inputs": {"nixpkgs": "nixpkgs"}},
                "transitive_keystone": {
                    "locked": {"type": "github", "rev": "ffffffff"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "nixpkgs": {
                    "locked": {"type": "github", "rev": "cccccccc"},
                    "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let err = find_keystone_input(&lock).unwrap_err();
        assert!(err.to_string().contains("no root input pins"), "got: {err}");
    }

    #[test]
    fn find_keystone_input_errors_when_multiple_root_inputs_match() {
        // Pathological but possible: the user declared two direct inputs
        // both pinning ncrmro/keystone under different names. We must
        // refuse rather than pick one arbitrarily.
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {
                    "inputs": {
                        "keystone": "keystone",
                        "keystone_alt": "keystone_alt"
                    }
                },
                "keystone": {
                    "locked": {"type": "github", "rev": "aaaaaaaa"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "keystone_alt": {
                    "locked": {"type": "github", "rev": "bbbbbbbb"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let err = find_keystone_input(&lock).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("found 2 root inputs"), "got: {msg}");
    }

    #[test]
    fn find_keystone_input_skips_follows_inputs() {
        // A `follows` input appears as an array value in root.inputs.
        // That path cannot be a direct GitHub source, so we must skip it
        // when looking for the keystone pin.
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {
                    "inputs": {
                        "keystone": "keystone",
                        "nixpkgs": ["keystone", "nixpkgs"]
                    }
                },
                "keystone": {
                    "locked": {"type": "github", "rev": "aaaaaaaa"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let (name, _) = find_keystone_input(&lock).expect("should resolve");
        assert_eq!(name, "keystone");
    }

    #[tokio::test]
    async fn dispatch_rejects_unknown_actions() {
        let err = dispatch("mystery-action", None).await.unwrap_err();
        assert!(
            err.to_string().contains("unknown update menu action"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn dispatch_noop_is_ok() {
        dispatch("", None).await.unwrap();
        dispatch("noop", None).await.unwrap();
    }

    #[test]
    fn evaluate_local_gate_rejects_missing_flake() {
        // With a guaranteed-nonexistent flake override, the gate must
        // refuse rather than silently pretend local preconditions are
        // met. Exact message is user-facing copy; keep the test loose
        // on wording and strict on rejection.
        let err = evaluate_local_gate(Some(Path::new("/nonexistent/path/used/only/in/unit/tests")))
            .unwrap_err();
        assert!(!err.is_empty(), "gate must return a non-empty reason");
    }

    #[test]
    fn unstable_state_uses_branch_sha_for_latest_rev() {
        // Simulates the `GET /repos/OWNER/REPO/branches/main` response
        // shape. The unstable channel MUST read the commit SHA inline
        // rather than issuing a second ref-to-sha lookup, and MUST
        // synthesize the display label as `main@<short-sha>`.
        let sha = "aabbccddeeff00112233445566778899aabbccdd";
        let payload = serde_json::json!({
            "name": "main",
            "commit": {
                "sha": sha,
                "html_url": format!("https://github.com/ncrmro/keystone/commit/{sha}"),
                "commit": {
                    "committer": { "date": "2026-04-22T12:00:00Z" },
                    "message": "feat(ks): add update channel\n\nLonger body that should not appear in the preview pane.",
                }
            }
        });
        let info = parse_unstable_branch(&payload).expect("branch response parses");
        assert_eq!(info.latest_tag, "main");
        assert_eq!(info.latest_rev, sha);
        assert_eq!(info.latest_name, format!("main@{}", &sha[..7]));
        assert_eq!(info.latest_published, "2026-04-22T12:00:00Z");
        assert_eq!(
            info.latest_url,
            format!("https://github.com/ncrmro/keystone/commit/{sha}")
        );
        // Body is the first paragraph (conventional commit subject line).
        assert_eq!(info.latest_body, "feat(ks): add update channel");
    }

    #[test]
    fn unstable_state_falls_back_to_tree_url_when_html_url_missing() {
        // A missing / empty `commit.html_url` must not drop the latest
        // row — fall back to the tree-view URL so the menu always has a
        // shell-safe link.
        let payload = serde_json::json!({
            "name": "main",
            "commit": {
                "sha": "0000000000000000000000000000000000000001",
                "commit": {
                    "committer": { "date": "2026-04-22T12:00:00Z" },
                    "message": "chore: bump deps",
                }
            }
        });
        let info = parse_unstable_branch(&payload).unwrap();
        assert_eq!(
            info.latest_url,
            "https://github.com/ncrmro/keystone/tree/main"
        );
    }

    #[test]
    fn unstable_state_errors_when_sha_missing() {
        // Without a commit SHA the menu cannot compare against the
        // locked rev, so the parser must surface an error.
        let payload = serde_json::json!({
            "name": "main",
            "commit": {
                "commit": { "committer": {"date": "2026-04-22T12:00:00Z"} }
            }
        });
        let err = parse_unstable_branch(&payload).unwrap_err();
        assert!(
            err.to_string().contains("commit.sha"),
            "expected sha error, got: {err}"
        );
    }

    #[test]
    fn unstable_state_body_falls_back_when_message_empty() {
        // A commit with an empty message should produce a non-empty
        // body so the preview pane stays renderable.
        let payload = serde_json::json!({
            "name": "main",
            "commit": {
                "sha": "0000000000000000000000000000000000000002",
                "commit": {
                    "committer": { "date": "2026-04-22T12:00:00Z" },
                    "message": "",
                }
            }
        });
        let info = parse_unstable_branch(&payload).unwrap();
        assert_eq!(info.latest_body, "No commit message.");
    }

    #[tokio::test]
    async fn dispatch_rejects_unsafe_open_release_payload() {
        // Defense in depth: even if entries were tampered with, dispatch
        // must refuse to hand an unsafe URL to xdg-open.
        let err = dispatch(
            &format!("{ACT_OPEN_RELEASE}\thttps://example.com/a'b"),
            None,
        )
        .await
        .unwrap_err();
        assert!(
            err.to_string().contains("failed safety check"),
            "got: {err}"
        );
    }
}
