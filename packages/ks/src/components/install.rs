//! Install screen — streamlined installer flow for pre-baked ISOs.
//!
//! When the TUI boots on an ISO with either an embedded flake repo at
//! `/etc/keystone/install-repo/` or a legacy config bundle at
//! `/etc/keystone/install-config/`, this screen drives the install:
//!
//! 1. **Host selection** — Choose the target host from the embedded flake repo
//! 2. **Summary** — Show the selected config (hostname, storage, user)
//! 3. **Disk selection** — Choose the destination disk explicitly
//! 4. **Confirm** — Final warning before erasing the disk
//! 5. **Install** — Run disko + hardware capture + local commit + nixos-install
//! 6. **Done** — Prompt to remove USB and reboot

use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command as StdCommand, Stdio};

use anyhow::{Context, Result as AnyhowResult};
use crossterm::event::{Event, KeyCode, KeyEventKind};
use rnix::{Root, SyntaxKind, SyntaxNode};
use serde::Deserialize;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::action::Action;
use crate::component::Component;
use crate::disk::DiskEntry;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

const INSTALL_REPO_PATH: &str = "/etc/keystone/install-repo";
const INSTALL_CONFIG_PATH: &str = "/etc/keystone/install-config";
const INSTALL_KEYSTONE_PATH: &str = "/etc/keystone/install-keystone";
const INSTALL_METADATA_DIR: &str = "/etc/keystone/install-metadata";
const WRITABLE_INSTALL_REPO_PATH: &str = "/tmp/keystone-install-repo";
const VENDORED_KEYSTONE_INPUT_DIR: &str = ".keystone-input";
const DEFAULT_INSTALLED_REPO_NAME: &str = "keystone-config";
const GENERATED_HARDWARE_FILENAME: &str = "hardware-generated.nix";
const FIRST_BOOT_MARKER: &str = ".first-boot-pending";
const INITIAL_INSTALL_COMMIT_MESSAGE: &str = "feat: initial Keystone configuration";

#[derive(Debug, Clone)]
pub enum InstallSource {
    EmbeddedRepo {
        repo_dir: PathBuf,
        repo_name: String,
        targets: Vec<InstallTarget>,
    },
    PrebakedConfig,
}

#[derive(Debug, Clone)]
pub struct InstallTarget {
    pub flake_host: String,
    pub hostname: String,
    pub system: Option<String>,
    pub storage_type: Option<String>,
    pub hardware_path: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct InstallTargetJson {
    hostname: String,
    system: Option<String>,
    storage_type: Option<String>,
    hardware_path: String,
}

/// Configuration parsed from the embedded installer repo or legacy config bundle.
#[derive(Debug, Clone)]
pub struct InstallerConfig {
    pub source: InstallSource,
    pub config_dir: PathBuf,
    pub flake_host: String,
    pub hostname: String,
    pub username: Option<String>,
    pub repo_owner: Option<String>,
    pub github_username: Option<String>,
    pub storage_type: Option<String>,
    pub disk_device: Option<String>,
    pub hardware_path: Option<PathBuf>,
}

impl InstallerConfig {
    /// Detect installer mode by checking for embedded repo or config at the well-known paths.
    ///
    /// The ISO filesystem is read-only (squashfs). Legacy config bundles are
    /// copied to a writable tmpdir before returning. Embedded repos are copied
    /// after host selection so disk choice can patch the selected host's
    /// hardware file.
    pub fn detect() -> AnyhowResult<Option<Self>> {
        let repo_dir = Path::new(INSTALL_REPO_PATH);
        if repo_dir.exists() {
            let targets = load_install_targets(repo_dir)?;
            let repo_name = read_install_metadata("repo-name")
                .unwrap_or_else(|| DEFAULT_INSTALLED_REPO_NAME.to_string());
            return Ok(Some(Self {
                source: InstallSource::EmbeddedRepo {
                    repo_dir: repo_dir.to_path_buf(),
                    repo_name,
                    targets,
                },
                config_dir: repo_dir.to_path_buf(),
                flake_host: String::new(),
                hostname: String::new(),
                username: read_install_metadata("admin-username"),
                repo_owner: read_install_metadata("repo-owner")
                    .or_else(|| read_install_metadata("admin-username")),
                github_username: None,
                storage_type: None,
                disk_device: None,
                hardware_path: None,
            }));
        }

        let config_dir = Path::new(INSTALL_CONFIG_PATH);
        if !config_dir.exists() {
            return Ok(None);
        }

        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        let username = std::fs::read_to_string(config_dir.join("username"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let github_username = std::fs::read_to_string(config_dir.join("github_username"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        // Copy to writable location so we can inject disk selection later
        let writable_dir = PathBuf::from("/tmp/keystone-install-config");
        let effective_dir = if Self::copy_to_writable(config_dir, &writable_dir).is_ok() {
            writable_dir
        } else {
            config_dir.to_path_buf()
        };

        // Parse storage type and disk device from configuration.nix
        let (storage_type, disk_device) =
            Self::parse_configuration_nix(&effective_dir).unwrap_or((None, None));

        // Treat the placeholder as "no disk configured"
        let disk_device = disk_device.filter(|d| d != crate::template::DISK_PLACEHOLDER);

        Ok(Some(Self {
            source: InstallSource::PrebakedConfig,
            config_dir: effective_dir,
            flake_host: hostname.clone(),
            hostname,
            repo_owner: username.clone(),
            username,
            github_username,
            storage_type,
            disk_device,
            hardware_path: None,
        }))
    }

    /// Recursively copy config files to a writable tmpdir for disk injection.
    fn copy_to_writable(src: &Path, dst: &Path) -> std::io::Result<()> {
        if dst.exists() {
            std::fs::remove_dir_all(dst)?;
        }
        Self::copy_dir_recursive(src, dst)
    }

    /// Recursively copy a directory tree.
    fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
        std::fs::create_dir_all(dst)?;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            let src_path = entry.path();
            let dst_path = dst.join(entry.file_name());
            if src_path.is_dir() {
                Self::copy_dir_recursive(&src_path, &dst_path)?;
            } else {
                std::fs::copy(&src_path, &dst_path)?;
            }
        }
        Ok(())
    }

    /// Find the per-host hardware.nix or configuration.nix path.
    ///
    /// With the mkSystemFlake layout, files live at `hosts/<hostname>/hardware.nix`.
    /// Falls back to flat layout for backward compatibility.
    fn find_host_file(config_dir: &Path, hostname: &str, filename: &str) -> Option<PathBuf> {
        // Try hosts/<hostname>/<filename> first (mkSystemFlake layout)
        let host_path = config_dir.join("hosts").join(hostname).join(filename);
        if host_path.exists() {
            return Some(host_path);
        }
        // Fall back to flat layout
        let flat_path = config_dir.join(filename);
        if flat_path.exists() {
            return Some(flat_path);
        }
        None
    }

    /// Extract storage type and disk device from hardware.nix or configuration.nix
    /// via rnix AST. Tries the mkSystemFlake hosts/ layout first.
    fn parse_configuration_nix(config_dir: &Path) -> Option<(Option<String>, Option<String>)> {
        // Read hostname to find host-specific files
        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        // With mkSystemFlake, storage config lives in hardware.nix.
        // Try hardware.nix first, then configuration.nix for backward compat.
        let files_to_try: Vec<PathBuf> = if hostname.is_empty() {
            vec![
                config_dir.join("hardware.nix"),
                config_dir.join("configuration.nix"),
            ]
        } else {
            vec![
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("hardware.nix"),
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("configuration.nix"),
                config_dir.join("hardware.nix"),
                config_dir.join("configuration.nix"),
            ]
        };

        let content = files_to_try
            .iter()
            .find_map(|p| std::fs::read_to_string(p).ok())?;

        let root = rnix::Root::parse(&content);
        let syntax = root.syntax();

        let mut storage_type = None;
        let mut disk_device = None;

        // Walk the AST looking for `storage.type = "..."` and `storage.devices = [ "..." ]`
        for node in syntax.descendants() {
            if node.kind() != rnix::SyntaxKind::NODE_ATTRPATH_VALUE {
                continue;
            }

            let path_text = Self::attr_path_text(&node);

            // Match `type` inside a `storage` context (storage.type = "zfs")
            if path_text.ends_with(".type") || path_text == "type" {
                if let Some(val) = Self::extract_string_literal(&node) {
                    if val == "zfs" || val == "ext4" {
                        storage_type = Some(val);
                    }
                }
            }

            // Match `devices` inside storage — extract first element of the list
            if path_text.ends_with(".devices") || path_text == "devices" {
                for descendant in node.descendants() {
                    if descendant.kind() == rnix::SyntaxKind::NODE_LIST {
                        // Get the first string in the list
                        for child in descendant.children() {
                            if child.kind() == rnix::SyntaxKind::NODE_STRING {
                                let text = child.text().to_string();
                                let trimmed = text.trim_matches('"');
                                if !trimmed.is_empty() {
                                    disk_device = Some(trimmed.to_string());
                                    break;
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }

        Some((storage_type, disk_device))
    }

    /// Get the dot-joined attribute path text from a NODE_ATTRPATH_VALUE.
    fn attr_path_text(node: &rnix::SyntaxNode) -> String {
        nix_attr_path_text(node)
    }

    /// Extract a string literal value from a NODE_ATTRPATH_VALUE node.
    fn extract_string_literal(node: &rnix::SyntaxNode) -> Option<String> {
        nix_extract_string(node)
    }

    /// Replace the disk placeholder in hardware.nix (or configuration.nix for legacy layout).
    fn inject_disk_device(config_dir: &Path, device: &str) -> std::io::Result<()> {
        // With mkSystemFlake layout, disk device is in hardware.nix.
        // Try all candidate files and replace the placeholder wherever found.
        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        let mut candidates: Vec<PathBuf> = Vec::new();
        if !hostname.is_empty() {
            candidates.push(
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("hardware.nix"),
            );
            candidates.push(
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("configuration.nix"),
            );
        }
        candidates.push(config_dir.join("hardware.nix"));
        candidates.push(config_dir.join("configuration.nix"));

        for path in &candidates {
            if let Ok(content) = std::fs::read_to_string(path) {
                if content.contains("__KEYSTONE_DISK__") {
                    let updated = content.replace("__KEYSTONE_DISK__", device);
                    std::fs::write(path, updated)?;
                    return Ok(());
                }
            }
        }

        Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "No file containing __KEYSTONE_DISK__ placeholder found",
        ))
    }

    fn inject_disk_into_hardware(hardware_path: &Path, device: &str) -> std::io::Result<()> {
        let content = std::fs::read_to_string(hardware_path)?;
        let root = Root::parse(&content);
        if !root.errors().is_empty() {
            let errors: Vec<_> = root.errors().iter().map(|e| e.to_string()).collect();
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Failed to parse {}: {}",
                    hardware_path.display(),
                    errors.join("; ")
                ),
            ));
        }
        let syntax = root.syntax();

        let attr_node = nix_find_attr(&syntax, "keystone.os.storage.devices").ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Could not find keystone.os.storage.devices in {}",
                    hardware_path.display()
                ),
            )
        })?;

        // Find the NODE_LIST within the attr value to splice.
        let list_node = attr_node
            .descendants()
            .find(|n| n.kind() == SyntaxKind::NODE_LIST)
            .ok_or_else(|| {
                std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!(
                        "keystone.os.storage.devices is not a list in {}",
                        hardware_path.display()
                    ),
                )
            })?;

        let range = list_node.text_range();
        let start = usize::from(range.start());
        let end = usize::from(range.end());

        // Derive indentation from the attr node's line.
        let line_start = content[..start].rfind('\n').map_or(0, |p| p + 1);
        let indent: String = content[line_start..]
            .chars()
            .take_while(|c| c.is_whitespace())
            .collect();

        let replacement = format!("[\n{indent}  \"{device}\"\n{indent}]");
        let mut updated = format!("{}{}{}", &content[..start], replacement, &content[end..]);
        if !updated.ends_with('\n') {
            updated.push('\n');
        }

        std::fs::write(hardware_path, updated)?;
        Ok(())
    }

    fn inject_selected_disk(&self, device: &str) -> std::io::Result<()> {
        if let Some(hardware_path) = self.hardware_path.as_ref() {
            Self::inject_disk_into_hardware(hardware_path, device)
        } else {
            Self::inject_disk_device(&self.config_dir, device)
        }
    }

    fn installed_repo_name(&self) -> &str {
        match &self.source {
            InstallSource::EmbeddedRepo { repo_name, .. } => repo_name.as_str(),
            InstallSource::PrebakedConfig => DEFAULT_INSTALLED_REPO_NAME,
        }
    }

    fn installed_repo_owner(&self) -> &str {
        self.repo_owner
            .as_deref()
            .or(self.username.as_deref())
            .unwrap_or("keystone")
    }
}

