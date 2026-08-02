//! `ks kube ...` — Kubernetes helpers.
//!
//! Currently one subcommand: `ks kube sudo`, per-command privilege
//! escalation via RBAC impersonation. Day-to-day kubectl runs with an
//! unprivileged identity; when a single command needs elevated rights, `ks
//! kube sudo -- <kubectl args...>` re-runs it as the caller's own user
//! identity plus the `keystone:sudoers` impersonation group. What that
//! group may do is bound server-side by RBAC (a ClusterRole/binding
//! maintained in ks.systems/services `access/sudo.yaml`), so escalation is
//! scoped per command and never grants `system:masters`.
//!
//! Approval gating: `ks kube sudo` itself needs no root — the escalation
//! is enforced by the cluster, and kubeconfig credentials are already the
//! caller's. The `keystone.security.privilegedApproval` module
//! (`modules/os/privileged-approval.nix`) currently asserts
//! `runAs == "root"` for every allowlist entry, so wiring this command
//! through `ks approve` would force a wrong runAs. The polkit approval
//! ceremony (hardware-key/password) for `ks kube sudo` lands when that
//! module grows non-root `runAs` support; until then the command works
//! standalone.

use std::env;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Subcommand};

/// Impersonation group granted elevated RBAC. The bindings live in
/// ks.systems/services `access/sudo.yaml`.
const SUDOERS_GROUP: &str = "keystone:sudoers";

#[derive(Subcommand)]
pub enum KubeCommand {
    /// Run one kubectl command with elevated rights via RBAC impersonation.
    ///
    /// Execs `kubectl --as=<user> --as-group=keystone:sudoers <args...>`,
    /// preserving stdin/stdout/stderr and exit status. The impersonated
    /// identity defaults to $USER; the elevated permissions come from the
    /// `keystone:sudoers` group's RBAC bindings, never `system:masters`.
    Sudo(KubeSudoArgs),
}

#[derive(Args)]
pub struct KubeSudoArgs {
    /// Target cluster. Reserved: accepted but currently unused — kubectl
    /// resolves the cluster from the environment ($KUBECONFIG / default
    /// kubeconfig / current context) untouched. It becomes a selector once
    /// a cluster registry exists.
    #[arg(long)]
    pub cluster: Option<String>,

    /// User identity to impersonate (defaults to $USER).
    #[arg(long)]
    pub user: Option<String>,

    /// kubectl arguments (after `--`).
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub args: Vec<String>,
}

/// Resolve the impersonated user: explicit `--user`, else $USER.
fn resolve_user(explicit: Option<&str>) -> Result<String> {
    let user = match explicit {
        Some(user) => user.to_string(),
        None => env::var("USER").context("--user not given and $USER is unset")?,
    };
    validate_user(&user)?;
    Ok(user)
}

/// Reject empty and `system:`-reserved identities. Escalation must go
/// through `keystone:sudoers` RBAC, never by impersonating a Kubernetes
/// system identity (`system:masters` et al. bypass RBAC entirely).
fn validate_user(user: &str) -> Result<()> {
    if user.trim().is_empty() {
        bail!("Impersonated user must not be empty");
    }
    if user.starts_with("system:") {
        bail!(
            "Refusing to impersonate reserved identity '{}' — escalation is scoped by the {} group, not system: identities",
            user,
            SUDOERS_GROUP
        );
    }
    Ok(())
}

/// Build the full kubectl argv (including the `kubectl` program name) for
/// an impersonated invocation. Impersonation flags come first so they can
/// never be swallowed by a trailing `--` in the user's arguments.
fn kubectl_argv(user: &str, args: &[String]) -> Vec<String> {
    let mut argv = Vec::with_capacity(args.len() + 3);
    argv.push("kubectl".to_string());
    argv.push(format!("--as={}", user));
    argv.push(format!("--as-group={}", SUDOERS_GROUP));
    argv.extend(args.iter().cloned());
    argv
}

