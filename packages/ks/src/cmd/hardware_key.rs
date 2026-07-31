//! `ks hardware-key` command family.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};

use super::util;
use crate::repo;

const DISK_UNLOCK_STATUS_FILE: &str = "/var/lib/keystone/disk-unlock-status.json";

#[derive(Debug, Clone, Serialize)]
pub struct HardwareKeyCheck {
    pub name: String,
    pub status: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct RegisteredHardwareKeyStatus {
    pub user: String,
    pub name: String,
    pub description: String,
    pub public_key_kind: String,
    pub public_key_comment: Option<String>,
    pub root_access: bool,
    pub age_identity: Option<String>,
    pub current_user_age_identity_configured: bool,
    pub current_user_age_serial: Option<String>,
    pub live_presence: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ConfiguredAgeIdentityStatus {
    pub serial: String,
    pub identity: String,
    pub present_in_identity_file: bool,
    pub connected: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct HardwareKeyDoctorReport {
    pub repo_root: String,
    pub host: String,
    pub current_user: Option<String>,
    pub selector: Option<String>,
    pub checks: Vec<HardwareKeyCheck>,
    pub registered_keys: Vec<RegisteredHardwareKeyStatus>,
    pub configured_age_identities: Vec<ConfiguredAgeIdentityStatus>,
    pub notes: Vec<String>,
    pub markdown: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct HardwareKeySecretsTodo {
    pub repo_root: String,
    pub host: String,
    pub current_user: Option<String>,
    pub implemented: bool,
    pub detected_layouts: Vec<String>,
    pub plans: Vec<String>,
    pub markdown: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct RegistryUser {
    #[serde(default)]
    hardware_keys: BTreeMap<String, RegistryHardwareKey>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RegistryHardwareKey {
    public_key: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    age_identity: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct HostHardwareKeyConfig {
    #[serde(default)]
    enable: bool,
    #[serde(default)]
    root_keys: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct AgeYubikeyConfig {
    #[serde(default)]
    enable: bool,
    #[serde(default)]
    identities: Vec<AgeYubikeyIdentity>,
    #[serde(default)]
    identity_path: String,
    #[serde(default)]
    secrets_flake_input: Option<String>,
    #[serde(default)]
    config_repo_path: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgeYubikeyIdentity {
    serial: String,
    identity: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiskUnlockStatus {
    device: String,
    #[serde(default)]
    tpm_enrolled: bool,
    #[serde(default)]
    fido2_enrolled: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DoctorEvalBundle {
    keys: BTreeMap<String, RegistryUser>,
    #[serde(default)]
    hardware_key: HostHardwareKeyConfig,
    tpm_enabled: bool,
    secure_boot_enabled: bool,
    storage_type: String,
    #[serde(default)]
    secrets_repo: Option<String>,
    #[serde(default)]
    age_yubikey: AgeYubikeyConfig,
}

#[derive(Debug, Clone)]
struct ProbeResult {
    stdout: String,
    stderr: String,
    status_code: Option<i32>,
}

impl ProbeResult {
    fn success(&self) -> bool {
        self.status_code == Some(0)
    }

    fn combined(&self) -> String {
        format!("{}{}", self.stdout, self.stderr)
    }

    fn summary_line(&self) -> String {
        self.combined()
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .unwrap_or("no output")
            .to_string()
    }
}

#[derive(Debug, Clone)]
struct IdentityFileEntry {
    serial: Option<String>,
    identity: String,
}

#[derive(Debug, Clone)]
enum Selector {
    CurrentUserOrAll,
    User(String),
    Key { user: String, key: String },
}

fn parse_selector(selector: Option<&str>) -> Result<Selector> {
    let Some(selector) = selector.filter(|value| !value.trim().is_empty()) else {
        return Ok(Selector::CurrentUserOrAll);
    };

    let parts: Vec<&str> = selector.split('/').collect();
    match parts.as_slice() {
        [user] => Ok(Selector::User(user.to_string())),
        [user, key] => Ok(Selector::Key {
            user: user.to_string(),
            key: key.to_string(),
        }),
        _ => Err(anyhow!(
            "invalid selector '{}'; expected `user` or `user/key`",
            selector
        )),
    }
}

fn check(name: &str, status: &str, detail: impl Into<String>) -> HardwareKeyCheck {
    HardwareKeyCheck {
        name: name.to_string(),
        status: status.to_string(),
        detail: detail.into(),
    }
}

fn probe(program: &str, args: &[&str]) -> Result<ProbeResult> {
    let output = Command::new(program)
        .args(args)
        .output()
        .with_context(|| format!("Failed to run {}", program))?;
    Ok(ProbeResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        status_code: output.status.code(),
    })
}

fn nix_string_literal(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

async fn eval_doctor_bundle(
    repo_root: &Path,
    host: &str,
    current_user: Option<&str>,
) -> Result<DoctorEvalBundle> {
    let age_yubikey_expr = current_user
        .map(|user| {
            format!(
                "cfg.home-manager.users.{}.keystone.terminal.ageYubikey",
                nix_string_literal(user)
            )
        })
        .unwrap_or_else(|| {
            "{ enable = false; identities = []; identityPath = \"\"; secretsFlakeInput = null; configRepoPath = \"\"; }".to_string()
        });

    let apply_expr = format!(
        "cfg: {{
          keys = cfg.keystone.keys;
          hardwareKey = cfg.keystone.hardwareKey;
          tpmEnabled = cfg.keystone.os.tpm.enable;
          secureBootEnabled = cfg.keystone.os.secureBoot.enable;
          storageType = cfg.keystone.os.storage.type;
          secretsRepo = cfg.keystone.secrets.repo;
          ageYubikey = {};
        }}",
        age_yubikey_expr
    );

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config",
            repo_root.display(),
            host,
        ))
        .arg("--apply")
        .arg(apply_expr)
        .arg("--json");

    for arg in repo::local_override_args(repo_root).await? {
        cmd.arg(arg);
    }

    let output = cmd
        .output()
        .await
        .context("Failed to evaluate hardware-key doctor config bundle")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "Failed to evaluate hardware-key doctor config bundle: {}",
            stderr.trim()
        );
    }

    serde_json::from_slice(&output.stdout)
        .context("Failed to parse hardware-key doctor config bundle")
}

fn parse_identity_file(content: &str) -> Vec<IdentityFileEntry> {
    let mut entries = Vec::new();
    let mut current_serial = None;

    for line in content.lines().map(str::trim) {
        if let Some(serial) = line.strip_prefix("# serial:") {
            current_serial = Some(serial.trim().to_string());
            continue;
        }
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        entries.push(IdentityFileEntry {
            serial: current_serial.take(),
            identity: line.to_string(),
        });
    }

    entries
}

fn ssh_public_key_kind(public_key: &str) -> String {
    public_key
        .split_whitespace()
        .next()
        .unwrap_or("unknown")
        .to_string()
}

fn ssh_public_key_comment(public_key: &str) -> Option<String> {
    let mut parts = public_key.split_whitespace();
    let _kind = parts.next()?;
    let _key = parts.next()?;
    let comment = parts.collect::<Vec<_>>().join(" ");
    if comment.is_empty() {
        None
    } else {
        Some(comment)
    }
}

fn configured_disk_unlock_device(storage_type: &str) -> &'static str {
    if storage_type == "zfs" {
        "/dev/zvol/rpool/credstore"
    } else {
        "/dev/disk/by-partlabel/disk-root-root"
    }
}

fn collect_selected_keys(
    registry: &BTreeMap<String, RegistryUser>,
    selector: &Selector,
    current_user: Option<&str>,
) -> Result<Vec<(String, String, RegistryHardwareKey)>> {
    match selector {
        Selector::CurrentUserOrAll => {
            if let Some(current_user) = current_user {
                if let Some(user) = registry.get(current_user) {
                    if !user.hardware_keys.is_empty() {
                        return Ok(user
                            .hardware_keys
                            .iter()
                            .map(|(name, key)| {
                                (current_user.to_string(), name.clone(), key.clone())
                            })
                            .collect());
                    }
                }
            }

            let selected = registry
                .iter()
                .flat_map(|(user, config)| {
                    config
                        .hardware_keys
                        .iter()
                        .map(|(name, key)| (user.clone(), name.clone(), key.clone()))
                })
                .collect::<Vec<_>>();
            Ok(selected)
        }
        Selector::User(user) => {
            let Some(config) = registry.get(user) else {
                anyhow::bail!("No hardware keys registered for unknown user '{}'", user);
            };
            Ok(config
                .hardware_keys
                .iter()
                .map(|(name, key)| (user.clone(), name.clone(), key.clone()))
                .collect())
        }
        Selector::Key { user, key } => {
            let Some(config) = registry.get(user) else {
                anyhow::bail!("Unknown user '{}'", user);
            };
            let Some(entry) = config.hardware_keys.get(key) else {
                anyhow::bail!("No hardware key '{}' registered for '{}'", key, user);
            };
            Ok(vec![(user.clone(), key.clone(), entry.clone())])
        }
    }
}

#[allow(clippy::cognitive_complexity)]
fn markdown_for_doctor(
    report: &HardwareKeyDoctorReport,
    disk_unlock_status: Option<&DiskUnlockStatus>,
) -> String {
    let mut markdown = String::new();
    markdown.push_str("## Hardware Key Doctor\n\n");
    markdown.push_str(&format!("**repo**: `{}`\n\n", report.repo_root));
    markdown.push_str(&format!("**host**: `{}`\n\n", report.host));
    if let Some(user) = &report.current_user {
        markdown.push_str(&format!("**current user**: `{}`\n\n", user));
    }
    if let Some(selector) = &report.selector {
        markdown.push_str(&format!("**selector**: `{}`\n\n", selector));
    }

    markdown.push_str("### Checks\n");
    for check in &report.checks {
        markdown.push_str(&format!(
            "- `{}`: **{}** — {}\n",
            check.name, check.status, check.detail
        ));
    }
    markdown.push('\n');

    markdown.push_str("### Registered SSH Hardware Keys\n");
    if report.registered_keys.is_empty() {
        markdown.push_str("_None_\n\n");
    } else {
        for key in &report.registered_keys {
            markdown.push_str(&format!(
                "- `{}/{}`: `{}`",
                key.user, key.name, key.public_key_kind
            ));
            if !key.description.is_empty() {
                markdown.push_str(&format!(" — {}", key.description));
            }
            markdown.push('\n');
            markdown.push_str(&format!(
                "  root access: {}; age identity configured: {}; live presence: {}\n",
                if key.root_access { "yes" } else { "no" },
                if key.current_user_age_identity_configured {
                    "yes"
                } else {
                    "no"
                },
                key.live_presence
            ));
        }
        markdown.push('\n');
    }

    markdown.push_str("### Configured Age Identities\n");
    if report.configured_age_identities.is_empty() {
        markdown.push_str("_None_\n\n");
    } else {
        for identity in &report.configured_age_identities {
            markdown.push_str(&format!(
                "- serial `{}`: file={}, connected={}\n",
                identity.serial,
                if identity.present_in_identity_file {
                    "yes"
                } else {
                    "no"
                },
                if identity.connected { "yes" } else { "no" }
            ));
        }
        markdown.push('\n');
    }

    markdown.push_str("### Disk Unlock\n");
    if let Some(status) = disk_unlock_status {
        markdown.push_str(&format!(
            "- device: `{}`\n- TPM enrolled: {}\n- FIDO2 enrolled: {}\n\n",
            status.device, status.tpm_enrolled, status.fido2_enrolled
        ));
    } else {
        markdown.push_str("_No world-readable disk unlock status file found._\n\n");
    }

    if !report.notes.is_empty() {
        markdown.push_str("### Notes\n");
        for note in &report.notes {
            markdown.push_str(&format!("- {}\n", note));
        }
        markdown.push('\n');
    }

    markdown
}

fn detect_same_repo_secrets_layout(repo_root: &Path, secrets_repo: Option<&str>) -> bool {
    if repo_root.join("secrets").is_dir() || repo_root.join("secrets.nix").is_file() {
        return true;
    }

    secrets_repo
        .map(PathBuf::from)
        .and_then(|path| fs::canonicalize(path).ok())
        .map(|path| path.starts_with(repo_root))
        .unwrap_or(false)
}

fn markdown_for_secrets(todo: &HardwareKeySecretsTodo) -> String {
    let mut markdown = String::new();
    markdown.push_str("## Hardware Key Secrets\n\n");
    markdown.push_str("TODO: this workflow is not implemented in `ks` yet.\n\n");
    markdown.push_str(&format!("**repo**: `{}`\n\n", todo.repo_root));
    markdown.push_str(&format!("**host**: `{}`\n\n", todo.host));
    if let Some(user) = &todo.current_user {
        markdown.push_str(&format!("**current user**: `{}`\n\n", user));
    }

    markdown.push_str("### Detected Layouts\n");
    for layout in &todo.detected_layouts {
        markdown.push_str(&format!("- {}\n", layout));
    }
    markdown.push('\n');

    markdown.push_str("### Planned Workflows\n");
    for plan in &todo.plans {
        markdown.push_str(&format!("- {}\n", plan));
    }
    markdown.push('\n');
    markdown
}

fn render_markdown(markdown: &str) -> Result<()> {
    print!("{}", markdown);
    Ok(())
}

#[allow(clippy::cognitive_complexity)]
pub async fn execute_doctor(
    selector: Option<&str>,
    flake_override: Option<&std::path::Path>,
) -> Result<HardwareKeyDoctorReport> {
    let repo_root = repo::find_repo(flake_override)?;
    let Some(host) = repo::resolve_current_host(&repo_root).await? else {
        anyhow::bail!(
            "Could not resolve the current host. Use --flake <path> or ensure keystone.systemFlake.path is set."
        );
    };
    let current_user = repo::resolve_current_hm_user(&repo_root, &host).await?;
    let selector = parse_selector(selector)?;
    let eval = eval_doctor_bundle(&repo_root, &host, current_user.as_deref()).await?;

    let registry = eval.keys;
    let selected_keys = collect_selected_keys(&registry, &selector, current_user.as_deref())?;
    let host_cfg = eval.hardware_key;
    let tpm_enabled = eval.tpm_enabled;
    let secure_boot_enabled = eval.secure_boot_enabled;
    let storage_type = eval.storage_type;
    let secrets_repo = eval.secrets_repo;
    let current_age_cfg = eval.age_yubikey;

    let identity_path = std::env::var("AGE_IDENTITIES_FILE")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| {
            if current_age_cfg.identity_path.is_empty() {
                None
            } else {
                Some(current_age_cfg.identity_path.clone())
            }
        })
        .unwrap_or_else(|| {
            std::env::var("HOME")
                .map(|home| format!("{home}/.age/yubikey-identity.txt"))
                .unwrap_or_else(|_| "~/.age/yubikey-identity.txt".to_string())
        });

    let identity_file_entries = fs::read_to_string(&identity_path)
        .ok()
        .map(|content| parse_identity_file(&content))
        .unwrap_or_default();

    let ykman_probe = util::find_executable("ykman")
        .map(|_| probe("ykman", &["list", "--serials"]))
        .transpose()?;
    let connected_serials = ykman_probe
        .as_ref()
        .filter(|probe| probe.success())
        .map(|probe| {
            probe
                .stdout
                .lines()
                .map(str::trim)
                .filter(|line| !line.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let age_probe = util::find_executable("age-plugin-yubikey")
        .map(|_| probe("age-plugin-yubikey", &["--list"]))
        .transpose()?;
    let fido_probe = util::find_executable("systemd-cryptenroll")
        .map(|_| probe("systemd-cryptenroll", &["--fido2-device=list"]))
        .transpose()?;

    let disk_unlock_status = fs::read_to_string(DISK_UNLOCK_STATUS_FILE)
        .ok()
        .and_then(|content| serde_json::from_str::<DiskUnlockStatus>(&content).ok());

    let root_refs = host_cfg.root_keys.to_vec();
    let selected_selector = selector_to_string(&selector);
    let mut checks = Vec::new();
    let mut notes = Vec::new();

    if selected_keys.is_empty() {
        checks.push(check(
            "registry",
            "warn",
            "No registered SSH hardware keys matched the selected scope",
        ));
    } else {
        checks.push(check(
            "registry",
            "ok",
            format!(
                "Found {} registered SSH hardware key(s)",
                selected_keys.len()
            ),
        ));
    }

    checks.push(check(
        "hardware-key-module",
        if host_cfg.enable { "ok" } else { "warn" },
        if host_cfg.enable {
            format!(
                "keystone.hardwareKey enabled; {} root key ref(s)",
                root_refs.len()
            )
        } else {
            "keystone.hardwareKey is disabled on this host".to_string()
        },
    ));

    let missing_root_refs = selected_keys
        .iter()
        .filter_map(|(user, key, _)| {
            let reference = format!("{user}/{key}");
            (!root_refs.contains(&reference)).then_some(reference)
        })
        .collect::<Vec<_>>();
    checks.push(check(
        "root-access",
        if missing_root_refs.is_empty() {
            "ok"
        } else {
            "warn"
        },
        if missing_root_refs.is_empty() {
            "All selected keys are wired into keystone.hardwareKey.rootKeys".to_string()
        } else {
            format!("Missing rootKeys entries: {}", missing_root_refs.join(", "))
        },
    ));

    checks.push(check(
        "age-yubikey-config",
        if current_age_cfg.enable && !current_age_cfg.identities.is_empty() {
            "ok"
        } else {
            "warn"
        },
        if current_age_cfg.enable {
            format!(
                "{} configured age identity/identities for current user",
                current_age_cfg.identities.len()
            )
        } else {
            "keystone.terminal.ageYubikey is not enabled for the current user".to_string()
        },
    ));

    let identity_file_status = if identity_file_entries.is_empty() {
        "warn"
    } else {
        "ok"
    };
    checks.push(check(
        "age-identity-file",
        identity_file_status,
        if identity_file_entries.is_empty() {
            format!("No age identities found at {}", identity_path)
        } else {
            format!(
                "Loaded {} age identity/identities from {}",
                identity_file_entries.len(),
                identity_path
            )
        },
    ));

    if !current_age_cfg.config_repo_path.is_empty() {
        let configured = fs::canonicalize(&current_age_cfg.config_repo_path)
            .unwrap_or_else(|_| PathBuf::from(&current_age_cfg.config_repo_path));
        let actual = fs::canonicalize(&repo_root).unwrap_or_else(|_| repo_root.clone());
        checks.push(check(
            "age-config-repo-path",
            if configured == actual { "ok" } else { "warn" },
            if configured == actual {
                format!("configRepoPath matches {}", actual.display())
            } else {
                format!(
                    "configRepoPath points to {} but repo discovery resolved {}",
                    configured.display(),
                    actual.display()
                )
            },
        ));
    }

    checks.push(match ykman_probe {
        Some(ref probe) if probe.success() => {
            if connected_serials.is_empty() {
                check(
                    "ykman",
                    "warn",
                    "ykman is available but no YubiKey serials are connected",
                )
            } else {
                check(
                    "ykman",
                    "ok",
                    format!("Connected serials: {}", connected_serials.join(", ")),
                )
            }
        }
        Some(ref probe) => check("ykman", "error", probe.summary_line()),
        None => check(
            "ykman",
            "error",
            "ykman not found in PATH. Enable keystone.hardwareKey on this host.",
        ),
    });

    checks.push(match age_probe {
        Some(ref probe) if probe.success() => check(
            "age-plugin-yubikey",
            "ok",
            "age-plugin-yubikey can talk to the currently connected device(s)",
        ),
        Some(ref probe) => check("age-plugin-yubikey", "error", probe.summary_line()),
        None => check(
            "age-plugin-yubikey",
            "error",
            "age-plugin-yubikey not found in PATH. Enable keystone.hardwareKey on this host.",
        ),
    });

    checks.push(match fido_probe {
        Some(ref probe) if probe.success() => {
            let output = probe.summary_line();
            if output.contains("No FIDO2 devices found.") {
                check("fido2-device", "warn", output)
            } else {
                check("fido2-device", "ok", output)
            }
        }
        Some(ref probe) => check("fido2-device", "error", probe.summary_line()),
        None => check(
            "fido2-device",
            "error",
            "systemd-cryptenroll not found in PATH.",
        ),
    });

    let disk_device = configured_disk_unlock_device(&storage_type);
    checks.push(match disk_unlock_status.as_ref() {
        Some(status) => {
            let status_level = if status.fido2_enrolled { "ok" } else { "warn" };
            check(
                "disk-unlock",
                status_level,
                format!(
                    "{} (TPM enrolled: {}, FIDO2 enrolled: {})",
                    status.device, status.tpm_enrolled, status.fido2_enrolled
                ),
            )
        }
        None => {
            let applicability = if tpm_enabled && secure_boot_enabled {
                "warn"
            } else {
                "info"
            };
            check(
                "disk-unlock",
                applicability,
                format!(
                    "No {} file found. Expected device {}",
                    DISK_UNLOCK_STATUS_FILE, disk_device
                ),
            )
        }
    });

    let configured_age_identities = current_age_cfg
        .identities
        .iter()
        .map(|identity| ConfiguredAgeIdentityStatus {
            serial: identity.serial.clone(),
            identity: identity.identity.clone(),
            present_in_identity_file: identity_file_entries.iter().any(|entry| {
                entry.identity == identity.identity
                    && entry.serial.as_deref() == Some(identity.serial.as_str())
            }),
            connected: connected_serials
                .iter()
                .any(|serial| serial == &identity.serial),
        })
        .collect::<Vec<_>>();

    let current_identity_map = current_age_cfg
        .identities
        .iter()
        .map(|identity| (identity.identity.as_str(), identity.serial.as_str()))
        .collect::<BTreeMap<_, _>>();

    let registered_keys = selected_keys
        .iter()
        .map(|(user, name, key)| {
            let age_serial = key
                .age_identity
                .as_deref()
                .and_then(|identity| current_identity_map.get(identity).copied())
                .map(str::to_string);
            let live_presence = match age_serial.as_deref() {
                Some(serial)
                    if connected_serials
                        .iter()
                        .any(|connected| connected == serial) =>
                {
                    "connected".to_string()
                }
                Some(_) => "configured-but-not-connected".to_string(),
                None if key.age_identity.is_some() => "configured-but-unmapped".to_string(),
                None => "not-mapped".to_string(),
            };

            RegisteredHardwareKeyStatus {
                user: user.clone(),
                name: name.clone(),
                description: key.description.clone(),
                public_key_kind: ssh_public_key_kind(&key.public_key),
                public_key_comment: ssh_public_key_comment(&key.public_key),
                root_access: root_refs.contains(&format!("{}/{}", user, name)),
                age_identity: key.age_identity.clone(),
                current_user_age_identity_configured: key
                    .age_identity
                    .as_deref()
                    .map(|identity| current_identity_map.contains_key(identity))
                    .unwrap_or(false),
                current_user_age_serial: age_serial,
                live_presence,
            }
        })
        .collect::<Vec<_>>();

    if registered_keys
        .iter()
        .all(|key| key.public_key_kind.starts_with("sk-"))
    {
        checks.push(check(
            "ssh-public-keys",
            "ok",
            "All selected SSH hardware keys use security-key SSH key types",
        ));
    } else {
        let invalid = registered_keys
            .iter()
            .filter(|key| !key.public_key_kind.starts_with("sk-"))
            .map(|key| format!("{}/{}", key.user, key.name))
            .collect::<Vec<_>>();
        checks.push(check(
            "ssh-public-keys",
            "error",
            format!(
                "Non-security-key SSH public keys found: {}",
                invalid.join(", ")
            ),
        ));
    }

    if !configured_age_identities.is_empty()
        && registered_keys.iter().all(|key| key.age_identity.is_none())
    {
        notes.push(
            "Configured age identities are present, but registered SSH hardware keys do not set keystone.keys.<user>.hardwareKeys.<key>.ageIdentity. Full per-key SSH↔age correlation is therefore not yet possible."
                .to_string(),
        );
    }

    if current_age_cfg.secrets_flake_input.is_some() {
        notes.push(
            "A separate agenix secrets flake input is configured. `ks hardware-key secrets` is the planned home for recipient management and rekey orchestration."
                .to_string(),
        );
    }
    if detect_same_repo_secrets_layout(&repo_root, secrets_repo.as_deref()) {
        notes.push(
            "A same-repo agenix layout was detected. `ks hardware-key secrets` should manage recipients and rekey in place here without a separate flake-input update step."
                .to_string(),
        );
    }

    let selector = selected_selector;
    let mut report = HardwareKeyDoctorReport {
        repo_root: repo_root.display().to_string(),
        host,
        current_user,
        selector,
        checks,
        registered_keys,
        configured_age_identities,
        notes,
        markdown: String::new(),
    };
    report.markdown = markdown_for_doctor(&report, disk_unlock_status.as_ref());
    Ok(report)
}

fn selector_to_string(selector: &Selector) -> Option<String> {
    match selector {
        Selector::CurrentUserOrAll => None,
        Selector::User(user) => Some(user.clone()),
        Selector::Key { user, key } => Some(format!("{}/{}", user, key)),
    }
}

pub async fn execute_secrets_todo(
    flake_override: Option<&std::path::Path>,
) -> Result<HardwareKeySecretsTodo> {
    let repo_root = repo::find_repo(flake_override)?;
    let host = repo::resolve_current_host(&repo_root)
        .await?
        .ok_or_else(|| anyhow!("Could not resolve current host from hosts.nix"))?;
    let current_user = repo::resolve_current_hm_user(&repo_root, &host).await?;
    let eval = eval_doctor_bundle(&repo_root, &host, current_user.as_deref()).await?;
    let current_age_cfg = eval.age_yubikey;
    let secrets_repo = eval.secrets_repo;

    let mut detected_layouts = Vec::new();
    if let Some(input) = current_age_cfg.secrets_flake_input.as_deref() {
        detected_layouts.push(format!(
            "flake-input workflow: rekey managed checkout and update flake input `{}`",
            input
        ));
    }
    if repo_root.join("agenix-secrets").is_dir() {
        detected_layouts
            .push("local agenix-secrets checkout present under the config repo".to_string());
    }
    if detect_same_repo_secrets_layout(&repo_root, secrets_repo.as_deref()) {
        detected_layouts.push(
            "same-repo workflow: manage recipients and rekey secrets directly in the config repo"
                .to_string(),
        );
    }
    if detected_layouts.is_empty() {
        detected_layouts.push(
            "manual workflow only detected; no flake-input or same-repo secrets layout was inferred"
                .to_string(),
        );
    }

    let plans = vec![
        "Update agenix recipients from registered hardware-key metadata before rekeying secrets."
            .to_string(),
        "Support separate `agenix-secrets` flake inputs by committing/pushing that checkout and then updating the parent flake lock."
            .to_string(),
        "Support same-repo secrets layouts by editing and rekeying in place without a flake-input update step."
            .to_string(),
        "Reconcile `keystone.secrets.repo`, local checkout discovery, and home-manager `ageYubikey` settings so the workflow is source-of-truth driven."
            .to_string(),
    ];

    let mut todo = HardwareKeySecretsTodo {
        repo_root: repo_root.display().to_string(),
        host,
        current_user,
        implemented: false,
        detected_layouts,
        plans,
        markdown: String::new(),
    };
    todo.markdown = markdown_for_secrets(&todo);
    Ok(todo)
}

pub fn render_doctor(report: &HardwareKeyDoctorReport) -> Result<()> {
    render_markdown(&report.markdown)
}

pub fn render_secrets_todo(todo: &HardwareKeySecretsTodo) -> Result<()> {
    render_markdown(&todo.markdown)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_selector_accepts_user_and_key() {
        assert!(matches!(
            parse_selector(Some("ncrmro")).unwrap(),
            Selector::User(user) if user == "ncrmro"
        ));
        assert!(matches!(
            parse_selector(Some("ncrmro/yubi-black")).unwrap(),
            Selector::Key { user, key } if user == "ncrmro" && key == "yubi-black"
        ));
    }

    #[test]
    fn parse_selector_rejects_invalid_path() {
        assert!(parse_selector(Some("a/b/c")).is_err());
    }

    #[test]
    fn parse_identity_file_reads_serial_annotations() {
        let entries = parse_identity_file(
            r#"# serial:36854515
AGE-PLUGIN-YUBIKEY-AAAA
# serial:36862273
AGE-PLUGIN-YUBIKEY-BBBB
"#,
        );
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].serial.as_deref(), Some("36854515"));
        assert_eq!(entries[1].identity, "AGE-PLUGIN-YUBIKEY-BBBB");
    }

    #[test]
    fn detect_same_repo_layout_uses_repo_files() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(temp.path().join("secrets.nix"), "{}").unwrap();
        assert!(detect_same_repo_secrets_layout(temp.path(), None));
    }
}