fn read_install_metadata(name: &str) -> Option<String> {
    std::fs::read_to_string(Path::new(INSTALL_METADATA_DIR).join(name))
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn read_install_metadata_lines(name: &str) -> Vec<String> {
    std::fs::read_to_string(Path::new(INSTALL_METADATA_DIR).join(name))
        .ok()
        .map(|contents| {
            contents
                .lines()
                .map(str::trim)
                .filter(|line| !line.is_empty())
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn merge_authorized_keys(existing: Option<&str>, additional: &[String]) -> String {
    let mut merged: Vec<String> = existing
        .into_iter()
        .flat_map(|contents| contents.lines())
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();

    for key in additional {
        if !merged.iter().any(|existing_key| existing_key == key) {
            merged.push(key.clone());
        }
    }

    if merged.is_empty() {
        String::new()
    } else {
        format!("{}\n", merged.join("\n"))
    }
}

fn load_install_targets(repo_dir: &Path) -> AnyhowResult<Vec<InstallTarget>> {
    let targets_path = Path::new(INSTALL_METADATA_DIR).join("targets.json");
    let targets_json = std::fs::read_to_string(&targets_path).with_context(|| {
        format!(
            "Failed to read installer target metadata at {} for repo {}",
            targets_path.display(),
            repo_dir.display()
        )
    })?;

    let targets: BTreeMap<String, InstallTargetJson> = serde_json::from_str(&targets_json)
        .context("Failed to parse installer target metadata JSON")?;

    let mut parsed: Vec<InstallTarget> = targets
        .into_iter()
        .map(|(flake_host, target)| InstallTarget {
            flake_host,
            hostname: target.hostname,
            system: target.system,
            storage_type: target.storage_type,
            hardware_path: target.hardware_path,
        })
        .collect();
    parsed.sort_by(|left, right| left.flake_host.cmp(&right.flake_host));
    Ok(parsed)
}

fn copy_repo_to_writable(src: &Path, dst: &Path) -> AnyhowResult<()> {
    if dst.exists() {
        std::fs::remove_dir_all(dst)
            .with_context(|| format!("Failed to remove {}", dst.display()))?;
    }

    std::fs::create_dir_all(dst).with_context(|| format!("Failed to create {}", dst.display()))?;

    let status = StdCommand::new("cp")
        .args([
            "-a",
            &format!("{}/.", src.display()),
            &dst.display().to_string(),
        ])
        .status()
        .with_context(|| {
            format!(
                "Failed to copy repo from {} to {}",
                src.display(),
                dst.display()
            )
        })?;

    if !status.success() {
        anyhow::bail!(
            "cp -a failed while copying installer repo to {}",
            dst.display()
        );
    }

    // The embedded repo comes from a read-only store-style snapshot. After
    // copying it into /tmp or the installed system, the installer needs to
    // mutate files like flake.lock and hardware.nix, so add owner write bits
    // recursively while preserving the rest of the copied metadata.
    let chmod_status = StdCommand::new("chmod")
        .args(["-R", "u+w", &dst.display().to_string()])
        .status()
        .with_context(|| format!("Failed to make copied repo writable at {}", dst.display()))?;

    if !chmod_status.success() {
        anyhow::bail!(
            "chmod -R u+w failed while preparing writable repo at {}",
            dst.display()
        );
    }

    Ok(())
}

fn rewrite_keystone_lock_input(repo_dir: &Path, keystone_input_dir: &Path) -> AnyhowResult<()> {
    let status = StdCommand::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "flake",
            "lock",
            "--override-input",
            "keystone",
            &format!("path:{}", keystone_input_dir.display()),
        ])
        .current_dir(repo_dir)
        .status()
        .with_context(|| {
            format!(
                "Failed to rewrite keystone flake input in {}",
                repo_dir.display()
            )
        })?;

    if !status.success() {
        anyhow::bail!(
            "nix flake lock --override-input keystone failed in {}",
            repo_dir.display()
        );
    }

    Ok(())
}

fn vendor_embedded_keystone_input(repo_dir: &Path) -> AnyhowResult<Option<PathBuf>> {
    let embedded_keystone = Path::new(INSTALL_KEYSTONE_PATH);
    if !embedded_keystone.exists() {
        return Ok(None);
    }

    let vendored_dir = repo_dir.join(VENDORED_KEYSTONE_INPUT_DIR);
    copy_repo_to_writable(embedded_keystone, &vendored_dir).with_context(|| {
        format!(
            "Failed to copy embedded keystone input from {} to {}",
            embedded_keystone.display(),
            vendored_dir.display()
        )
    })?;

    rewrite_keystone_lock_input(repo_dir, &vendored_dir)?;
    Ok(Some(vendored_dir))
}

fn normalize_staged_install_repo(repo_dir: &Path, source_lock_path: &Path) -> Result<(), String> {
    let vendored_dir = repo_dir.join(VENDORED_KEYSTONE_INPUT_DIR);
    if !vendored_dir.exists() {
        return Ok(());
    }

    if !source_lock_path.is_file() {
        return Err(format!(
            "Cannot normalize {} because {} is missing",
            vendored_dir.display(),
            source_lock_path.display()
        ));
    }

    let target_lock_path = repo_dir.join("flake.lock");
    let source_lock = std::fs::read(source_lock_path)
        .map_err(|e| format!("Failed to read {}: {}", source_lock_path.display(), e))?;
    std::fs::write(&target_lock_path, source_lock).map_err(|e| {
        format!(
            "Failed to restore {} from {}: {}",
            target_lock_path.display(),
            source_lock_path.display(),
            e
        )
    })?;

    std::fs::remove_dir_all(&vendored_dir)
        .map_err(|e| format!("Failed to remove {}: {}", vendored_dir.display(), e))?;

    Ok(())
}

fn normalize_installed_repo_state(repo_dir: &Path) -> Result<(), String> {
    normalize_staged_install_repo(repo_dir, &Path::new(INSTALL_REPO_PATH).join("flake.lock"))
}

// --- rnix AST helpers ---

/// Join attr path segments, handling both bare idents (`foo`) and quoted string
/// keys (`"/"`) so paths like `fileSystems."/"` render correctly.
fn nix_attr_path_text(node: &SyntaxNode) -> String {
    node.children()
        .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)
        .map(|ap| {
            ap.children()
                .filter_map(|n| match n.kind() {
                    SyntaxKind::NODE_IDENT => Some(n.text().to_string()),
                    SyntaxKind::NODE_STRING => Some(n.text().to_string()),
                    _ => None,
                })
                .collect::<Vec<_>>()
                .join(".")
        })
        .unwrap_or_default()
}

/// Find the first `NODE_ATTRPATH_VALUE` descendant whose dot-joined attr path
/// matches `target_path`. Works for both attrset entries and `let` bindings.
fn nix_find_attr(root: &SyntaxNode, target_path: &str) -> Option<SyntaxNode> {
    root.descendants().find(|node| {
        node.kind() == SyntaxKind::NODE_ATTRPATH_VALUE && nix_attr_path_text(node) == target_path
    })
}

/// Extract a single string literal value from a `NODE_ATTRPATH_VALUE` node.
fn nix_extract_string(node: &SyntaxNode) -> Option<String> {
    // Skip the attrpath child and look at the value position for a string.
    for child in node.children() {
        if child.kind() == SyntaxKind::NODE_STRING {
            let text = child.text().to_string();
            let trimmed = text.trim_matches('"');
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    // Also check one level deeper (value might be wrapped).
    for descendant in node.descendants() {
        if descendant.kind() == SyntaxKind::NODE_STRING {
            let text = descendant.text().to_string();
            let trimmed = text.trim_matches('"');
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    None
}

/// Extract all string elements from a `NODE_LIST` that is the value of a
/// `NODE_ATTRPATH_VALUE` node.
fn nix_extract_string_list(node: &SyntaxNode) -> Vec<String> {
    let mut values = Vec::new();
    for descendant in node.descendants() {
        if descendant.kind() == SyntaxKind::NODE_LIST {
            for child in descendant.children() {
                if child.kind() == SyntaxKind::NODE_STRING {
                    let text = child.text().to_string();
                    let trimmed = text.trim_matches('"').to_string();
                    if !trimmed.is_empty() && !values.contains(&trimmed) {
                        values.push(trimmed);
                    }
                }
            }
            break;
        }
    }
    values
}

fn parse_hardware_disk_device(hardware_path: &Path) -> Option<String> {
    let content = std::fs::read_to_string(hardware_path).ok()?;
    let root = Root::parse(&content);
    let syntax = root.syntax();
    nix_find_attr(&syntax, "keystone.os.storage.devices")
        .map(|node| nix_extract_string_list(&node))
        .unwrap_or_default()
        .into_iter()
        .find(|d| d.contains("/dev/disk/by-id/"))
}

fn is_placeholder_host_id(host_id: &str) -> bool {
    host_id == crate::template::HOST_ID_PLACEHOLDER
}

fn is_valid_host_id(host_id: &str) -> bool {
    host_id.len() == 8
        && host_id.chars().all(|ch| ch.is_ascii_hexdigit())
        && !is_placeholder_host_id(host_id)
}

fn is_placeholder_storage_device(device: &str) -> bool {
    device == crate::template::DISK_PLACEHOLDER || device.contains("YOUR-")
}

fn extract_stable_disk_identifiers(config: &str) -> Vec<String> {
    let root = Root::parse(config);
    let syntax = root.syntax();
    let mut ids = Vec::new();

    for node in syntax.descendants() {
        if node.kind() == SyntaxKind::NODE_STRING {
            let text = node.text().to_string();
            let trimmed = text.trim_matches('"');
            if trimmed.contains("/dev/disk/by-")
                || trimmed.contains("UUID=")
                || trimmed.contains("PARTUUID=")
            {
                let value = trimmed.to_string();
                if !ids.contains(&value) {
                    ids.push(value);
                }
            }
        }
    }

    ids
}

fn escape_nix_string(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace("${", "\\${")
        .replace('\n', "\\n")
}

fn ensure_marker_gitignore_contents(current: Option<&str>) -> String {
    let existing = current.unwrap_or_default();
    if existing
        .lines()
        .any(|line| line.trim() == FIRST_BOOT_MARKER)
    {
        if existing.ends_with('\n') {
            return existing.to_string();
        }
        return format!("{existing}\n");
    }

    if existing.trim().is_empty() {
        format!("{FIRST_BOOT_MARKER}\n")
    } else if existing.ends_with('\n') {
        format!("{existing}{FIRST_BOOT_MARKER}\n")
    } else {
        format!("{existing}\n{FIRST_BOOT_MARKER}\n")
    }
}

fn strip_generated_storage_assignments(generated_hardware: &str) -> String {
    let storage_prefixes = ["fileSystems.", "swapDevices", "boot.initrd.luks.devices."];
    let root = Root::parse(generated_hardware);
    if !root.errors().is_empty() {
        // If the generated hardware config can't be parsed, return it unchanged
        // rather than risk corrupting the output with bad range calculations.
        return generated_hardware.to_string();
    }
    let syntax = root.syntax();

    // Collect text ranges of storage-related attr assignments to exclude.
    let mut exclude: Vec<std::ops::Range<usize>> = Vec::new();
    for node in syntax.descendants() {
        if node.kind() != SyntaxKind::NODE_ATTRPATH_VALUE {
            continue;
        }
        let path = nix_attr_path_text(&node);
        if storage_prefixes
            .iter()
            .any(|prefix| path.starts_with(prefix) || path == "swapDevices")
        {
            let range = node.text_range();
            let start = usize::from(range.start());
            let mut end = usize::from(range.end());
            // Consume the trailing semicolon and whitespace/newline that follows
            // the node so we don't leave blank lines.
            let rest = &generated_hardware[end..];
            for ch in rest.chars() {
                if ch == ';' || ch == ' ' || ch == '\t' {
                    end += ch.len_utf8();
                } else if ch == '\n' {
                    end += 1;
                    break;
                } else {
                    break;
                }
            }
            exclude.push(start..end);
        }
    }

    // Reconstruct source, skipping excluded ranges.
    exclude.sort_by_key(|r| r.start);
    let mut sanitized = String::new();
    let mut cursor = 0;
    for range in &exclude {
        if range.start > cursor {
            sanitized.push_str(&generated_hardware[cursor..range.start]);
        }
        cursor = range.end;
    }
    if cursor < generated_hardware.len() {
        sanitized.push_str(&generated_hardware[cursor..]);
    }

    // Collapse runs of blank lines left by removals.
    let mut result = String::new();
    let mut blank_count = 0;
    for line in sanitized.lines() {
        if line.trim().is_empty() {
            blank_count += 1;
            if blank_count <= 1 {
                result.push('\n');
            }
        } else {
            blank_count = 0;
            result.push_str(line);
            result.push('\n');
        }
    }

    result.trim_end().to_string()
}

fn resolve_hardware_path(config: &InstallerConfig) -> Result<PathBuf, String> {
    if let Some(path) = config.hardware_path.clone() {
        return Ok(path);
    }

    InstallerConfig::find_host_file(&config.config_dir, &config.hostname, "hardware.nix")
        .ok_or_else(|| {
            format!(
                "Failed to locate hardware.nix for host {} in {}",
                config.hostname,
                config.config_dir.display()
            )
        })
}

fn build_reconciled_hardware_wrapper(
    current_hardware_nix: &str,
    selected_disk: Option<&str>,
) -> Result<String, String> {
    // Parse once, extract all values from the AST.
    let root = Root::parse(current_hardware_nix);
    if !root.errors().is_empty() {
        let errors: Vec<_> = root.errors().iter().map(|e| e.to_string()).collect();
        return Err(format!(
            "Failed to parse current hardware.nix: {}",
            errors.join("; ")
        ));
    }
    let syntax = root.syntax();

    let system = nix_find_attr(&syntax, "system")
        .and_then(|n| nix_extract_string(&n))
        .unwrap_or_else(|| "x86_64-linux".to_string());

    let host_id = nix_find_attr(&syntax, "networking.hostId")
        .and_then(|n| nix_extract_string(&n))
        .filter(|id| is_valid_host_id(id))
        .unwrap_or_else(crate::template::generate_host_id);

    let mut storage_devices = nix_find_attr(&syntax, "keystone.os.storage.devices")
        .map(|n| nix_extract_string_list(&n))
        .unwrap_or_default()
        .into_iter()
        .filter(|device| !is_placeholder_storage_device(device))
        .collect::<Vec<_>>();
    if storage_devices.is_empty() {
        if let Some(device) = selected_disk {
            storage_devices.push(device.to_string());
        }
    }
    if storage_devices.is_empty() {
        return Err(
            "Could not determine keystone.os.storage.devices while reconciling hardware.nix."
                .to_string(),
        );
    }

    let storage_mode = nix_find_attr(&syntax, "keystone.os.storage.mode")
        .and_then(|n| nix_extract_string(&n))
        .unwrap_or_else(|| "single".to_string());

    let remote_unlock_network_module =
        nix_find_attr(&syntax, "keystone.os.remoteUnlock.networkModule")
            .and_then(|n| nix_extract_string(&n));

    let rendered_storage_devices = storage_devices
        .iter()
        .map(|device| format!("        \"{}\"\n", escape_nix_string(device)))
        .collect::<String>();
    let rendered_remote_unlock = remote_unlock_network_module
        .map(|module| {
            format!(
                "\n      keystone.os.remoteUnlock.networkModule = \"{}\";\n",
                escape_nix_string(&module)
            )
        })
        .unwrap_or_default();

    Ok(format!(
        r#"let
  system = "{system}";
in
{{
  inherit system;

  module =
    {{
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }}:
    {{
      imports = [
        ./{generated_hardware_filename}
      ];

      networking.hostId = "{host_id}";

      keystone.os.storage.devices = [
{rendered_storage_devices}      ];
      keystone.os.storage.mode = "{storage_mode}";
{rendered_remote_unlock}      hardware.cpu.intel.updateMicrocode =
        lib.mkDefault config.hardware.enableRedistributableFirmware;
      hardware.enableRedistributableFirmware = true;
    }};
}}
"#,
        system = escape_nix_string(&system),
        generated_hardware_filename = GENERATED_HARDWARE_FILENAME,
        host_id = escape_nix_string(&host_id),
        rendered_storage_devices = rendered_storage_devices,
        storage_mode = escape_nix_string(&storage_mode),
        rendered_remote_unlock = rendered_remote_unlock,
    ))
}

/// The phases of the install flow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallPhase {
    /// Select the target host from the embedded repo.
    HostSelection,
    /// Show config summary, waiting for user to proceed.
    Summary,
    /// Select a disk device (shown when no disk was pre-configured).
    DiskSelection,
    /// Confirm disk erasure.
    Confirm,
    /// Running disko + nixos-install.
    Installing,
    /// Install completed successfully.
    Done,
    /// Install failed.
    Failed(String),
}

/// Messages from the install subprocess.
pub enum InstallMessage {
    Output(String),
    PhaseComplete(String),
    Finished(InstallResult),
    DisksDiscovered(Vec<DiskEntry>),
}

#[derive(Clone, Debug)]
pub enum InstallResult {
    Success,
    Failed(String),
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CommandSpec {
    program: String,
    args: Vec<String>,
}

pub struct InstallScreen {
    config: InstallerConfig,
    phase: InstallPhase,
    available_hosts: Vec<InstallTarget>,
    selected_host_index: usize,
    /// Output log lines from the install process.
    output_lines: Vec<String>,
    scroll_offset: u16,
    auto_scroll: bool,
    /// Channel for receiving install subprocess messages.
    rx: Option<mpsc::UnboundedReceiver<InstallMessage>>,
    cancel_token: CancellationToken,
    /// Discovered disks for DiskSelection phase.
    available_disks: Vec<DiskEntry>,
    selected_disk_index: usize,
    /// Whether disk discovery is still running.
    discovering_disks: bool,
}

fn preferred_disk_index(disks: &[DiskEntry], preferred_disk: Option<&str>) -> usize {
    preferred_disk
        .and_then(|path| disks.iter().position(|disk| disk.by_id_path == path))
        .unwrap_or(0)
}

fn format_disk_summary(disk: &DiskEntry) -> String {
    let mut details = vec![disk.model.clone(), disk.size.clone()];
    if !disk.transport.is_empty() {
        details.push(disk.transport.clone());
    }

    format!("{} ({})", disk.by_id_path, details.join(", "))
}

fn format_available_disks(disks: &[DiskEntry], selected_disk: Option<&str>) -> String {
    if disks.is_empty() {
        return "Discovered disks: none".to_string();
    }

    let mut lines = vec!["Discovered disks:".to_string()];
    for disk in disks {
        let marker = if selected_disk.is_some_and(|path| path == disk.by_id_path) {
            "*"
        } else {
            "-"
        };
        lines.push(format!("  {} {}", marker, format_disk_summary(disk)));
    }

    lines.join("\n")
}

const HEADLESS_CONFIRMATION_TOKEN: &str = "destroy";

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum HeadlessSelectionSource {
    Requested,
    AutoSelected,
    Prompted,
}

fn format_numbered_available_disks(disks: &[DiskEntry], preferred_index: usize) -> String {
    if disks.is_empty() {
        return "Discovered disks: none".to_string();
    }

    let mut lines = vec!["Discovered disks:".to_string()];
    for (index, disk) in disks.iter().enumerate() {
        let mut line = format!("  {}. {}", index + 1, format_disk_summary(disk));
        if index == preferred_index {
            line.push_str("  [best guess]");
        }
        lines.push(line);
    }

    lines.join("\n")
}

fn parse_headless_disk_selection(
    input: &str,
    disk_count: usize,
    preferred_index: usize,
) -> Result<usize, String> {
    if disk_count == 0 {
        return Err("Install cancelled. No disks were available for selection.".to_string());
    }

    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Ok(preferred_index);
    }

    let selected = trimmed.parse::<usize>().map_err(|_| {
        format!(
            "Install cancelled. Expected a disk number between 1 and {}.",
            disk_count
        )
    })?;
    if !(1..=disk_count).contains(&selected) {
        return Err(format!(
            "Install cancelled. Expected a disk number between 1 and {}.",
            disk_count
        ));
    }

    Ok(selected - 1)
}

fn prompt_for_headless_disk_selection(
    host: &str,
    disks: &[DiskEntry],
    preferred_index: usize,
) -> Result<usize, String> {
    eprintln!("No --disk was provided for host '{}'.", host);
    eprintln!("Installer media is excluded from this list.");
    eprintln!(
        "{}",
        format_numbered_available_disks(disks, preferred_index)
    );
    eprintln!(
        "Press Enter to use {} or type a disk number between 1 and {}.",
        preferred_index + 1,
        disks.len()
    );
    eprint!("Disk> ");
    std::io::stderr()
        .flush()
        .map_err(|error| format!("Failed to flush disk selection prompt: {}", error))?;

    let mut selection = String::new();
    std::io::stdin()
        .read_line(&mut selection)
        .map_err(|error| format!("Failed to read disk selection: {}", error))?;

    parse_headless_disk_selection(&selection, disks.len(), preferred_index)
}

fn build_headless_confirmation_message(
    host: &str,
    selected_disk: &str,
    selection_source: HeadlessSelectionSource,
    disks: &[DiskEntry],
) -> String {
    let mut lines = Vec::new();

    match selection_source {
        HeadlessSelectionSource::Requested | HeadlessSelectionSource::Prompted => {
            lines.push(format!(
                "Headless install is ready for host '{}' on '{}'.",
                host, selected_disk
            ));
        }
        HeadlessSelectionSource::AutoSelected => {
            lines.push(format!("No --disk was provided for host '{}'.", host));
            lines.push(format!("Only available install disk: {}", selected_disk));
        }
    }

    lines.push(format!("This will erase all data on '{}'.", selected_disk));
    lines.push(String::new());
    lines.push(format_available_disks(disks, Some(selected_disk)));
    lines.push(String::new());
    lines.push(format!(
        "Type '{}' to confirm installation, or anything else to cancel.",
        HEADLESS_CONFIRMATION_TOKEN
    ));

    lines.join("\n")
}

fn confirm_headless_install(
    host: &str,
    selected_disk: &str,
    selection_source: HeadlessSelectionSource,
    disks: &[DiskEntry],
) -> Result<(), String> {
    eprintln!(
        "{}",
        build_headless_confirmation_message(host, selected_disk, selection_source, disks)
    );
    eprint!("Confirmation> ");
    std::io::stderr()
        .flush()
        .map_err(|error| format!("Failed to flush confirmation prompt: {}", error))?;

    let mut confirmation = String::new();
    std::io::stdin()
        .read_line(&mut confirmation)
        .map_err(|error| format!("Failed to read confirmation: {}", error))?;

    if confirmation.trim() != HEADLESS_CONFIRMATION_TOKEN {
        return Err(format!(
            "Install cancelled. Expected '{}' at the confirmation prompt.",
            HEADLESS_CONFIRMATION_TOKEN
        ));
    }

    Ok(())
}

impl InstallScreen {
    pub fn new(config: InstallerConfig) -> Self {
        let (phase, available_hosts) = match &config.source {
            InstallSource::EmbeddedRepo { targets, .. } if targets.is_empty() => (
                InstallPhase::Failed(
                    "No installable Linux hosts were found in /etc/keystone/install-repo."
                        .to_string(),
                ),
                Vec::new(),
            ),
            InstallSource::EmbeddedRepo { targets, .. } => {
                (InstallPhase::HostSelection, targets.clone())
            }
            InstallSource::PrebakedConfig => (InstallPhase::Summary, Vec::new()),
        };

        Self {
            config,
            phase,
            available_hosts,
            selected_host_index: 0,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            rx: None,
            cancel_token: CancellationToken::new(),
            available_disks: Vec::new(),
            selected_disk_index: 0,
            discovering_disks: false,
        }
    }

    #[cfg(test)]
    pub fn new_with_channel(
        config: InstallerConfig,
        rx: mpsc::UnboundedReceiver<InstallMessage>,
    ) -> Self {
        let (phase, available_hosts) = match &config.source {
            InstallSource::EmbeddedRepo { targets, .. } if targets.is_empty() => (
                InstallPhase::Failed(
                    "No installable Linux hosts were found in /etc/keystone/install-repo."
                        .to_string(),
                ),
                Vec::new(),
            ),
            InstallSource::EmbeddedRepo { targets, .. } => {
                (InstallPhase::HostSelection, targets.clone())
            }
            InstallSource::PrebakedConfig => (InstallPhase::Summary, Vec::new()),
        };

        Self {
            config,
            phase,
            available_hosts,
            selected_host_index: 0,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            rx: Some(rx),
            cancel_token: CancellationToken::new(),
            available_disks: Vec::new(),
            selected_disk_index: 0,
            discovering_disks: false,
        }
    }

    pub fn phase(&self) -> &InstallPhase {
        &self.phase
    }

    pub fn config(&self) -> &InstallerConfig {
        &self.config
    }

    pub fn output_lines(&self) -> &[String] {
        &self.output_lines
    }

    pub fn available_hosts(&self) -> &[InstallTarget] {
        &self.available_hosts
    }

    pub fn selected_host_index(&self) -> usize {
        self.selected_host_index
    }

    pub fn available_disks(&self) -> &[DiskEntry] {
        &self.available_disks
    }

    pub fn selected_disk_index(&self) -> usize {
        self.selected_disk_index
    }

    pub fn set_host_index(&mut self, index: usize) {
        self.selected_host_index = index;
    }

    fn set_disk_by_path(&mut self, disk_path: &str) -> Result<(), String> {
        let Some(index) = self
            .available_disks
            .iter()
            .position(|disk| disk.by_id_path == disk_path)
        else {
            let best_guess = self
                .available_disks
                .get(preferred_disk_index(
                    &self.available_disks,
                    self.config.disk_device.as_deref(),
                ))
                .map(|disk| disk.by_id_path.as_str());
            return Err(format!(
                "Requested disk '{}' was not found.\n{}\nBest guess: {}",
                disk_path,
                format_available_disks(&self.available_disks, best_guess),
                best_guess.unwrap_or("none")
            ));
        };

        self.selected_disk_index = index;
        Ok(())
    }

    /// Run the install headlessly — no TUI. Resolves disk selection using the
    /// same disk discovery as the TUI, prompting for a numbered choice when
    /// multiple installable disks remain, then requires an explicit
    /// confirmation prompt before destructive actions proceed.
    pub async fn run_headless(&mut self, disk_path: Option<&str>) -> Result<(), String> {
        // Phase 1: select host (copies repo, vendors keystone input)
        self.select_host();
        if let InstallPhase::Failed(msg) = &self.phase {
            return Err(msg.clone());
        }

        // Phase 2: discover disks
        eprintln!("Discovering disks...");
        let disks = crate::disk::discover_disks()
            .await
            .map_err(|e| format!("Disk discovery failed: {}", e))?;
        if disks.is_empty() {
            return Err("No installable disks found after excluding installer media.".to_string());
        }
        self.available_disks = disks;
        let selection_source = if let Some(disk_path) = disk_path {
            self.set_disk_by_path(disk_path)?;
            HeadlessSelectionSource::Requested
        } else if self.available_disks.len() == 1 {
            self.selected_disk_index = 0;
            HeadlessSelectionSource::AutoSelected
        } else {
            let preferred_index =
                preferred_disk_index(&self.available_disks, self.config.disk_device.as_deref());
            self.selected_disk_index = prompt_for_headless_disk_selection(
                &self.config.flake_host,
                &self.available_disks,
                preferred_index,
            )?;
            HeadlessSelectionSource::Prompted
        };
        let selected_disk = self.available_disks[self.selected_disk_index]
            .by_id_path
            .clone();
        eprintln!("Found {} installable disk(s).", self.available_disks.len());
        match selection_source {
            HeadlessSelectionSource::Requested => {
                eprintln!("Using requested disk: {}", selected_disk);
            }
            HeadlessSelectionSource::AutoSelected => {
                eprintln!(
                    "{}",
                    format_available_disks(&self.available_disks, Some(&selected_disk))
                );
                eprintln!("Auto-selected only available disk: {}", selected_disk);
            }
            HeadlessSelectionSource::Prompted => {
                eprintln!("Selected disk: {}", selected_disk);
            }
        }

        confirm_headless_install(
            &self.config.flake_host,
            &selected_disk,
            selection_source,
            &self.available_disks,
        )?;

        eprintln!(
            "Installing host '{}' headlessly to '{}'...",
            self.config.flake_host, selected_disk
        );
        self.phase = InstallPhase::DiskSelection;
        self.select_disk();
        if let InstallPhase::Failed(msg) = &self.phase {
            return Err(msg.clone());
        }

        // Phase 3: start install
        self.start_install();

        // Drain messages to stdout
        if let Some(ref mut rx) = self.rx {
            loop {
                match rx.recv().await {
                    Some(InstallMessage::Output(line)) => eprintln!("{}", line),
                    Some(InstallMessage::PhaseComplete(phase)) => {
                        eprintln!("=== Phase complete: {} ===", phase);
                    }
                    Some(InstallMessage::Finished(InstallResult::Success)) => {
                        eprintln!("Install completed successfully.");
                        return Ok(());
                    }
                    Some(InstallMessage::Finished(InstallResult::Failed(msg))) => {
                        return Err(format!("Install failed: {}", msg));
                    }
                    Some(InstallMessage::Finished(InstallResult::Cancelled)) => {
                        return Err("Install cancelled".to_string());
                    }
                    Some(InstallMessage::DisksDiscovered(_)) => {}
                    None => {
                        return Err("Install channel closed unexpectedly".to_string());
                    }
                }
            }
        }

        Err("No install channel available".to_string())
    }

    pub fn host_up(&mut self) {
        if !self.available_hosts.is_empty() {
            self.selected_host_index = if self.selected_host_index == 0 {
                self.available_hosts.len() - 1
            } else {
                self.selected_host_index - 1
            };
        }
    }

    pub fn host_down(&mut self) {
        if !self.available_hosts.is_empty() {
            self.selected_host_index = (self.selected_host_index + 1) % self.available_hosts.len();
        }
    }

    pub fn select_host(&mut self) {
        if self.phase != InstallPhase::HostSelection || self.available_hosts.is_empty() {
            return;
        }

        let selected = self.available_hosts[self.selected_host_index].clone();
        let repo_dir = match &self.config.source {
            InstallSource::EmbeddedRepo { repo_dir, .. } => repo_dir.clone(),
            InstallSource::PrebakedConfig => {
                self.phase = InstallPhase::Failed(
                    "Host selection is not available for legacy embedded install-config bundles."
                        .to_string(),
                );
                return;
            }
        };

        let writable_repo = PathBuf::from(WRITABLE_INSTALL_REPO_PATH);
        if let Err(error) = copy_repo_to_writable(&repo_dir, &writable_repo) {
            self.phase = InstallPhase::Failed(format!("Failed to prepare installer repo: {error}"));
            return;
        }
        if let Err(error) = vendor_embedded_keystone_input(&writable_repo) {
            self.phase =
                InstallPhase::Failed(format!("Failed to vendor embedded keystone input: {error}"));
            return;
        }

        let hardware_path = writable_repo.join(&selected.hardware_path);
        let disk_device = parse_hardware_disk_device(&hardware_path).filter(|path| {
            path.contains("/dev/disk/by-id/") && !is_placeholder_storage_device(path)
        });

        self.config.config_dir = writable_repo;
        self.config.flake_host = selected.flake_host;
        self.config.hostname = selected.hostname;
        self.config.storage_type = selected.storage_type;
        self.config.disk_device = disk_device;
        self.config.hardware_path = Some(hardware_path);
        self.phase = InstallPhase::Summary;
    }

    /// Move from Summary → DiskSelection.
    ///
    /// Disk selection is always explicit, even when a disk was pre-configured
    /// in the embedded config, so the operator must actively confirm target
    /// media before destructive disk operations.
    pub fn proceed_to_confirm(&mut self) {
        if self.phase != InstallPhase::Summary {
            return;
        }

        self.phase = InstallPhase::DiskSelection;
        self.discovering_disks = true;
        self.spawn_disk_discovery();
    }

    /// Spawn async disk discovery.
    fn spawn_disk_discovery(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);

        tokio::spawn(async move {
            match crate::disk::discover_disks().await {
                Ok(disks) => {
                    let _ = tx.send(InstallMessage::DisksDiscovered(disks));
                }
                Err(e) => {
                    let _ = tx.send(InstallMessage::Output(format!(
                        "Disk discovery failed: {}",
                        e
                    )));
                    let _ = tx.send(InstallMessage::DisksDiscovered(Vec::new()));
                }
            }
        });
    }

    /// Move disk selection cursor up.
    pub fn disk_up(&mut self) {
        if !self.available_disks.is_empty() {
            self.selected_disk_index = if self.selected_disk_index == 0 {
                self.available_disks.len() - 1
            } else {
                self.selected_disk_index - 1
            };
        }
    }

    /// Move disk selection cursor down.
    pub fn disk_down(&mut self) {
        if !self.available_disks.is_empty() {
            self.selected_disk_index = (self.selected_disk_index + 1) % self.available_disks.len();
        }
    }

    /// Select the highlighted disk and proceed to Confirm.
    pub fn select_disk(&mut self) {
        if self.phase != InstallPhase::DiskSelection || self.available_disks.is_empty() {
            return;
        }

        let selected = &self.available_disks[self.selected_disk_index];
        let device_path = selected.by_id_path.clone();

        // Inject the selected disk into the writable configuration.nix
        if let Err(e) = self.config.inject_selected_disk(&device_path) {
            self.phase = InstallPhase::Failed(format!("Failed to set disk device: {}", e));
            return;
        }

        self.config.disk_device = Some(device_path);
        self.rx = None; // Clean up discovery channel
        self.phase = InstallPhase::Confirm;
    }

    /// Move from Confirm → Installing, spawning the install subprocess.
    pub fn start_install(&mut self) {
        if self.phase != InstallPhase::Confirm {
            return;
        }

        self.phase = InstallPhase::Installing;
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let cancel_token = CancellationToken::new();
        self.cancel_token = cancel_token.clone();

        let config_dir = self.config.config_dir.clone();
        let install_config = self.config.clone();
        let flake_host = self.config.flake_host.clone();
        let username = self.config.username.clone();
        let repo_owner = self.config.installed_repo_owner().to_string();
        let repo_name = self.config.installed_repo_name().to_string();

        tokio::spawn(async move {
            // Phase 1: Run disko to partition and format the disk
            let _ = tx.send(InstallMessage::Output(
                "=== Phase 1/4: Partitioning with disko ===".to_string(),
            ));

            let disko_result = run_command(
                "disko",
                &[
                    "--mode",
                    "disko",
                    "--flake",
                    &format!("{}#{}", config_dir.display(), flake_host),
                ],
                &config_dir,
                &tx,
                &cancel_token,
                true,
            )
            .await;

            if let Err(e) = disko_result {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                    "disko failed: {}",
                    e
                ))));
                return;
            }

            if cancel_token.is_cancelled() {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Cancelled));
                return;
            }

            let _ = tx.send(InstallMessage::PhaseComplete(
                "Disk partitioning complete.".to_string(),
            ));

            let Some(ref user) = username else {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(
                    "Installer metadata is missing the admin username needed for the install commit and installed repo path.".to_string(),
                )));
                return;
            };

            // Phase 2: Capture hardware before nixos-install so the committed
            // repo already reflects the real target machine when the system is built.
            let _ = tx.send(InstallMessage::Output(String::new()));
            let _ = tx.send(InstallMessage::Output(
                "=== Phase 2/4: Detecting hardware ===".to_string(),
            ));
            if let Err(e) = detect_hardware_config(&install_config, &tx, &cancel_token).await {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                    "hardware detection failed: {}",
                    e
                ))));
                return;
            }

            if cancel_token.is_cancelled() {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Cancelled));
                return;
            }

            let _ = tx.send(InstallMessage::PhaseComplete(
                "Hardware config recorded.".to_string(),
            ));

            // Phase 3: Create the local install commit before nixos-install.
            let _ = tx.send(InstallMessage::Output(String::new()));
            let _ = tx.send(InstallMessage::Output(
                "=== Phase 3/4: Recording install commit ===".to_string(),
            ));
            if let Err(e) = create_install_commit(&config_dir, user, &tx).await {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                    "install commit failed: {}",
                    e
                ))));
                return;
            }

            if cancel_token.is_cancelled() {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Cancelled));
                return;
            }

            let _ = tx.send(InstallMessage::PhaseComplete(
                "Local install commit recorded.".to_string(),
            ));

            // Phase 4: Run nixos-install from the reconciled, committed repo.
            let _ = tx.send(InstallMessage::Output(String::new()));
            let _ = tx.send(InstallMessage::Output(
                "=== Phase 4/4: Installing NixOS ===".to_string(),
            ));

            let flake_ref = format!("{}#{}", config_dir.display(), flake_host);

            // The install-repo at config_dir was created and Phase-3-committed
            // as the installing user (typically uid 1001). nixos-install runs
            // under sudo as root, and Nix's libgit2 backend enforces
            // CVE-2022-24765's "dubious ownership" check — it refuses to open
            // a git repo not owned by the current user. Without this allowlist
            // entry, eval dies in seconds before any nix-daemon traffic, with
            // `error: opening Git repository ... is not owned by current user`.
            // Writing to root's --global (~root/.gitconfig) works on the live
            // installer; /etc/gitconfig is on the read-only squashfs.
            let safe_dir = config_dir.to_string_lossy().to_string();
            // Dedup: `--add` would otherwise accumulate identical
            // safe.directory entries on repeated install attempts in
            // the same live-installer boot.
            let already_set = match tokio::process::Command::new("sudo")
                .args([
                    "-n",
                    "git",
                    "config",
                    "--global",
                    "--get-all",
                    "safe.directory",
                ])
                .output()
                .await
            {
                Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .any(|l| l == safe_dir),
                _ => false,
            };
            if !already_set {
                if let Err(e) = run_command_quiet(
                    "git",
                    &["config", "--global", "--add", "safe.directory", &safe_dir],
                    Some(&config_dir),
                    true,
                )
                .await
                {
                    let _ = tx.send(InstallMessage::Output(format!(
                        "warning: failed to set git safe.directory for root: {} (nixos-install may fail on flake eval)",
                        e
                    )));
                }
            }

            let install_result = run_command(
                "nixos-install",
                &["--flake", &flake_ref, "--no-root-password"],
                &config_dir,
                &tx,
                &cancel_token,
                true,
            )
            .await;

            match install_result {
                Ok(()) => {
                    if let Err(e) = normalize_installed_repo_state(&config_dir) {
                        let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                            "post-install repo normalization failed: {}",
                            e
                        ))));
                        return;
                    }
                    if let Err(e) = amend_install_commit(&config_dir, &tx).await {
                        let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                            "post-install repo amend failed: {}",
                            e
                        ))));
                        return;
                    }

                    // Generate Secure Boot keys in the installed system (non-fatal)
                    let _ = tx.send(InstallMessage::Output(
                        "Generating Secure Boot keys in target...".to_string(),
                    ));
                    let sb_result = run_command(
                        "nixos-enter",
                        &["--root", "/mnt", "--", "sbctl", "create-keys"],
                        &config_dir,
                        &tx,
                        &cancel_token,
                        true,
                    )
                    .await;
                    match sb_result {
                        Ok(()) => {
                            let _ = tx.send(InstallMessage::Output(
                                "Secure Boot keys generated.".to_string(),
                            ));
                        }
                        Err(e) => {
                            let _ = tx.send(InstallMessage::Output(format!(
                                "SB key generation skipped: {} (will retry on first boot)",
                                e
                            )));
                        }
                    }

                    let _ = tx.send(InstallMessage::Output(
                        "Copying config to installed system...".to_string(),
                    ));
                    if let Err(e) =
                        copy_config_to_target(&config_dir, user, &repo_owner, &repo_name, &tx).await
                    {
                        let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                            "post-install config copy failed: {}",
                            e
                        ))));
                        return;
                    }

                    let (_, mounted_repo) = installed_repo_paths(user, &repo_owner, &repo_name);
                    if let Err(e) =
                        validate_installed_hardware(&mounted_repo, &flake_host, &tx).await
                    {
                        let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                            "hardware validation failed: {}",
                            e
                        ))));
                        return;
                    }

                    let _ = tx.send(InstallMessage::Finished(InstallResult::Success));
                }
                Err(e) => {
                    let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                        "nixos-install failed: {}",
                        e
                    ))));
                }
            }
        });
    }

    /// Go back from Confirm → DiskSelection, or DiskSelection → Summary.
    pub fn go_back(&mut self) {
        match self.phase {
            InstallPhase::Confirm => {
                self.phase = InstallPhase::DiskSelection;
            }
            InstallPhase::DiskSelection => {
                self.phase = InstallPhase::Summary;
            }
            InstallPhase::Summary => {
                if matches!(&self.config.source, InstallSource::EmbeddedRepo { .. }) {
                    self.phase = InstallPhase::HostSelection;
                }
            }
            _ => {}
        }
    }

    /// Cancel a running install.
    pub fn cancel(&mut self) {
        if self.phase == InstallPhase::Installing {
            self.cancel_token.cancel();
        }
    }

    pub fn is_finished(&self) -> bool {
        matches!(self.phase, InstallPhase::Done | InstallPhase::Failed(_))
    }

    pub fn scroll_up(&mut self) {
        self.auto_scroll = false;
        self.scroll_offset = self.scroll_offset.saturating_add(1);
    }

    pub fn scroll_down(&mut self) {
        if self.scroll_offset > 0 {
            self.scroll_offset = self.scroll_offset.saturating_sub(1);
            if self.scroll_offset == 0 {
                self.auto_scroll = true;
            }
        }
    }

    /// Poll for subprocess messages.
    pub fn poll(&mut self) {
        let rx = match self.rx.as_mut() {
            Some(rx) => rx,
            None => return,
        };

        while let Ok(msg) = rx.try_recv() {
            match msg {
                InstallMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                InstallMessage::PhaseComplete(msg) => {
                    self.output_lines.push(msg);
                }
                InstallMessage::DisksDiscovered(disks) => {
                    self.available_disks = disks;
                    if !self.available_disks.is_empty() {
                        self.selected_disk_index = preferred_disk_index(
                            &self.available_disks,
                            self.config.disk_device.as_deref(),
                        );
                    }
                    self.discovering_disks = false;
                }
                InstallMessage::Finished(result) => match result {
                    InstallResult::Success => {
                        self.output_lines
                            .push(String::from("\nInstallation complete!"));
                        self.phase = InstallPhase::Done;
                    }
                    InstallResult::Failed(err) => {
                        self.output_lines
                            .push(format!("\nInstallation failed: {}", err));
                        self.phase = InstallPhase::Failed(err);
                    }
                    InstallResult::Cancelled => {
                        self.output_lines
                            .push(String::from("\nInstallation cancelled."));
                        self.phase = InstallPhase::Failed("Cancelled by user".to_string());
                    }
                },
            }
        }
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match &self.phase {
            InstallPhase::HostSelection => self.render_host_selection(frame, area),
            InstallPhase::Summary => self.render_summary(frame, area),
            InstallPhase::DiskSelection => self.render_disk_selection(frame, area),
            InstallPhase::Confirm => self.render_confirm(frame, area),
            InstallPhase::Installing => self.render_installing(frame, area),
            InstallPhase::Done => self.render_done(frame, area),
            InstallPhase::Failed(err) => self.render_failed(frame, area, err),
        }
    }

    fn render_host_selection(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(8),    // Host list
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Select Installation Host",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let items: Vec<ListItem> = self
            .available_hosts
            .iter()
            .enumerate()
            .map(|(index, host)| {
                let indicator = if index == self.selected_host_index {
                    "▸ "
                } else {
                    "  "
                };
                let style = if index == self.selected_host_index {
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                };
                let metadata = match (&host.system, &host.storage_type) {
                    (Some(system), Some(storage_type)) => format!("{system}  [{storage_type}]"),
                    (Some(system), None) => system.clone(),
                    (None, Some(storage_type)) => format!("[{storage_type}]"),
                    (None, None) => String::new(),
                };
                let details = format!("hostname={}  {}", host.hostname, metadata)
                    .trim_end()
                    .to_string();

                ListItem::new(Line::from(vec![
                    Span::styled(indicator, style),
                    Span::styled(&host.flake_host, style),
                    Span::styled(
                        format!("  {}", details),
                        Style::default().fg(Color::DarkGray),
                    ),
                ]))
            })
            .collect();

        let host_list = List::new(items).block(
            Block::default()
                .title(" Embedded installer targets ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(host_list, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: navigate • Enter: select host • q: quit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_summary(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(8),    // Config summary
                Constraint::Length(3), // Help
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled("Keystone Installer", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Config summary
        let disk = self
            .config
            .disk_device
            .as_deref()
            .unwrap_or("(not detected)");
        let storage = self
            .config
            .storage_type
            .as_deref()
            .unwrap_or("(not detected)");
        let source_label = match &self.config.source {
            InstallSource::EmbeddedRepo { .. } => "  Repo:      ",
            InstallSource::PrebakedConfig => "  Config:    ",
        };

        let items = vec![
            ListItem::new(Line::from(vec![
                Span::styled("  Host:      ", t.inactive_style()),
                Span::styled(
                    &self.config.flake_host,
                    Style::default().add_modifier(Modifier::BOLD),
                ),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Hostname:  ", t.inactive_style()),
                Span::styled(
                    &self.config.hostname,
                    Style::default().add_modifier(Modifier::BOLD),
                ),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Storage:   ", t.inactive_style()),
                Span::styled(storage, Style::default().add_modifier(Modifier::BOLD)),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Disk:      ", t.inactive_style()),
                Span::styled(disk, Style::default().add_modifier(Modifier::BOLD)),
            ])),
            ListItem::new(Line::from("")),
            ListItem::new(Line::from(vec![
                Span::styled(source_label, t.inactive_style()),
                Span::styled(
                    self.config.config_dir.display().to_string(),
                    t.inactive_style(),
                ),
            ])),
        ];

        let summary = List::new(items).block(
            Block::default()
                .title(" Configuration Summary ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(summary, chunks[1]);

        // Help
        let help = Paragraph::new(Text::styled(
            "Enter: proceed to install • Esc: back • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_disk_selection(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Disk list
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Select Installation Disk", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        if self.discovering_disks {
            let loading =
                Paragraph::new(Text::styled("\n  Discovering disks...", t.inactive_style())).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .border_style(Style::default().fg(t.accent)),
                );
            frame.render_widget(loading, chunks[1]);
        } else if self.available_disks.is_empty() {
            let no_disks = Paragraph::new(Text::styled(
                "\n  No disks found. Ensure drives are connected and detected by the kernel.",
                t.error_style(),
            ))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.error)),
            );
            frame.render_widget(no_disks, chunks[1]);
        } else {
            let items: Vec<ListItem> = self
                .available_disks
                .iter()
                .enumerate()
                .map(|(i, disk)| {
                    let indicator = if i == self.selected_disk_index {
                        "▸ "
                    } else {
                        "  "
                    };
                    let style = if i == self.selected_disk_index {
                        Style::default().fg(t.accent).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    ListItem::new(Line::from(vec![
                        Span::styled(indicator, style),
                        Span::styled(&disk.model, style),
                        Span::styled(
                            format!("  {}  [{}]", disk.size, disk.transport),
                            t.inactive_style(),
                        ),
                    ]))
                })
                .collect();

            let disk_list = List::new(items).block(
                Block::default()
                    .title(" Available Disks ")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.accent)),
            );
            frame.render_widget(disk_list, chunks[1]);
        }

        let help = Paragraph::new(Text::styled(
            "↑/���: navigate • Enter: select disk • Esc: back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_confirm(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Warning
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Confirm Installation", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let disk = self
            .config
            .disk_device
            .as_deref()
            .unwrap_or("(unknown disk)");
        let warning_text = format!(
            "\n  WARNING: This will ERASE ALL DATA on:\n\n    {}\n\n  This action cannot be undone.",
            disk,
        );
        let warning = Paragraph::new(Text::styled(
            warning_text,
            t.error_style().add_modifier(Modifier::BOLD),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.error)),
        );
        frame.render_widget(warning, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: confirm and install • Esc: go back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_installing(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Output
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            format!("Installing: {} (in progress...)", self.config.hostname),
            t.title_style(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Output area with scrolling
        let output_height = chunks[1].height.saturating_sub(2) as usize;
        let total_lines = self.output_lines.len();

        let scroll = if self.auto_scroll {
            total_lines.saturating_sub(output_height) as u16
        } else {
            let max_scroll = total_lines.saturating_sub(output_height) as u16;
            max_scroll.saturating_sub(self.scroll_offset)
        };

        let output_lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|line| Line::from(line.as_str()))
            .collect();

        let output = Paragraph::new(output_lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(t.inactive_style()),
            )
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0));
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: scroll • Esc: cancel",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Message
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Installation Complete", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let message = Paragraph::new(Text::styled(
            format!(
                "\n  NixOS has been installed as '{}'.\n\n  \
                 Please remove the USB drive and reboot.\n\n  \
                 After reboot, enroll Secure Boot keys with:\n    \
                 sudo sbctl enroll-keys --microsoft",
                self.config.hostname,
            ),
            Style::default().fg(t.active),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: reboot • q: quit to shell",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, error: &str) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Output + error
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Installation Failed",
            t.error_style().add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Show the last N lines of output plus the error
        let output_height = chunks[1].height.saturating_sub(2) as usize;
        let total_lines = self.output_lines.len();

        let scroll = if self.auto_scroll {
            total_lines.saturating_sub(output_height) as u16
        } else {
            let max_scroll = total_lines.saturating_sub(output_height) as u16;
            max_scroll.saturating_sub(self.scroll_offset)
        };

        let output_lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|line| Line::from(line.as_str()))
            .collect();

        let output = Paragraph::new(output_lines)
            .block(
                Block::default()
                    .title(format!(" Error: {} ", error))
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.error)),
            )
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0));
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: scroll • q: quit to shell",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

