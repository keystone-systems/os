//! Disk discovery for the Keystone installer.
//!
//! Enumerates block devices via /dev/disk/by-id/ and correlates with lsblk
//! to provide model, size, and transport information for disk selection.

use std::path::Path;

// Must stay in sync with the installer ISO volume label defined by the build.
// Prefer setting INSTALLER_VOLUME_LABEL at compile time (for example from Nix)
// so installer-media exclusion cannot silently drift from the ISO label.
const INSTALLER_VOLUME_LABEL: &str = match option_env!("INSTALLER_VOLUME_LABEL") {
    Some(label) => label,
    None => "KEYSTONE",
};

/// A discovered disk device suitable for installation.
#[derive(Debug, Clone)]
pub struct DiskEntry {
    /// Stable by-id path, e.g. /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB
    pub by_id_path: String,
    /// Human-readable model name
    pub model: String,
    /// Size string, e.g. "1.8T"
    pub size: String,
    /// Transport type: nvme, sata, usb, etc.
    pub transport: String,
}

impl DiskEntry {
    /// Sort priority — NVMe first, then SATA, then everything else.
    fn sort_key(&self) -> u8 {
        match self.transport.as_str() {
            "nvme" => 0,
            "sata" => 1,
            "usb" => 3,
            _ => 2,
        }
    }
}

fn parse_blockdevices(lsblk_output: &[u8]) -> Vec<serde_json::Value> {
    serde_json::from_slice::<serde_json::Value>(lsblk_output)
        .unwrap_or_default()
        .get("blockdevices")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
}

fn installer_device_name(blockdevices: &[serde_json::Value]) -> Option<String> {
    let device = blockdevices.first()?;
    match device.get("type").and_then(|v| v.as_str()) {
        Some("disk") => device
            .get("name")
            .and_then(|v| v.as_str())
            .map(|name| name.to_string()),
        Some("part") => device
            .get("pkname")
            .and_then(|v| v.as_str())
            .map(|name| name.to_string()),
        _ => None,
    }
}

fn should_skip_by_id_name(name: &str) -> bool {
    name.contains("-part")
        || name.starts_with("wwn-")
        || name.starts_with("dm-")
        || name.contains("loop")
        || name.contains("cdrom")
        || name.contains("CD-ROM")
        || name.contains("DVD")
        || name.contains("dvd")
}

async fn collect_raw_links(by_id_dir: &Path) -> anyhow::Result<Vec<(String, String)>> {
    let mut entries = tokio::fs::read_dir(by_id_dir).await?;
    let mut raw_links = Vec::new();

    while let Some(entry) = entries.next_entry().await? {
        let name = entry.file_name().to_string_lossy().to_string();
        if should_skip_by_id_name(&name) {
            continue;
        }

        let full_path = by_id_dir.join(&name);
        if let Ok(target) = tokio::fs::read_link(&full_path).await {
            let dev_name = target
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            if !dev_name.is_empty() && !dev_name.starts_with("sr") {
                raw_links.push((name, dev_name));
            }
        }
    }

    Ok(raw_links)
}

fn by_id_priority(name: &str) -> u8 {
    if name.starts_with("nvme-") || name.starts_with("ata-") {
        0
    } else {
        1
    }
}

fn build_device_map(raw_links: &[(String, String)]) -> std::collections::HashMap<String, String> {
    let mut device_map: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();

    for (by_id_name, dev_name) in raw_links {
        let prefer_new = device_map
            .get(dev_name)
            .is_none_or(|old| by_id_priority(by_id_name) < by_id_priority(old));
        if prefer_new {
            device_map.insert(dev_name.clone(), by_id_name.clone());
        }
    }

    device_map
}

async fn discover_installer_device_name() -> anyhow::Result<Option<String>> {
    let installer_label_path = Path::new("/dev/disk/by-label").join(INSTALLER_VOLUME_LABEL);
    if !installer_label_path.exists() {
        return Ok(None);
    }

    let lsblk_output = tokio::process::Command::new("lsblk")
        .args(["--json", "-o", "NAME,PKNAME,TYPE"])
        .arg(installer_label_path)
        .output()
        .await?;

    if !lsblk_output.status.success() {
        return Ok(None);
    }

    Ok(installer_device_name(&parse_blockdevices(
        &lsblk_output.stdout,
    )))
}

