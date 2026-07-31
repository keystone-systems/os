//! `ks activate <store-path>` — narrow privileged activation for a
//! pre-built NixOS system closure.
//!
//! This is the only step of the Walker → Update flow that requires root.
//! Everything upstream (channel resolution, flake input override, `nix
//! build`, `git commit`, `git push`) runs in the user's session where
//! credentials and network already work.
//!
//! Allowlist contract: the privileged-approval module installs an entry
//! whose `argv` matches `["ks", "activate"]` (prefix), so the only way
//! to reach root is `ks approve --reason <text> -- ks activate
//! <store-path>`. The store path arrives as a positional arg and is
//! validated here before any privileged side effect.
//!
//! Idempotence: running this against the closure already pointed at by
//! `/run/current-system` short-circuits to a no-op. This matches the
//! `local_system_closure_matches` fast path used by `cmd::switch` and
//! lets the Walker flow safely retry without double-activating.
//!
//! Implementation choice: explicit profile bump + `switch-to-configuration`
//! rather than `nixos-rebuild switch --no-build`. Reasons:
//!   - `nixos-rebuild` would re-evaluate the flake under root, which
//!     defeats the user-side build we just produced. The store path is
//!     already realized; we only need to activate it.
//!   - The two-step shape (`nix-env --profile … --set <path>` then
//!     `<path>/bin/switch-to-configuration switch`) matches what
//!     `cmd::switch::set_local_system_profile` + `switch_local_system`
//!     already do for `ks switch`, so failure modes are familiar.