/// Recursively copy a directory tree using async I/O.
async fn copy_dir_recursive_async(src: &Path, dst: &Path) -> Result<(), String> {
    let mut entries = tokio::fs::read_dir(src)
        .await
        .map_err(|e| format!("Failed to read dir {}: {}", src.display(), e))?;

    while let Some(entry) = entries
        .next_entry()
        .await
        .map_err(|e| format!("Failed to read entry: {}", e))?
    {
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        let file_type = entry
            .file_type()
            .await
            .map_err(|e| format!("Failed to inspect {}: {}", src_path.display(), e))?;

        if file_type.is_symlink() {
            let link_target = tokio::fs::read_link(&src_path)
                .await
                .map_err(|e| format!("Failed to read symlink {}: {}", src_path.display(), e))?;
            std::os::unix::fs::symlink(&link_target, &dst_path).map_err(|e| {
                format!(
                    "Failed to recreate symlink {} -> {}: {}",
                    dst_path.display(),
                    link_target.display(),
                    e
                )
            })?;
        } else if file_type.is_dir() {
            tokio::fs::create_dir_all(&dst_path)
                .await
                .map_err(|e| format!("Failed to create dir {}: {}", dst_path.display(), e))?;
            Box::pin(copy_dir_recursive_async(&src_path, &dst_path)).await?;
        } else {
            // Skip non-nix files that are not the marker files (hostname, username, etc.)
            tokio::fs::copy(&src_path, &dst_path).await.map_err(|e| {
                format!(
                    "Failed to copy {} -> {}: {}",
                    src_path.display(),
                    dst_path.display(),
                    e
                )
            })?;
        }
    }

    Ok(())
}