fn find_lsblk_info<'a>(
    blockdevices: &'a [serde_json::Value],
    dev_name: &str,
) -> Option<&'a serde_json::Value> {
    blockdevices.iter().find(|device| {
        device
            .get("name")
            .and_then(|v| v.as_str())
            .is_some_and(|name| name == dev_name)
    })
}

fn build_disk_entry(
    dev_name: &str,
    by_id_name: &str,
    blockdevices: &[serde_json::Value],
) -> Option<DiskEntry> {
    let lsblk_info = find_lsblk_info(blockdevices, dev_name);
    if lsblk_info
        .and_then(|d| d.get("type"))
        .and_then(|v| v.as_str())
        .is_some_and(|device_type| device_type != "disk")
    {
        return None;
    }

    let model = lsblk_info
        .and_then(|d| d.get("model"))
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .trim()
        .to_string();

    let size = lsblk_info
        .and_then(|d| d.get("size"))
        .and_then(|v| v.as_str())
        .unwrap_or("?")
        .to_string();

    let transport = lsblk_info
        .and_then(|d| d.get("tran"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    Some(DiskEntry {
        by_id_path: format!("/dev/disk/by-id/{by_id_name}"),
        model,
        size,
        transport,
    })
}

/// Discover available disks by reading /dev/disk/by-id/ and correlating with lsblk.
///
/// Filters out partitions, device-mapper, loop devices, and CD-ROM entries.
/// Returns disks sorted by transport priority (NVMe > SATA > other > USB).
pub async fn discover_disks() -> anyhow::Result<Vec<DiskEntry>> {
    let by_id_dir = Path::new("/dev/disk/by-id");
    if !by_id_dir.exists() {
        return Ok(Vec::new());
    }

    // Get lsblk data for correlation
    let lsblk_output = tokio::process::Command::new("lsblk")
        .args(["--json", "-d", "-o", "NAME,SIZE,MODEL,TRAN,TYPE"])
        .output()
        .await?;

    let blockdevices = parse_blockdevices(&lsblk_output.stdout);
    let raw_links = collect_raw_links(by_id_dir).await?;
    let device_map = build_device_map(&raw_links);
    let installer_device_name = discover_installer_device_name().await?;

    // Build DiskEntry list by correlating with lsblk
    let mut disks: Vec<DiskEntry> = Vec::new();
    for (dev_name, by_id_name) in &device_map {
        if installer_device_name
            .as_deref()
            .is_some_and(|installer_device| installer_device == dev_name)
        {
            continue;
        }
        if let Some(entry) = build_disk_entry(dev_name, by_id_name, &blockdevices) {
            disks.push(entry);
        }
    }

    disks.sort_by_key(|d| (d.sort_key(), d.by_id_path.clone()));
    Ok(disks)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sort_key_priority() {
        let nvme = DiskEntry {
            by_id_path: String::new(),
            model: String::new(),
            size: String::new(),
            transport: "nvme".to_string(),
        };
        let sata = DiskEntry {
            by_id_path: String::new(),
            model: String::new(),
            size: String::new(),
            transport: "sata".to_string(),
        };
        let usb = DiskEntry {
            by_id_path: String::new(),
            model: String::new(),
            size: String::new(),
            transport: "usb".to_string(),
        };

        assert!(nvme.sort_key() < sata.sort_key());
        assert!(sata.sort_key() < usb.sort_key());
    }

    #[test]
    fn test_installer_device_name_prefers_parent_disk_for_partition() {
        let blockdevices = parse_blockdevices(
            br#"{
              "blockdevices": [
                {
                  "name": "sda1",
                  "pkname": "sda",
                  "type": "part"
                }
              ]
            }"#,
        );

        assert_eq!(
            installer_device_name(&blockdevices),
            Some("sda".to_string())
        );
    }

    #[test]
    fn test_installer_device_name_uses_disk_name_directly() {
        let blockdevices = parse_blockdevices(
            br#"{
              "blockdevices": [
                {
                  "name": "sda",
                  "type": "disk"
                }
              ]
            }"#,
        );

        assert_eq!(
            installer_device_name(&blockdevices),
            Some("sda".to_string())
        );
    }
}