pub fn execute(cmd: KubeCommand) -> Result<()> {
    match cmd {
        KubeCommand::Sudo(args) => sudo(&args),
    }
}

fn sudo(args: &KubeSudoArgs) -> Result<()> {
    if args.args.is_empty() {
        bail!("Missing kubectl arguments after -- (usage: ks kube sudo -- <kubectl args...>)");
    }

    let user = resolve_user(args.user.as_deref())?;
    let argv = kubectl_argv(&user, &args.args);

    match args.cluster.as_deref() {
        Some(cluster) => eprintln!(
            "ks kube sudo: impersonating user '{}' with group '{}' (--cluster '{}' is reserved and currently ignored; kubectl uses $KUBECONFIG / current context)",
            user, SUDOERS_GROUP, cluster
        ),
        None => eprintln!(
            "ks kube sudo: impersonating user '{}' with group '{}'",
            user, SUDOERS_GROUP
        ),
    }

    // exec() replaces this process: stdin/stdout/stderr and the exit
    // status belong to kubectl. Environment (incl. KUBECONFIG) passes
    // through untouched. exec() only returns on failure.
    let error = Command::new(&argv[0])
        .args(&argv[1..])
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .exec();
    Err(anyhow!(error)).context("Failed to exec kubectl — is it installed and in PATH?")
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    /// Minimal harness mirroring how `ks` mounts the subcommand group.
    #[derive(Parser)]
    struct TestCli {
        #[command(subcommand)]
        command: KubeCommand,
    }

    fn parse(args: &[&str]) -> Result<KubeSudoArgs, clap::Error> {
        TestCli::try_parse_from(args).map(|cli| match cli.command {
            KubeCommand::Sudo(args) => args,
        })
    }

    #[test]
    fn parses_plain_sudo_with_kubectl_args() {
        let args = parse(&["ks", "sudo", "--", "get", "pods", "-A"]).unwrap();
        assert_eq!(args.args, vec!["get", "pods", "-A"]);
        assert!(args.user.is_none());
        assert!(args.cluster.is_none());
    }

    #[test]
    fn parses_user_and_cluster_flags() {
        let args = parse(&[
            "ks", "sudo", "--cluster", "ocean", "--user", "alice", "--", "delete", "pod", "x",
        ])
        .unwrap();
        assert_eq!(args.cluster.as_deref(), Some("ocean"));
        assert_eq!(args.user.as_deref(), Some("alice"));
        assert_eq!(args.args, vec!["delete", "pod", "x"]);
    }

    #[test]
    fn kubectl_flags_after_separator_stay_in_args() {
        // Hyphen-values must flow to kubectl, not be parsed by clap.
        let args = parse(&["ks", "sudo", "--", "get", "pods", "--all-namespaces", "-o", "wide"])
            .unwrap();
        assert_eq!(args.args, vec!["get", "pods", "--all-namespaces", "-o", "wide"]);
    }

    #[test]
    fn builds_impersonation_argv_before_user_args() {
        let argv = kubectl_argv("alice", &["get".to_string(), "pods".to_string()]);
        assert_eq!(
            argv,
            vec![
                "kubectl",
                "--as=alice",
                "--as-group=keystone:sudoers",
                "get",
                "pods",
            ]
        );
    }

    #[test]
    fn resolve_user_prefers_explicit_flag() {
        assert_eq!(resolve_user(Some("alice")).unwrap(), "alice");
    }

    #[test]
    fn rejects_system_identities() {
        let err = validate_user("system:masters").unwrap_err().to_string();
        assert!(err.contains("system:masters"), "got: {err}");
        assert!(validate_user("system:admin").is_err());
    }

    #[test]
    fn rejects_empty_user() {
        assert!(validate_user("").is_err());
        assert!(validate_user("   ").is_err());
    }

    #[test]
    fn accepts_ordinary_user() {
        assert!(validate_user("ncrmro").is_ok());
    }
}