async fn run_command_quiet(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
    privileged: bool,
) -> Result<(), String> {
    let command = build_command_spec(program, args, privileged);
    let command_display = format!("{} {}", command.program, command.args.join(" "));

    let mut child = Command::new(&command.program);
    child.args(&command.args);
    if let Some(cwd) = cwd {
        child.current_dir(cwd);
    }

    let output = child
        .output()
        .await
        .map_err(|e| format!("Failed to run `{}`: {}", command_display, e))?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let details = if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        "no output".to_string()
    };

    Err(format!(
        "`{}` exited with {}: {}",
        command_display,
        output
            .status
            .code()
            .map(|code| code.to_string())
            .unwrap_or_else(|| "signal".to_string()),
        details
    ))
}

async fn git_config_get(repo_dir: &Path, key: &str) -> Result<Option<String>, String> {
    let output = Command::new("git")
        .args(["config", "--get", key])
        .current_dir(repo_dir)
        .output()
        .await
        .map_err(|e| format!("Failed to read git config {key}: {e}"))?;

    if !output.status.success() {
        return Ok(None);
    }

    let value = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if value.is_empty() {
        Ok(None)
    } else {
        Ok(Some(value))
    }
}

async fn ensure_git_identity(repo_dir: &Path, username: &str) -> Result<(), String> {
    if git_config_get(repo_dir, "user.name").await?.is_none() {
        run_command_quiet(
            "git",
            &["config", "user.name", username],
            Some(repo_dir),
            false,
        )
        .await
        .map_err(|e| format!("Failed to configure git user.name: {e}"))?;
    }

    if git_config_get(repo_dir, "user.email").await?.is_none() {
        let email = format!("{username}@keystone.local");
        run_command_quiet(
            "git",
            &["config", "user.email", &email],
            Some(repo_dir),
            false,
        )
        .await
        .map_err(|e| format!("Failed to configure git user.email: {e}"))?;
    }

    Ok(())
}