use anyhow::{anyhow, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Validate the store-path argument before any privileged side effect.
/// Rejects relative paths, empty strings, and paths that don't live under
/// `/nix/store/`. The allowlist already restricts callers to argv shape
/// `["ks", "activate", <path>]`, but defense-in-depth: the validator runs
/// inside the privileged child too, so even a misconfigured allowlist
/// can't push activation against an arbitrary path.
//
// SECURITY: path traversal via `..` segments. A naive `starts_with`
// check on the raw string accepts inputs like `/nix/store/../tmp/evil`
// which still has the `/nix/store/` prefix but resolves outside the
// store. An attacker who can create files under `/tmp/evil/bin/` could
// drop a fake `switch-to-configuration` and have it executed as root
// once the broker re-execs us.
//
// Mitigation: canonicalize the path (`std::fs::canonicalize` resolves
// `..` segments and follows symlinks) and re-check the *canonical*
// path is under `/nix/store/`. canonicalize fails on non-existent
// paths, so it doubles as the existence check; a missing-path failure
// is also a hard bail.
fn validate_store_path(raw: &str) -> Result<PathBuf> {
    if raw.trim().is_empty() {
        anyhow::bail!("ks activate requires a store path argument");
    }
    let path = PathBuf::from(raw);
    if !path.is_absolute() {
        anyhow::bail!("store path must be absolute: {raw}");
    }
    // Cheap pre-check: reject the obvious before paying for canonicalize.
    // The authoritative check is on the canonical path below.
    if !path.starts_with("/nix/store/") {
        anyhow::bail!("store path must live under /nix/store/: {raw}");
    }
    let canonical = std::fs::canonicalize(&path).map_err(|e| {
        anyhow!(
            "store path does not exist or cannot be resolved: {} ({}) \
             (did the user-side `nix build` succeed?)",
            path.display(),
            e
        )
    })?;
    // SECURITY: re-check the canonical (post-`..`-resolution) path lives
    // under `/nix/store/`. Without this, `/nix/store/../tmp/evil` would
    // canonicalize to `/tmp/evil` and slip past.
    if !canonical.starts_with("/nix/store/") {
        anyhow::bail!(
            "store path resolves outside /nix/store/: {} → {}",
            path.display(),
            canonical.display()
        );
    }
    let switch_bin = canonical.join("bin/switch-to-configuration");
    if !switch_bin.is_file() {
        anyhow::bail!(
            "store path is not a NixOS system closure (missing {}): {}",
            switch_bin.display(),
            canonical.display()
        );
    }
    Ok(canonical)
}

/// Returns true when `/run/current-system` already points at `path`.
/// Same probe `cmd::switch::local_system_closure_matches` uses; duplicated
/// here so this module stays standalone (avoids pulling switch's
/// SshSessionManager and friends into a privileged code path).
fn current_system_matches(path: &Path) -> bool {
    let current = std::fs::canonicalize("/run/current-system").ok();
    let target = std::fs::canonicalize(path).ok();
    match (current, target) {
        (Some(c), Some(t)) => c == t,
        _ => false,
    }
}

/// Bump the system profile to point at the new closure. Equivalent to
/// `nix-env --profile /nix/var/nix/profiles/system --set <path>`. Runs
/// directly (no sudo) — this command path is reachable only after the
/// approval broker re-exec'd as root, so EUID is already 0.
fn set_system_profile(path: &Path) -> Result<()> {
    let status = Command::new("nix-env")
        .args(["--profile", "/nix/var/nix/profiles/system", "--set"])
        .arg(path)
        .status()
        .context("failed to invoke nix-env to set system profile")?;
    if !status.success() {
        anyhow::bail!(
            "nix-env --profile system --set {} exited {:?}",
            path.display(),
            status.code()
        );
    }
    Ok(())
}

/// Touch the bootloader-safe-to-update marker before invoking
/// switch-to-configuration. Mirrors `cmd::switch::switch_local_system`.
fn mark_bootloader_safe() -> Result<()> {
    let status = Command::new("touch")
        .arg("/var/run/nixos-rebuild-safe-to-update-bootloader")
        .status()
        .context("failed to touch nixos-rebuild-safe-to-update-bootloader")?;
    if !status.success() {
        anyhow::bail!(
            "touch /var/run/nixos-rebuild-safe-to-update-bootloader exited {:?}",
            status.code()
        );
    }
    Ok(())
}

/// Run `<path>/bin/switch-to-configuration <mode>` directly. The closure
/// at `path` carries its own switch-to-configuration so we always invoke
/// the version that matches the closure being activated — never a stale
/// one from a previous generation.
///
/// Exit-code handling: 0 = clean success, 4 = success-with-warnings,
/// anything else = real failure.
///
/// Exit 4 is NixOS' "warning: the following units failed: …" outcome.
/// The system *is* on the new generation by then: `/run/current-system`
/// and `/nix/var/nix/profiles/system` are bumped, agenix has run, `/etc`
/// is current, and the configured units have been
/// started/restarted/reloaded. The warning typically reflects a unit
/// that happens to be in `activating (auto-restart)` state during the
/// post-switch check window — common for daemons with `Restart=always`
/// plus a long `RestartSec` (e.g., `systemd-journal-upload` exiting 1
/// on malformed local journal entries between cycles). Treating exit 4
/// as a hard failure aborts `ks update --approve`'s post-activation
/// work (relock, commit, push, notify) even though the system is
/// already on the new generation, so we surface a notice and proceed.
fn switch_to_configuration(path: &Path, mode: &str) -> Result<()> {
    let switch_bin = path.join("bin/switch-to-configuration");
    let status = Command::new(&switch_bin)
        .arg(mode)
        .status()
        .with_context(|| format!("failed to invoke {}", switch_bin.display()))?;
    match status.code() {
        Some(0) => Ok(()),
        Some(4) => {
            eprintln!(
                "{} {}: completed with warnings (exit 4) — system is on the new generation; some units flagged in the post-switch check. Continuing.",
                switch_bin.display(),
                mode
            );
            Ok(())
        }
        other => anyhow::bail!("{} {} exited {:?}", switch_bin.display(), mode, other),
    }
}

fn is_root() -> bool {
    // SAFETY: getuid() is always defined and never fails on Linux.
    // Reading effective user id requires no allocation; falling back
    // to the `id -u` shellout would add a dependency on `id` being on
    // PATH, which the systemd unit's stripped PATH may not guarantee.
    unsafe { libc::geteuid() == 0 }
}

/// Public entry point. Validates inputs, short-circuits if the closure
/// is already current, then bumps the profile and runs
/// switch-to-configuration in `mode`.
pub fn execute(store_path: &str, mode: &str) -> Result<()> {
    let path = validate_store_path(store_path)?;

    if !matches!(mode, "switch" | "boot" | "test" | "dry-activate") {
        return Err(anyhow!(
            "ks activate: unsupported mode '{mode}' (expected switch|boot|test|dry-activate)"
        ));
    }

    if !is_root() {
        // Mode is optional in the user-facing CLI (`switch` is the
        // default), so emit a paste-ready invocation that uses the
        // explicit `--mode` form Clap actually parses. Showing the
        // mode as a positional arg (the previous "ks activate <path>
        // {mode}" string) produced commands Clap rejected — copy/paste
        // failed silently for users who hit the not-root branch.
        anyhow::bail!(
            "ks activate must run as root. Invoke via:\n  \
             ks approve --reason \"<reason>\" -- ks activate {} --mode {mode}",
            path.display()
        );
    }

    if current_system_matches(&path) {
        eprintln!(
            "ks activate: /run/current-system already points at {} — nothing to do.",
            path.display()
        );
        return Ok(());
    }

    eprintln!(
        "ks activate: bumping system profile to {} ({})",
        path.display(),
        mode
    );
    set_system_profile(&path)?;
    mark_bootloader_safe()?;
    switch_to_configuration(&path, mode)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_store_path_rejects_empty() {
        let err = validate_store_path("").unwrap_err().to_string();
        assert!(err.contains("requires a store path"), "got: {err}");
    }

    #[test]
    fn validate_store_path_rejects_relative() {
        let err = validate_store_path("relative/path")
            .unwrap_err()
            .to_string();
        assert!(err.contains("must be absolute"), "got: {err}");
    }

    #[test]
    fn validate_store_path_rejects_outside_nix_store() {
        let err = validate_store_path("/etc/passwd").unwrap_err().to_string();
        assert!(err.contains("/nix/store/"), "got: {err}");
    }

    #[test]
    fn validate_store_path_rejects_missing_path() {
        // A path under /nix/store that almost-certainly doesn't exist.
        let err = validate_store_path("/nix/store/0000000000000000000000000000000000000-bogus")
            .unwrap_err()
            .to_string();
        assert!(
            err.contains("does not exist") || err.contains("cannot be resolved"),
            "got: {err}"
        );
    }

    #[test]
    fn validate_store_path_rejects_path_traversal() {
        // SECURITY regression guard: `/nix/store/../tmp/evil` has the
        // `/nix/store/` prefix as a literal substring, but canonicalizes
        // outside the store. Before the canonicalize fix, a `starts_with`
        // check on the raw path accepted this and would have let an
        // attacker who could write under /tmp execute their own
        // `bin/switch-to-configuration` as root. The bail must happen
        // before any privileged side effect.
        let err = validate_store_path("/nix/store/../tmp/evil-keystone-traversal-probe")
            .unwrap_err()
            .to_string();
        // Either canonicalize fails (path doesn't exist — preferred), or
        // the canonical-path re-check trips. Both are hard bails before
        // any side effect, so accept either error string.
        assert!(
            err.contains("does not exist")
                || err.contains("cannot be resolved")
                || err.contains("resolves outside"),
            "expected traversal rejection, got: {err}"
        );
    }
}