async fn ensure_repo_on_main(repo_dir: &Path) -> Result<(), String> {
    let git_dir = repo_dir.join(".git");
    if !git_dir.exists() {
        return run_command_quiet("git", &["init", "-b", "main"], Some(repo_dir), false)
            .await
            .map_err(|e| format!("Failed to initialize git repo: {e}"));
    }

    let output = Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .current_dir(repo_dir)
        .output()
        .await
        .map_err(|e| format!("Failed to inspect current git branch: {e}"))?;

    if !output.status.success() {
        return Err(format!(
            "Failed to inspect current git branch: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let branch = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if branch == "main" {
        return Ok(());
    }

    if branch == "HEAD" {
        run_command_quiet("git", &["checkout", "-B", "main"], Some(repo_dir), false)
            .await
            .map_err(|e| format!("Failed to create main branch: {e}"))?;
    } else {
        run_command_quiet("git", &["branch", "-M", "main"], Some(repo_dir), false)
            .await
            .map_err(|e| format!("Failed to rename branch to main: {e}"))?;
    }

    Ok(())
}

async fn detect_hardware_config(
    config: &InstallerConfig,
    tx: &mpsc::UnboundedSender<InstallMessage>,
    cancel_token: &CancellationToken,
) -> Result<(), String> {
    let hardware_path = resolve_hardware_path(config)?;
    let generated_hardware_path = hardware_path
        .parent()
        .ok_or_else(|| {
            format!(
                "hardware.nix has no parent dir: {}",
                hardware_path.display()
            )
        })?
        .join(GENERATED_HARDWARE_FILENAME);
    let capture_path = PathBuf::from(format!(
        "/tmp/keystone-detected-hardware-{}.nix",
        std::process::id()
    ));
    let capture_script = format!(
        "nixos-generate-config --root /mnt --show-hardware-config > {}",
        capture_path.display()
    );

    let current_hardware_nix = tokio::fs::read_to_string(&hardware_path)
        .await
        .map_err(|e| format!("Failed to read {}: {}", hardware_path.display(), e))?;

    let _ = tx.send(InstallMessage::Output(format!(
        "Capturing detected hardware config for {}",
        config.hostname
    )));
    run_command(
        "sh",
        &["-c", &capture_script],
        &config.config_dir,
        tx,
        cancel_token,
        true,
    )
    .await?;

    let generated_hardware = tokio::fs::read_to_string(&capture_path)
        .await
        .map_err(|e| format!("Failed to read captured hardware config: {}", e))?;
    let _ = tokio::fs::remove_file(&capture_path).await;
    let sanitized_generated_hardware = strip_generated_storage_assignments(&generated_hardware);

    let stable_disk_ids = extract_stable_disk_identifiers(&generated_hardware);
    if stable_disk_ids.is_empty() {
        return Err(
            "No confident stable disk mapping was detected in the generated hardware config. The installer will not guess."
                .to_string(),
        );
    }

    let _ = tx.send(InstallMessage::Output(format!(
        "Detected stable disk identifiers: {}",
        stable_disk_ids.join(", ")
    )));

    let reconciled_hardware =
        build_reconciled_hardware_wrapper(&current_hardware_nix, config.disk_device.as_deref())?;

    tokio::fs::write(
        &generated_hardware_path,
        format!("{}\n", sanitized_generated_hardware),
    )
    .await
    .map_err(|e| {
        format!(
            "Failed to write generated hardware module {}: {}",
            generated_hardware_path.display(),
            e
        )
    })?;
    tokio::fs::write(&hardware_path, reconciled_hardware)
        .await
        .map_err(|e| format!("Failed to update {}: {}", hardware_path.display(), e))?;

    let _ = tx.send(InstallMessage::Output(format!(
        "Updated {} to import {}",
        hardware_path.display(),
        generated_hardware_path.display()
    )));

    Ok(())
}

async fn create_install_commit(
    config_dir: &Path,
    username: &str,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let _ = tx.send(InstallMessage::Output(
        "Preparing local install commit...".to_string(),
    ));

    ensure_repo_on_main(config_dir).await?;
    ensure_git_identity(config_dir, username).await?;

    let gitignore_path = config_dir.join(".gitignore");
    let current_gitignore = tokio::fs::read_to_string(&gitignore_path).await.ok();
    let gitignore_contents = ensure_marker_gitignore_contents(current_gitignore.as_deref());
    tokio::fs::write(&gitignore_path, gitignore_contents)
        .await
        .map_err(|e| format!("Failed to update {}: {}", gitignore_path.display(), e))?;

    let _ = Command::new("git")
        .args([
            "rm",
            "--cached",
            "-f",
            "--ignore-unmatch",
            FIRST_BOOT_MARKER,
        ])
        .current_dir(config_dir)
        .output()
        .await;

    run_command_quiet("git", &["add", "."], Some(config_dir), false)
        .await
        .map_err(|e| format!("Failed to stage install repo changes: {e}"))?;
    run_command_quiet(
        "git",
        &[
            "commit",
            "--allow-empty",
            "--no-gpg-sign",
            "-m",
            INITIAL_INSTALL_COMMIT_MESSAGE,
        ],
        Some(config_dir),
        false,
    )
    .await
    .map_err(|e| format!("Failed to create install commit: {e}"))?;

    let _ = tx.send(InstallMessage::Output(
        "Recorded local install commit.".to_string(),
    ));

    Ok(())
}

async fn amend_install_commit(
    config_dir: &Path,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let _ = tx.send(InstallMessage::Output(
        "Normalizing install repo state before handoff...".to_string(),
    ));

    let _ = Command::new("git")
        .args([
            "rm",
            "--cached",
            "-f",
            "--ignore-unmatch",
            FIRST_BOOT_MARKER,
        ])
        .current_dir(config_dir)
        .output()
        .await;

    run_command_quiet("git", &["add", "-A", "."], Some(config_dir), false)
        .await
        .map_err(|e| format!("Failed to stage normalized install repo: {e}"))?;
    run_command_quiet(
        "git",
        &["commit", "--amend", "--no-edit", "--no-gpg-sign"],
        Some(config_dir),
        false,
    )
    .await
    .map_err(|e| format!("Failed to amend install commit: {e}"))?;

    Ok(())
}

/// Copy the prepared config to the installed system for the post-install onboarding flow.
///
/// Creates the installed system flake directory on the target and copies
/// the config tree with a `.first-boot-pending` marker so the TUI knows
/// to continue onboarding on next login.
fn installed_repo_paths(username: &str, repo_owner: &str, repo_name: &str) -> (PathBuf, PathBuf) {
    let system_repo_dir = PathBuf::from("/home")
        .join(username)
        .join("repos")
        .join(repo_owner)
        .join(repo_name);
    let mounted_repo_dir = PathBuf::from("/mnt").join(
        system_repo_dir
            .strip_prefix("/")
            .expect("installed repo path should be absolute"),
    );

    (system_repo_dir, mounted_repo_dir)
}

/// Stage the config repo into a temporary directory with first-boot marker.
async fn stage_config_to_temp(
    config_dir: &Path,
    staging_root: &Path,
    staged_repo_dir: &Path,
) -> Result<(), String> {
    let _ = tokio::fs::remove_dir_all(staging_root).await;
    tokio::fs::create_dir_all(staged_repo_dir)
        .await
        .map_err(|e| format!("Failed to create staging dir: {}", e))?;

    copy_dir_recursive_async(config_dir, staged_repo_dir)
        .await
        .map_err(|e| format!("Failed to stage config files: {}", e))?;

    tokio::fs::write(staged_repo_dir.join(FIRST_BOOT_MARKER), "")
        .await
        .map_err(|e| format!("Failed to write first-boot marker: {}", e))?;

    let staged_marker_string = staged_repo_dir
        .join(FIRST_BOOT_MARKER)
        .display()
        .to_string();
    run_command_quiet("test", &["-f", &staged_marker_string], None, false)
        .await
        .map_err(|e| format!("Failed to verify staged first-boot marker: {}", e))?;
    Ok(())
}

/// Install development SSH keys into the target system's authorized_keys.
async fn install_ssh_keys(
    installed_ssh_keys: &[String],
    target_ssh_dir: &Path,
    target_authorized_keys: &Path,
    staging_root: &Path,
) -> Result<(), String> {
    let target_ssh_dir_string = target_ssh_dir.display().to_string();
    let target_authorized_keys_string = target_authorized_keys.display().to_string();
    run_command_quiet(
        "install",
        &["-d", "-m", "0700", &target_ssh_dir_string],
        None,
        true,
    )
    .await
    .map_err(|e| format!("Failed to create installed SSH directory: {}", e))?;

    let existing_authorized_keys = tokio::fs::read_to_string(target_authorized_keys).await.ok();
    let merged_authorized_keys =
        merge_authorized_keys(existing_authorized_keys.as_deref(), installed_ssh_keys);
    let staged_authorized_keys = staging_root.join("authorized_keys");
    let staged_authorized_keys_string = staged_authorized_keys.display().to_string();
    tokio::fs::write(&staged_authorized_keys, merged_authorized_keys)
        .await
        .map_err(|e| format!("Failed to stage installed SSH keys: {}", e))?;
    run_command_quiet(
        "install",
        &[
            "-m",
            "0600",
            &staged_authorized_keys_string,
            &target_authorized_keys_string,
        ],
        None,
        true,
    )
    .await
    .map_err(|e| format!("Failed to install development SSH keys: {}", e))?;
    Ok(())
}

/// Fix ownership of .keystone and optionally .ssh directories on the installed target.
async fn fix_target_ownership(
    target_home: &Path,
    username: &str,
    has_ssh_keys: bool,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let passwd_path = PathBuf::from("/mnt/etc/passwd");
    if !passwd_path.exists() {
        return Ok(());
    }
    let passwd = tokio::fs::read_to_string(&passwd_path)
        .await
        .unwrap_or_default();
    let line = match passwd
        .lines()
        .find(|l| l.starts_with(&format!("{}:", username)))
    {
        Some(l) => l.to_string(),
        None => return Ok(()),
    };
    let parts: Vec<&str> = line.split(':').collect();
    if parts.len() < 4 {
        return Ok(());
    }
    let uid = parts[2];
    let gid = parts[3];
    let keystone_dir = target_home.join(".keystone");
    let ownership = format!("{}:{}", uid, gid);
    let keystone_dir_string = keystone_dir.display().to_string();
    let _ = tx.send(InstallMessage::Output(format!(
        "Fixing installed repo ownership at {}",
        keystone_dir.display()
    )));
    run_command_quiet(
        "chown",
        &["-R", &ownership, &keystone_dir_string],
        None,
        true,
    )
    .await
    .map_err(|e| format!("Failed to set installed repo ownership: {}", e))?;
    if has_ssh_keys {
        let ssh_dir = target_home.join(".ssh");
        let ssh_dir_string = ssh_dir.display().to_string();
        run_command_quiet("chown", &["-R", &ownership, &ssh_dir_string], None, true)
            .await
            .map_err(|e| format!("Failed to set installed SSH key ownership: {}", e))?;
    }
    Ok(())
}

async fn copy_config_to_target(
    config_dir: &Path,
    username: &str,
    repo_owner: &str,
    repo_name: &str,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let (_, mounted_repo_dir) = installed_repo_paths(username, repo_owner, repo_name);
    let target_home = PathBuf::from("/mnt").join(
        Path::new("/home")
            .join(username)
            .strip_prefix("/")
            .expect("target home should be absolute"),
    );
    let repo_parent = mounted_repo_dir.parent().ok_or_else(|| {
        format!(
            "Installed repo path has no parent: {}",
            mounted_repo_dir.display()
        )
    })?;
    let staging_root = PathBuf::from(format!(
        "/tmp/keystone-installed-config-{}",
        std::process::id()
    ));
    let staged_repo_dir = staging_root.join(repo_name);
    let repo_parent_string = repo_parent.display().to_string();
    let repo_dir_string = mounted_repo_dir.display().to_string();
    let staged_repo_contents = format!("{}/.", staged_repo_dir.display());
    let target_marker = mounted_repo_dir.join(FIRST_BOOT_MARKER);
    let target_marker_string = target_marker.display().to_string();
    let installed_ssh_keys = read_install_metadata_lines("installed-ssh-keys");
    let target_ssh_dir = target_home.join(".ssh");
    let target_authorized_keys = target_ssh_dir.join("authorized_keys");

    let _ = tx.send(InstallMessage::Output(format!(
        "Preparing installed repo handoff to {}",
        mounted_repo_dir.display()
    )));

    // Stage the repo in /tmp first, then copy it into /mnt through sudo so the
    // installer's success state means the first-boot handoff is actually usable.
    stage_config_to_temp(config_dir, &staging_root, &staged_repo_dir).await?;

    let _ = tx.send(InstallMessage::Output(format!(
        "Copying installed repo to {}",
        mounted_repo_dir.display()
    )));
    run_command_quiet("install", &["-d", &repo_parent_string], None, true)
        .await
        .map_err(|e| format!("Failed to create installed repo parent: {}", e))?;
    run_command_quiet("rm", &["-rf", &repo_dir_string], None, true)
        .await
        .map_err(|e| format!("Failed to clear installed repo dir: {}", e))?;
    run_command_quiet("install", &["-d", &repo_dir_string], None, true)
        .await
        .map_err(|e| format!("Failed to create installed repo dir: {}", e))?;
    run_command_quiet(
        "cp",
        &["-a", &staged_repo_contents, &repo_dir_string],
        None,
        true,
    )
    .await
    .map_err(|e| format!("Failed to copy staged repo into target system: {}", e))?;
    run_command_quiet("test", &["-f", &target_marker_string], None, true)
        .await
        .map_err(|e| format!("Installed repo is missing the first-boot marker: {}", e))?;

    if !installed_ssh_keys.is_empty() {
        let _ = tx.send(InstallMessage::Output(format!(
            "Installing development SSH keys for {}",
            username
        )));
        install_ssh_keys(
            &installed_ssh_keys,
            &target_ssh_dir,
            &target_authorized_keys,
            &staging_root,
        )
        .await?;
    }

    fix_target_ownership(&target_home, username, !installed_ssh_keys.is_empty(), tx).await?;

    let _ = tokio::fs::remove_dir_all(&staging_root).await;

    let _ = tx.send(InstallMessage::Output(format!(
        "Config copied to {}",
        mounted_repo_dir.display()
    )));
    Ok(())
}

/// Validate that the installed canonical repo contains reconciled hardware files.
///
/// After the installer copies the config repo to the target system, this function
/// verifies that the hardware reconciliation from install time is actually present.
/// Without this, a rebuild from the canonical repo can produce an unbootable system
/// (e.g., missing initrd modules like `vmd` on Dell hardware).
///
/// `flake_host` is the selected host key from the installer config — used to locate
/// the host directory under `hosts/`. This avoids depending on a `hostname` file
/// which may not exist in all repo layouts.
/// Try a direct `tokio::fs::metadata`; if that fails (PermissionDenied
/// vs NotFound is indistinguishable across mount perms), fall back to
/// `sudo test -f` so we don't conflate "not readable from this uid"
/// with "absent". The live installer's admin runs at a different uid
/// than the installed system's admin (e.g., live=1001, installed=1000)
/// and `/mnt/home/<user>` is mode 700 — direct stat as the live
/// installer's uid returns Err on a path that's correctly placed.
async fn path_exists_for_validation(p: &Path) -> bool {
    if tokio::fs::metadata(p).await.is_ok() {
        return true;
    }
    run_command_quiet("test", &["-f", &p.display().to_string()], None, true)
        .await
        .is_ok()
}

async fn read_to_string_for_validation(p: &Path) -> Result<String, String> {
    if let Ok(s) = tokio::fs::read_to_string(p).await {
        return Ok(s);
    }
    let output = tokio::process::Command::new("sudo")
        .args(["-n", "cat", &p.display().to_string()])
        .output()
        .await
        .map_err(|e| format!("Cannot read {}: {}", p.display(), e))?;
    if !output.status.success() {
        return Err(format!(
            "Cannot read {}: sudo cat exited with {}: {}",
            p.display(),
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

async fn validate_installed_hardware(
    mounted_repo_dir: &Path,
    flake_host: &str,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let _ = tx.send(InstallMessage::Output(
        "Validating reconciled hardware in installed repo...".to_string(),
    ));

    let host_dir = mounted_repo_dir.join("hosts").join(flake_host);
    let generated_hw = host_dir.join(GENERATED_HARDWARE_FILENAME);
    let flat_generated_hw = mounted_repo_dir.join(GENERATED_HARDWARE_FILENAME);

    if !path_exists_for_validation(&generated_hw).await
        && !path_exists_for_validation(&flat_generated_hw).await
    {
        return Err(format!(
            "Installed repo is missing {}: a rebuild from this repo may produce \
             an unbootable system with missing initrd modules. \
             Expected at {} or {}",
            GENERATED_HARDWARE_FILENAME,
            generated_hw.display(),
            flat_generated_hw.display(),
        ));
    }

    // Verify hardware.nix exists and imports hardware-generated.nix
    let hardware_nix = host_dir.join("hardware.nix");
    let flat_hardware_nix = mounted_repo_dir.join("hardware.nix");

    let hardware_nix_path = if path_exists_for_validation(&hardware_nix).await {
        hardware_nix
    } else if path_exists_for_validation(&flat_hardware_nix).await {
        flat_hardware_nix
    } else {
        return Err(format!(
            "Installed repo is missing hardware.nix: cannot verify import of {}. \
             Expected at {} or {}",
            GENERATED_HARDWARE_FILENAME,
            host_dir.join("hardware.nix").display(),
            mounted_repo_dir.join("hardware.nix").display(),
        ));
    };

    let hw_content = read_to_string_for_validation(&hardware_nix_path).await?;

    if !hw_content.contains(GENERATED_HARDWARE_FILENAME) {
        return Err(format!(
            "{} does not import {}: a rebuild may miss \
             machine-specific initrd modules and storage configuration",
            hardware_nix_path.display(),
            GENERATED_HARDWARE_FILENAME,
        ));
    }

    let _ = tx.send(InstallMessage::Output(
        "Reconciled hardware validation passed".to_string(),
    ));
    Ok(())
}

/// Run a command, streaming output lines to the channel.
async fn run_command(
    program: &str,
    args: &[&str],
    cwd: &Path,
    tx: &mpsc::UnboundedSender<InstallMessage>,
    cancel_token: &CancellationToken,
    privileged: bool,
) -> Result<(), String> {
    let command = build_command_spec(program, args, privileged);
    let cmd_display = format!("$ {} {}", command.program, command.args.join(" "));
    let _ = tx.send(InstallMessage::Output(cmd_display));

    let child_result = Command::new(&command.program)
        .args(&command.args)
        .current_dir(cwd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn();

    let mut child = match child_result {
        Ok(c) => c,
        Err(e) => return Err(format!("Failed to start {}: {}", program, e)),
    };

    let stderr = child.stderr.take();
    let stdout = child.stdout.take();

    let tx_stderr = tx.clone();
    let stderr_task = tokio::spawn(async move {
        if let Some(stderr) = stderr {
            let reader = BufReader::new(stderr);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if tx_stderr.send(InstallMessage::Output(line)).is_err() {
                    break;
                }
            }
        }
    });

    let tx_stdout = tx.clone();
    let stdout_task = tokio::spawn(async move {
        if let Some(stdout) = stdout {
            let reader = BufReader::new(stdout);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if tx_stdout.send(InstallMessage::Output(line)).is_err() {
                    break;
                }
            }
        }
    });

    tokio::select! {
        status = child.wait() => {
            let _ = stderr_task.await;
            let _ = stdout_task.await;

            match status {
                Ok(s) if s.success() => Ok(()),
                Ok(s) => Err(format!("{} exited with code {}", program, s.code().unwrap_or(-1))),
                Err(e) => Err(format!("{} process error: {}", program, e)),
            }
        }
        _ = cancel_token.cancelled() => {
            drop(child);
            let _ = stderr_task.await;
            let _ = stdout_task.await;
            Err("Cancelled".to_string())
        }
    }
}

fn build_command_spec(program: &str, args: &[&str], privileged: bool) -> CommandSpec {
    if privileged {
        let mut command_args = Vec::with_capacity(args.len() + 2);
        command_args.push("-n".to_string());
        command_args.push(program.to_string());
        command_args.extend(args.iter().map(|arg| (*arg).to_string()));
        return CommandSpec {
            program: "sudo".to_string(),
            args: command_args,
        };
    }

    CommandSpec {
        program: program.to_string(),
        args: args.iter().map(|arg| (*arg).to_string()).collect(),
    }
}

impl Component for InstallScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(self.handle_key_event(key.code));
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

impl InstallScreen {
    /// Handle a key press, returning an optional global Action.
    fn handle_key_event(&mut self, code: KeyCode) -> Option<Action> {
        match self.phase() {
            InstallPhase::HostSelection => match code {
                KeyCode::Up | KeyCode::Char('k') => {
                    self.host_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.host_down();
                    None
                }
                KeyCode::Enter => {
                    self.select_host();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Summary => match code {
                KeyCode::Enter => {
                    self.proceed_to_confirm();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::DiskSelection => match code {
                KeyCode::Up | KeyCode::Char('k') => {
                    self.disk_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.disk_down();
                    None
                }
                KeyCode::Enter => {
                    self.select_disk();
                    None
                }
                KeyCode::Esc => {
                    self.go_back();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Confirm => match code {
                KeyCode::Enter => {
                    self.start_install();
                    None
                }
                KeyCode::Esc => {
                    self.go_back();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Installing => match code {
                KeyCode::Esc => {
                    self.cancel();
                    None
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    self.scroll_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.scroll_down();
                    None
                }
                _ => None,
            },
            InstallPhase::Done => match code {
                KeyCode::Char('r') => Some(Action::Reboot),
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Failed(_) => match code {
                KeyCode::Char('q') => Some(Action::Quit),
                KeyCode::Up | KeyCode::Char('k') => {
                    self.scroll_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.scroll_down();
                    None
                }
                _ => None,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> InstallerConfig {
        InstallerConfig {
            source: InstallSource::PrebakedConfig,
            config_dir: PathBuf::from("/etc/keystone/install-config"),
            flake_host: "test-laptop".to_string(),
            hostname: "test-laptop".to_string(),
            username: Some("testuser".to_string()),
            repo_owner: Some("testuser".to_string()),
            github_username: None,
            storage_type: Some("ext4".to_string()),
            disk_device: Some("/dev/disk/by-id/nvme-TEST".to_string()),
            hardware_path: None,
        }
    }

    fn test_config_no_disk() -> InstallerConfig {
        InstallerConfig {
            source: InstallSource::PrebakedConfig,
            config_dir: PathBuf::from("/tmp/keystone-test-config"),
            flake_host: "test-laptop".to_string(),
            hostname: "test-laptop".to_string(),
            username: Some("testuser".to_string()),
            repo_owner: Some("testuser".to_string()),
            github_username: None,
            storage_type: Some("ext4".to_string()),
            disk_device: None,
            hardware_path: None,
        }
    }

    fn test_embedded_repo_config() -> InstallerConfig {
        InstallerConfig {
            source: InstallSource::EmbeddedRepo {
                repo_dir: PathBuf::from("/etc/keystone/install-repo"),
                repo_name: "keystone-config".to_string(),
                targets: vec![
                    InstallTarget {
                        flake_host: "laptop".to_string(),
                        hostname: "keystone".to_string(),
                        system: Some("x86_64-linux".to_string()),
                        storage_type: Some("ext4".to_string()),
                        hardware_path: "hosts/laptop/hardware.nix".to_string(),
                    },
                    InstallTarget {
                        flake_host: "server-ocean".to_string(),
                        hostname: "server-ocean".to_string(),
                        system: Some("x86_64-linux".to_string()),
                        storage_type: Some("zfs".to_string()),
                        hardware_path: "hosts/server-ocean/hardware.nix".to_string(),
                    },
                ],
            },
            config_dir: PathBuf::from("/etc/keystone/install-repo"),
            flake_host: String::new(),
            hostname: String::new(),
            username: Some("noah".to_string()),
            repo_owner: Some("noah".to_string()),
            github_username: None,
            storage_type: None,
            disk_device: None,
            hardware_path: None,
        }
    }

    #[test]
    fn test_initial_phase_is_summary() {
        let screen = InstallScreen::new(test_config());
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_embedded_repo_initial_phase_is_host_selection() {
        let screen = InstallScreen::new(test_embedded_repo_config());
        assert_eq!(*screen.phase(), InstallPhase::HostSelection);
        assert_eq!(screen.available_hosts().len(), 2);
    }

    #[test]
    fn test_host_navigation() {
        let mut screen = InstallScreen::new(test_embedded_repo_config());
        assert_eq!(screen.selected_host_index(), 0);

        screen.host_down();
        assert_eq!(screen.selected_host_index(), 1);

        screen.host_down();
        assert_eq!(screen.selected_host_index(), 0);

        screen.host_up();
        assert_eq!(screen.selected_host_index(), 1);
    }

    #[tokio::test]
    async fn test_proceed_to_disk_selection() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[test]
    fn test_go_back_from_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.phase = InstallPhase::Confirm;
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[test]
    fn test_go_back_from_summary_is_noop() {
        let mut screen = InstallScreen::new(test_config());
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_go_back_from_summary_returns_to_host_selection_for_embedded_repo() {
        let mut screen = InstallScreen::new(test_embedded_repo_config());
        screen.phase = InstallPhase::Summary;
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::HostSelection);
    }

    #[test]
    fn test_poll_collects_output() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::Installing;

        tx.send(InstallMessage::Output("partitioning...".to_string()))
            .unwrap();
        tx.send(InstallMessage::Output("formatting...".to_string()))
            .unwrap();

        screen.poll();
        assert_eq!(screen.output_lines().len(), 2);
    }

    #[test]
    fn test_poll_handles_success() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::Installing;

        tx.send(InstallMessage::Finished(InstallResult::Success))
            .unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), InstallPhase::Done);
        assert!(screen.is_finished());
    }

    #[test]
    fn test_poll_handles_failure() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::Installing;

        tx.send(InstallMessage::Finished(InstallResult::Failed(
            "disk error".to_string(),
        )))
        .unwrap();

        screen.poll();
        assert!(matches!(screen.phase(), InstallPhase::Failed(_)));
        assert!(screen.is_finished());
    }

    #[test]
    fn test_scroll_behavior() {
        let mut screen = InstallScreen::new(test_config());
        assert!(screen.auto_scroll);

        screen.scroll_up();
        assert!(!screen.auto_scroll);

        screen.scroll_down();
        assert!(screen.auto_scroll);
    }

    #[tokio::test]
    async fn test_proceed_with_disk_goes_to_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[tokio::test]
    async fn test_proceed_without_disk_goes_to_selection() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[test]
    fn test_disk_navigation() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.available_disks = vec![
            DiskEntry {
                by_id_path: "/dev/disk/by-id/nvme-disk1".to_string(),
                model: "Samsung 980 PRO".to_string(),
                size: "1T".to_string(),
                transport: "nvme".to_string(),
            },
            DiskEntry {
                by_id_path: "/dev/disk/by-id/ata-disk2".to_string(),
                model: "WD Blue".to_string(),
                size: "2T".to_string(),
                transport: "sata".to_string(),
            },
        ];
        assert_eq!(screen.selected_disk_index(), 0);

        screen.disk_down();
        assert_eq!(screen.selected_disk_index(), 1);

        screen.disk_down();
        assert_eq!(screen.selected_disk_index(), 0); // wrap

        screen.disk_up();
        assert_eq!(screen.selected_disk_index(), 1); // wrap back
    }

    #[test]
    fn test_go_back_from_disk_selection() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.phase = InstallPhase::DiskSelection;
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_poll_discovers_disks() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config_no_disk(), rx);
        screen.phase = InstallPhase::DiskSelection;
        screen.discovering_disks = true;

        tx.send(InstallMessage::DisksDiscovered(vec![DiskEntry {
            by_id_path: "/dev/disk/by-id/nvme-test".to_string(),
            model: "Test Disk".to_string(),
            size: "500G".to_string(),
            transport: "nvme".to_string(),
        }]))
        .unwrap();

        screen.poll();
        assert!(!screen.discovering_disks);
        assert_eq!(screen.available_disks().len(), 1);
    }

    #[test]
    fn test_poll_preselects_configured_disk() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::DiskSelection;
        screen.discovering_disks = true;

        tx.send(InstallMessage::DisksDiscovered(vec![
            DiskEntry {
                by_id_path: "/dev/disk/by-id/ata-other".to_string(),
                model: "Other Disk".to_string(),
                size: "1T".to_string(),
                transport: "sata".to_string(),
            },
            DiskEntry {
                by_id_path: "/dev/disk/by-id/nvme-TEST".to_string(),
                model: "Preferred Disk".to_string(),
                size: "2T".to_string(),
                transport: "nvme".to_string(),
            },
        ]))
        .unwrap();

        screen.poll();
        assert_eq!(screen.selected_disk_index(), 1);
    }

    #[test]
    fn test_preferred_disk_index_falls_back_to_first_disk() {
        let disks = vec![
            DiskEntry {
                by_id_path: "/dev/disk/by-id/nvme-first".to_string(),
                model: "Fast Disk".to_string(),
                size: "1T".to_string(),
                transport: "nvme".to_string(),
            },
            DiskEntry {
                by_id_path: "/dev/disk/by-id/ata-second".to_string(),
                model: "Slow Disk".to_string(),
                size: "2T".to_string(),
                transport: "sata".to_string(),
            },
        ];

        assert_eq!(preferred_disk_index(&disks, None), 0);
        assert_eq!(
            preferred_disk_index(&disks, Some("/dev/disk/by-id/missing")),
            0
        );
    }

    #[test]
    fn test_set_disk_by_path_selects_requested_disk() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.available_disks = vec![
            DiskEntry {
                by_id_path: "/dev/disk/by-id/ata-other".to_string(),
                model: "Other Disk".to_string(),
                size: "1T".to_string(),
                transport: "sata".to_string(),
            },
            DiskEntry {
                by_id_path: "/dev/disk/by-id/virtio-keystone-test-disk".to_string(),
                model: "Fixture Disk".to_string(),
                size: "64G".to_string(),
                transport: "virtio".to_string(),
            },
        ];

        screen
            .set_disk_by_path("/dev/disk/by-id/virtio-keystone-test-disk")
            .unwrap();

        assert_eq!(screen.selected_disk_index(), 1);
    }

    #[test]
    fn test_set_disk_by_path_errors_when_requested_disk_missing() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.available_disks = vec![DiskEntry {
            by_id_path: "/dev/disk/by-id/ata-other".to_string(),
            model: "Other Disk".to_string(),
            size: "1T".to_string(),
            transport: "sata".to_string(),
        }];

        let error = screen
            .set_disk_by_path("/dev/disk/by-id/virtio-keystone-test-disk")
            .unwrap_err();

        assert!(error
            .contains("Requested disk '/dev/disk/by-id/virtio-keystone-test-disk' was not found."));
        assert!(error.contains("Discovered disks:"));
        assert!(error.contains("Best guess: /dev/disk/by-id/ata-other"));
    }

    #[test]
    fn test_build_headless_confirmation_message_for_auto_selected_disk() {
        let disks = vec![DiskEntry {
            by_id_path: "/dev/disk/by-id/nvme-best".to_string(),
            model: "Best Disk".to_string(),
            size: "2T".to_string(),
            transport: "nvme".to_string(),
        }];

        let message = build_headless_confirmation_message(
            "laptop",
            "/dev/disk/by-id/nvme-best",
            HeadlessSelectionSource::AutoSelected,
            &disks,
        );

        assert!(message.contains("No --disk was provided for host 'laptop'."));
        assert!(message.contains("This will erase all data on '/dev/disk/by-id/nvme-best'."));
        assert!(message.contains("Type 'destroy' to confirm installation"));
    }

    #[test]
    fn test_build_headless_confirmation_message_for_prompted_disk() {
        let disks = vec![DiskEntry {
            by_id_path: "/dev/disk/by-id/nvme-best".to_string(),
            model: "Best Disk".to_string(),
            size: "2T".to_string(),
            transport: "nvme".to_string(),
        }];

        let message = build_headless_confirmation_message(
            "laptop",
            "/dev/disk/by-id/nvme-best",
            HeadlessSelectionSource::Prompted,
            &disks,
        );

        assert!(message.contains("Headless install is ready for host 'laptop'"));
        assert!(!message.contains("Only available install disk"));
    }

    #[test]
    fn test_parse_headless_disk_selection_accepts_enter_for_default() {
        assert_eq!(parse_headless_disk_selection("", 3, 1).unwrap(), 1);
        assert_eq!(parse_headless_disk_selection(" \n", 3, 2).unwrap(), 2);
    }

    #[test]
    fn test_parse_headless_disk_selection_accepts_one_based_choice() {
        assert_eq!(parse_headless_disk_selection("2", 3, 0).unwrap(), 1);
    }

    #[test]
    fn test_parse_headless_disk_selection_rejects_invalid_choice() {
        let error = parse_headless_disk_selection("9", 3, 0).unwrap_err();

        assert!(error.contains("Expected a disk number between 1 and 3"));
    }

    #[test]
    fn test_build_command_spec_wraps_privileged_commands_in_sudo() {
        let command = build_command_spec("disko", &["--mode", "disko"], true);

        assert_eq!(command.program, "sudo");
        assert_eq!(command.args, vec!["-n", "disko", "--mode", "disko"]);
    }

    #[test]
    fn test_build_command_spec_keeps_non_privileged_commands_direct() {
        let command = build_command_spec("disko", &["--mode", "disko"], false);

        assert_eq!(command.program, "disko");
        assert_eq!(command.args, vec!["--mode", "disko"]);
    }

    #[test]
    fn test_prebaked_config_defaults_installed_repo_name_to_keystone_config() {
        assert_eq!(
            test_config().installed_repo_name(),
            DEFAULT_INSTALLED_REPO_NAME
        );
    }

    #[test]
    fn test_embedded_repo_uses_configured_installed_repo_name() {
        assert_eq!(
            test_embedded_repo_config().installed_repo_name(),
            "keystone-config"
        );
    }

    #[test]
    fn test_installed_repo_paths_returns_canonical_and_mounted_paths() {
        let (system_repo_dir, mounted_repo_dir) =
            installed_repo_paths("noah", "noah", "keystone-config");

        assert_eq!(
            system_repo_dir,
            PathBuf::from("/home/noah/repos/noah/keystone-config")
        );
        assert_eq!(
            mounted_repo_dir,
            PathBuf::from("/mnt/home/noah/repos/noah/keystone-config")
        );
    }

    #[test]
    fn test_normalize_staged_install_repo_restores_lock_and_removes_vendored_input() {
        let temp = tempfile::tempdir().unwrap();
        let source_lock = temp.path().join("source-flake.lock");
        let repo_dir = temp.path().join("repo");
        let vendored_dir = repo_dir.join(VENDORED_KEYSTONE_INPUT_DIR);

        std::fs::create_dir_all(&vendored_dir).unwrap();
        std::fs::write(&source_lock, "original-lock").unwrap();
        std::fs::write(repo_dir.join("flake.lock"), "path-lock").unwrap();
        std::fs::write(vendored_dir.join("CLAUDE.md"), "vendored").unwrap();

        normalize_staged_install_repo(&repo_dir, &source_lock).unwrap();

        assert_eq!(
            std::fs::read_to_string(repo_dir.join("flake.lock")).unwrap(),
            "original-lock"
        );
        assert!(!vendored_dir.exists());
    }

    #[test]
    fn test_normalize_staged_install_repo_requires_source_lock_when_vendored_input_exists() {
        let temp = tempfile::tempdir().unwrap();
        let source_lock = temp.path().join("missing-flake.lock");
        let repo_dir = temp.path().join("repo");
        let vendored_dir = repo_dir.join(VENDORED_KEYSTONE_INPUT_DIR);

        std::fs::create_dir_all(&vendored_dir).unwrap();
        std::fs::write(repo_dir.join("flake.lock"), "path-lock").unwrap();

        let error = normalize_staged_install_repo(&repo_dir, &source_lock).unwrap_err();

        assert!(error.contains("missing"));
        assert!(vendored_dir.exists());
        assert_eq!(
            std::fs::read_to_string(repo_dir.join("flake.lock")).unwrap(),
            "path-lock"
        );
    }

    #[test]
    fn test_normalize_staged_install_repo_keeps_flake_lock_writable() {
        use std::os::unix::fs::PermissionsExt;

        let temp = tempfile::tempdir().unwrap();
        let source_lock = temp.path().join("source-flake.lock");
        let repo_dir = temp.path().join("repo");
        let vendored_dir = repo_dir.join(VENDORED_KEYSTONE_INPUT_DIR);
        let target_lock = repo_dir.join("flake.lock");

        std::fs::create_dir_all(&vendored_dir).unwrap();
        std::fs::write(&source_lock, "original-lock").unwrap();
        std::fs::write(&target_lock, "path-lock").unwrap();
        std::fs::set_permissions(&source_lock, std::fs::Permissions::from_mode(0o444)).unwrap();
        std::fs::set_permissions(&target_lock, std::fs::Permissions::from_mode(0o644)).unwrap();

        normalize_staged_install_repo(&repo_dir, &source_lock).unwrap();

        let mode = std::fs::metadata(&target_lock)
            .unwrap()
            .permissions()
            .mode();
        assert_ne!(mode & 0o200, 0);
    }

    #[test]
    fn test_normalize_staged_install_repo_is_noop_without_vendored_input() {
        let temp = tempfile::tempdir().unwrap();
        let source_lock = temp.path().join("source-flake.lock");
        let repo_dir = temp.path().join("repo");
        let target_lock = repo_dir.join("flake.lock");

        std::fs::create_dir_all(&repo_dir).unwrap();
        std::fs::write(&source_lock, "original-lock").unwrap();
        std::fs::write(&target_lock, "existing-lock").unwrap();

        normalize_staged_install_repo(&repo_dir, &source_lock).unwrap();

        assert_eq!(
            std::fs::read_to_string(&target_lock).unwrap(),
            "existing-lock"
        );
    }

    #[tokio::test]
    async fn test_copy_dir_recursive_async_preserves_symlinks() {
        let temp = tempfile::tempdir().unwrap();
        let src = temp.path().join("src");
        let dst = temp.path().join("dst");

        std::fs::create_dir_all(&src).unwrap();
        tokio::fs::create_dir_all(&dst).await.unwrap();
        std::fs::write(src.join("target.txt"), "hello").unwrap();
        std::os::unix::fs::symlink("target.txt", src.join("link.txt")).unwrap();

        copy_dir_recursive_async(&src, &dst).await.unwrap();

        let metadata = std::fs::symlink_metadata(dst.join("link.txt")).unwrap();
        assert!(metadata.file_type().is_symlink());
        assert_eq!(
            std::fs::read_link(dst.join("link.txt")).unwrap(),
            PathBuf::from("target.txt")
        );
    }

    #[test]
    fn test_ensure_marker_gitignore_contents_preserves_existing_entries() {
        let updated = ensure_marker_gitignore_contents(Some("result\nnode_modules/\n"));
        assert_eq!(updated, "result\nnode_modules/\n.first-boot-pending\n");

        let unchanged = ensure_marker_gitignore_contents(Some(".first-boot-pending\n"));
        assert_eq!(unchanged, ".first-boot-pending\n");
    }

    #[test]
    fn test_merge_authorized_keys_appends_missing_keys_without_duplicates() {
        let merged = merge_authorized_keys(
            Some("ssh-ed25519 AAAA existing\n"),
            &[
                "ssh-ed25519 AAAA existing".to_string(),
                "ssh-ed25519 BBBB new".to_string(),
            ],
        );

        assert_eq!(merged, "ssh-ed25519 AAAA existing\nssh-ed25519 BBBB new\n");
    }

    #[test]
    fn test_build_reconciled_hardware_wrapper_preserves_keystone_fields() {
        let current = r#"let
  system = "x86_64-linux";
in
{
  inherit system;

  module =
    { config, lib, pkgs, modulesPath, ... }:
    {
      networking.hostId = "deadbeef";
      keystone.os.storage.devices = [
        "/dev/disk/by-id/test-disk"
      ];
      keystone.os.storage.mode = "mirror";
      keystone.os.remoteUnlock.networkModule = "e1000e";
    };
}
"#;

        let reconciled =
            build_reconciled_hardware_wrapper(current, Some("/dev/disk/by-id/fallback")).unwrap();

        assert!(reconciled.contains("./hardware-generated.nix"));
        assert!(reconciled.contains("networking.hostId = \"deadbeef\";"));
        assert!(reconciled.contains("\"/dev/disk/by-id/test-disk\""));
        assert!(reconciled.contains("keystone.os.storage.mode = \"mirror\";"));
        assert!(reconciled.contains("keystone.os.remoteUnlock.networkModule = \"e1000e\";"));
        assert!(reconciled.contains("hardware.enableRedistributableFirmware = true;"));
    }

    #[test]
    fn test_build_reconciled_hardware_wrapper_uses_selected_disk_fallback() {
        let current = r#"let
  system = "x86_64-linux";
in
{
  inherit system;

  module = { ... }: {
    networking.hostId = "deadbeef";
  };
}
"#;

        let reconciled =
            build_reconciled_hardware_wrapper(current, Some("/dev/disk/by-id/fallback")).unwrap();

        assert!(reconciled.contains("\"/dev/disk/by-id/fallback\""));
    }

    #[test]
    fn test_build_reconciled_hardware_wrapper_generates_host_id_from_placeholder() {
        let current = r#"let
  system = "x86_64-linux";
in
{
  inherit system;

  module = { ... }: {
    networking.hostId = "00000000";
    keystone.os.storage.devices = [
      "__KEYSTONE_DISK__"
    ];
  };
}
"#;

        let reconciled =
            build_reconciled_hardware_wrapper(current, Some("/dev/disk/by-id/fallback")).unwrap();

        assert!(!reconciled.contains("networking.hostId = \"00000000\";"));
        assert!(reconciled.contains("\"/dev/disk/by-id/fallback\""));
    }

    #[test]
    fn test_strip_generated_storage_assignments_removes_storage_conflicts() {
        let generated = r#"
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "virtio_blk" ];
  fileSystems."/" =
    { device = "/dev/mapper/cryptroot";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/root";

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/boot";
      fsType = "vfat";
    };

  swapDevices = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
"#;

        let sanitized = strip_generated_storage_assignments(generated);

        assert!(sanitized.contains("imports = [ (modulesPath + \"/profiles/qemu-guest.nix\") ];"));
        assert!(sanitized.contains("boot.initrd.availableKernelModules = [ \"virtio_blk\" ];"));
        assert!(sanitized.contains("nixpkgs.hostPlatform = lib.mkDefault \"x86_64-linux\";"));
        assert!(!sanitized.contains("fileSystems.\"/\""));
        assert!(!sanitized.contains("fileSystems.\"/boot\""));
        assert!(!sanitized.contains("boot.initrd.luks.devices.\"cryptroot\""));
        assert!(!sanitized.contains("swapDevices = [ ];"));
    }

    #[tokio::test]
    async fn validate_installed_hardware_passes_with_reconciled_files() {
        let repo = tempfile::tempdir().unwrap();
        let host_dir = repo.path().join("hosts").join("test-laptop");
        std::fs::create_dir_all(&host_dir).unwrap();
        std::fs::write(
            host_dir.join(GENERATED_HARDWARE_FILENAME),
            "{ /* generated */ }",
        )
        .unwrap();
        std::fs::write(
            host_dir.join("hardware.nix"),
            "{ imports = [ ./hardware-generated.nix ]; }",
        )
        .unwrap();

        let (tx, _rx) = mpsc::unbounded_channel();
        let result = validate_installed_hardware(repo.path(), "test-laptop", &tx).await;
        assert!(result.is_ok(), "Expected Ok, got: {:?}", result);
    }

    #[tokio::test]
    async fn validate_installed_hardware_fails_missing_generated() {
        let repo = tempfile::tempdir().unwrap();
        let host_dir = repo.path().join("hosts").join("test-laptop");
        std::fs::create_dir_all(&host_dir).unwrap();
        std::fs::write(host_dir.join("hardware.nix"), "{ }").unwrap();

        let (tx, _rx) = mpsc::unbounded_channel();
        let result = validate_installed_hardware(repo.path(), "test-laptop", &tx).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains(GENERATED_HARDWARE_FILENAME));
    }

    #[tokio::test]
    async fn validate_installed_hardware_fails_missing_import() {
        let repo = tempfile::tempdir().unwrap();
        let host_dir = repo.path().join("hosts").join("test-laptop");
        std::fs::create_dir_all(&host_dir).unwrap();
        std::fs::write(
            host_dir.join(GENERATED_HARDWARE_FILENAME),
            "{ /* generated */ }",
        )
        .unwrap();
        // hardware.nix exists but does NOT import hardware-generated.nix
        std::fs::write(
            host_dir.join("hardware.nix"),
            "{ imports = [ ./qemu-guest.nix ]; }",
        )
        .unwrap();

        let (tx, _rx) = mpsc::unbounded_channel();
        let result = validate_installed_hardware(repo.path(), "test-laptop", &tx).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("does not import"));
    }

    #[tokio::test]
    async fn validate_installed_hardware_fails_missing_hardware_nix() {
        let repo = tempfile::tempdir().unwrap();
        let host_dir = repo.path().join("hosts").join("test-laptop");
        std::fs::create_dir_all(&host_dir).unwrap();
        std::fs::write(
            host_dir.join(GENERATED_HARDWARE_FILENAME),
            "{ /* generated */ }",
        )
        .unwrap();
        // hardware-generated.nix exists but hardware.nix is missing

        let (tx, _rx) = mpsc::unbounded_channel();
        let result = validate_installed_hardware(repo.path(), "test-laptop", &tx).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("missing hardware.nix"));
    }

    #[test]
    fn test_inject_disk_into_hardware_replaces_devices_list() {
        let dir = tempfile::tempdir().unwrap();
        let hardware_path = dir.path().join("hardware.nix");
        let original = r#"{ config, pkgs, ... }:
{
  imports = [
    ./hardware-generated.nix
  ];

  other.setting = "keep";

  keystone.os.storage.devices = [
    "/dev/old-disk"
  ];

  networking.hostName = "demo";
}
"#;
        std::fs::write(&hardware_path, original).unwrap();

        InstallerConfig::inject_disk_into_hardware(&hardware_path, "/dev/disk/by-id/new-target")
            .unwrap();

        let updated = std::fs::read_to_string(&hardware_path).unwrap();
        assert!(
            updated.contains("\"/dev/disk/by-id/new-target\""),
            "should contain new device"
        );
        assert!(
            !updated.contains("/dev/old-disk"),
            "should not contain old device"
        );
        assert!(
            updated.contains("other.setting = \"keep\";"),
            "should preserve other attrs"
        );
        assert!(
            updated.contains("networking.hostName = \"demo\";"),
            "should preserve trailing attrs"
        );
        assert!(updated.ends_with('\n'), "should end with newline");
    }
}
