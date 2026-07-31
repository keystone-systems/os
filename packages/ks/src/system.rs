//! System monitoring: Tailscale peer status, local metrics via sysinfo, host matching.

use std::collections::HashMap;

use serde::Deserialize;
use sysinfo::{Components, Disks, System};
use tokio::sync::mpsc;

use crate::nix::HostInfo;

// ---------------------------------------------------------------------------
// Tailscale types + JSON parsing
// ---------------------------------------------------------------------------

/// Parsed result from `tailscale status --json`.
#[derive(Debug, Clone)]
pub struct TailscaleStatus {
    pub self_hostname: String,
    pub peers: HashMap<String, TailscalePeer>,
}

/// A single Tailscale peer.
#[derive(Debug, Clone)]
pub struct TailscalePeer {
    pub hostname: String,
    pub tailscale_ips: Vec<String>,
    pub online: bool,
    pub last_seen: String,
    pub os: String,
}

// -- serde helper structs (mirror tailscale JSON shape) --

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct TsStatusJson {
    #[serde(rename = "Self")]
    self_node: TsNodeJson,
    #[serde(default)]
    peer: HashMap<String, TsNodeJson>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct TsNodeJson {
    #[serde(default)]
    host_name: String,
    #[serde(default, rename = "TailscaleIPs")]
    tailscale_ips: Vec<String>,
    #[serde(default)]
    online: bool,
    #[serde(default)]
    last_seen: String,
    #[serde(default, rename = "OS")]
    os: String,
}

/// Parse the JSON output of `tailscale status --json`.
pub fn parse_tailscale_json(json: &str) -> anyhow::Result<TailscaleStatus> {
    let raw: TsStatusJson = serde_json::from_str(json)?;

    let peers = raw
        .peer
        .into_iter()
        .map(|(key, node)| {
            let peer = TailscalePeer {
                hostname: node.host_name,
                tailscale_ips: node.tailscale_ips,
                online: node.online,
                last_seen: node.last_seen,
                os: node.os,
            };
            (key, peer)
        })
        .collect();

    Ok(TailscaleStatus {
        self_hostname: raw.self_node.host_name,
        peers,
    })
}

// ---------------------------------------------------------------------------
// Local system metrics
// ---------------------------------------------------------------------------

/// Local system metrics collected from sysinfo.
#[derive(Debug, Clone)]
pub struct SystemMetrics {
    pub cpu_usage: f64,
    pub cpu_history: CpuHistory,
    pub memory_used: u64,
    pub memory_total: u64,
    pub swap_used: u64,
    pub swap_total: u64,
    pub disks: Vec<DiskInfo>,
    pub temperatures: Vec<TempReading>,
}

/// Ring buffer for CPU usage history (last N samples).
#[derive(Debug, Clone)]
pub struct CpuHistory {
    samples: Vec<f64>,
    capacity: usize,
}

impl CpuHistory {
    pub fn new(capacity: usize) -> Self {
        Self {
            samples: Vec::with_capacity(capacity),
            capacity,
        }
    }

    pub fn push(&mut self, value: f64) {
        if self.samples.len() >= self.capacity {
            self.samples.remove(0);
        }
        self.samples.push(value);
    }

    pub fn samples(&self) -> &[f64] {
        &self.samples
    }

    pub fn len(&self) -> usize {
        self.samples.len()
    }

    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }
}

/// Information about a single disk.
#[derive(Debug, Clone)]
pub struct DiskInfo {
    pub name: String,
    pub mount_point: String,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub filesystem: String,
}

impl DiskInfo {
    /// Percentage of disk space used (0.0 – 100.0). Returns 0.0 if total is 0.
    pub fn usage_percent(&self) -> f64 {
        if self.total_bytes == 0 {
            return 0.0;
        }
        let used = self.total_bytes - self.available_bytes;
        (used as f64 / self.total_bytes as f64) * 100.0
    }
}

/// A temperature reading from a hardware sensor.
#[derive(Debug, Clone)]
pub struct TempReading {
    pub label: String,
    pub current: f32,
    pub critical: Option<f32>,
}

impl TempReading {
    /// Whether the current temperature exceeds the critical threshold.
    pub fn is_critical(&self) -> bool {
        match self.critical {
            Some(crit) => self.current >= crit,
            None => false,
        }
    }
}

/// Collect current system metrics from sysinfo objects.
pub fn collect_metrics(sys: &System, disks: &Disks, components: &Components) -> SystemMetrics {
    let cpu_usage = sys.global_cpu_usage() as f64;

    let disk_infos: Vec<DiskInfo> = disks
        .list()
        .iter()
        .map(|d| DiskInfo {
            name: d.name().to_string_lossy().to_string(),
            mount_point: d.mount_point().to_string_lossy().to_string(),
            total_bytes: d.total_space(),
            available_bytes: d.available_space(),
            filesystem: d.file_system().to_string_lossy().to_string(),
        })
        .collect();

    let temps: Vec<TempReading> = components
        .list()
        .iter()
        .filter_map(|c| {
            c.temperature().map(|temp| TempReading {
                label: c.label().to_string(),
                current: temp,
                critical: c.critical(),
            })
        })
        .collect();

    SystemMetrics {
        cpu_usage,
        cpu_history: CpuHistory::new(60),
        memory_used: sys.used_memory(),
        memory_total: sys.total_memory(),
        swap_used: sys.used_swap(),
        swap_total: sys.total_swap(),
        disks: disk_infos,
        temperatures: temps,
    }
}

// ---------------------------------------------------------------------------
// Host matching
// ---------------------------------------------------------------------------

/// Combined status for a host on the dashboard.
#[derive(Debug, Clone)]
pub struct HostStatus {
    pub host_info: HostInfo,
    pub tailscale: Option<TailscalePeer>,
    pub metrics: Option<SystemMetrics>,
    pub is_local: bool,
}

/// Match parsed NixOS hosts to Tailscale peers and detect which host is local.
pub fn match_hosts_to_peers(hosts: &[HostInfo], ts: Option<&TailscaleStatus>) -> Vec<HostStatus> {
    let local_hostname = detect_local_hostname();

    let mut statuses: Vec<HostStatus> = hosts
        .iter()
        .map(|host| {
            let tailscale = ts.and_then(|status| {
                status
                    .peers
                    .values()
                    .find(|p| p.hostname.eq_ignore_ascii_case(&host.name))
                    .cloned()
            });

            let is_local = host.name.eq_ignore_ascii_case(&local_hostname);

            HostStatus {
                host_info: host.clone(),
                tailscale,
                metrics: None,
                is_local,
            }
        })
        .collect();

    // Sort local host first so the dashboard defaults to showing its metrics.
    // stable sort preserves the original flake ordering among non-local hosts.
    // !is_local: false (0) sorts before true (1), putting local host at index 0.
    statuses.sort_by_key(|s| !s.is_local);
    statuses
}

/// Get the local machine's hostname.
pub fn detect_local_hostname() -> String {
    System::host_name().unwrap_or_default()
}

// ---------------------------------------------------------------------------
// Dashboard messages (async channel pattern like BuildScreen)
// ---------------------------------------------------------------------------

/// Messages sent from background tasks to the dashboard UI.
#[derive(Debug)]
pub enum DashboardMessage {
    TailscaleUpdate(TailscaleStatus),
    MetricsUpdate(SystemMetrics),
    TailscaleUnavailable,
}

/// Spawn background polling tasks. Returns the receiver.
pub fn spawn_dashboard_poller() -> mpsc::UnboundedReceiver<DashboardMessage> {
    let (tx, rx) = mpsc::unbounded_channel();

    // Metrics polling task (every 1s)
    let tx_metrics = tx.clone();
    tokio::spawn(async move {
        let mut sys = System::new_all();
        // sysinfo needs two refreshes to compute CPU delta
        sys.refresh_cpu_usage();
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        loop {
            sys.refresh_cpu_usage();
            sys.refresh_memory();
            let disks = Disks::new_with_refreshed_list();
            let components = Components::new_with_refreshed_list();

            let metrics = collect_metrics(&sys, &disks, &components);
            if tx_metrics
                .send(DashboardMessage::MetricsUpdate(metrics))
                .is_err()
            {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    });

    // Tailscale polling task (every 10s)
    tokio::spawn(async move {
        loop {
            match tokio::process::Command::new("tailscale")
                .args(["status", "--json"])
                .output()
                .await
            {
                Ok(output) if output.status.success() => {
                    let json = String::from_utf8_lossy(&output.stdout);
                    match parse_tailscale_json(&json) {
                        Ok(status) => {
                            if tx.send(DashboardMessage::TailscaleUpdate(status)).is_err() {
                                break;
                            }
                        }
                        Err(_) => {
                            if tx.send(DashboardMessage::TailscaleUnavailable).is_err() {
                                break;
                            }
                        }
                    }
                }
                _ => {
                    if tx.send(DashboardMessage::TailscaleUnavailable).is_err() {
                        break;
                    }
                }
            }
            tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        }
    });

    rx
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // -- T1: parse valid JSON with Self + 1 peer --
    #[test]
    fn test_parse_tailscale_minimal() {
        let json = r#"{
            "Self": {
                "HostName": "my-laptop",
                "TailscaleIPs": ["100.64.0.1"],
                "Online": true,
                "OS": "linux"
            },
            "Peer": {
                "nodekey:abc123": {
                    "HostName": "my-server",
                    "TailscaleIPs": ["100.64.0.2", "fd7a::2"],
                    "Online": true,
                    "LastSeen": "2026-03-12T10:00:00Z",
                    "OS": "linux"
                }
            }
        }"#;

        let status = parse_tailscale_json(json).unwrap();
        assert_eq!(status.self_hostname, "my-laptop");
        assert_eq!(status.peers.len(), 1);

        let peer = status.peers.values().next().unwrap();
        assert_eq!(peer.hostname, "my-server");
        assert!(peer.online);
        assert_eq!(peer.tailscale_ips, vec!["100.64.0.2", "fd7a::2"]);
    }

    // -- T2: empty peer map --
    #[test]
    fn test_parse_tailscale_no_peers() {
        let json = r#"{
            "Self": {
                "HostName": "lonely-host",
                "TailscaleIPs": ["100.64.0.1"],
                "Online": true,
                "OS": "linux"
            },
            "Peer": {}
        }"#;

        let status = parse_tailscale_json(json).unwrap();
        assert_eq!(status.self_hostname, "lonely-host");
        assert!(status.peers.is_empty());
    }

    // -- T3: offline peer --
    #[test]
    fn test_parse_tailscale_offline_peer() {
        let json = r#"{
            "Self": {
                "HostName": "laptop",
                "TailscaleIPs": ["100.64.0.1"],
                "Online": true,
                "OS": "linux"
            },
            "Peer": {
                "nodekey:xyz": {
                    "HostName": "rpi",
                    "TailscaleIPs": ["100.64.0.3"],
                    "Online": false,
                    "LastSeen": "2026-03-12T08:00:00Z",
                    "OS": "linux"
                }
            }
        }"#;

        let status = parse_tailscale_json(json).unwrap();
        let peer = status.peers.values().next().unwrap();
        assert!(!peer.online);
        assert_eq!(peer.last_seen, "2026-03-12T08:00:00Z");
    }

    // -- T4: invalid JSON --
    #[test]
    fn test_parse_tailscale_invalid_json() {
        let result = parse_tailscale_json("not valid json {{{");
        assert!(result.is_err());
    }

    // -- T5: missing optional fields default gracefully --
    #[test]
    fn test_parse_tailscale_missing_fields() {
        let json = r#"{
            "Self": {
                "HostName": "host"
            },
            "Peer": {
                "nodekey:a": {}
            }
        }"#;

        let status = parse_tailscale_json(json).unwrap();
        assert_eq!(status.self_hostname, "host");
        let peer = status.peers.values().next().unwrap();
        assert!(peer.hostname.is_empty());
        assert!(peer.tailscale_ips.is_empty());
        assert!(!peer.online);
        assert!(peer.last_seen.is_empty());
        assert!(peer.os.is_empty());
    }

    // -- T6: disk usage percent --
    #[test]
    fn test_disk_usage_percent() {
        let disk = DiskInfo {
            name: "nvme0n1".to_string(),
            mount_point: "/".to_string(),
            total_bytes: 1_000_000_000_000,   // 1 TB
            available_bytes: 250_000_000_000, // 250 GB free = 750 GB used
            filesystem: "ext4".to_string(),
        };
        let pct = disk.usage_percent();
        assert!((pct - 75.0).abs() < 0.01);
    }

    // -- T7: zero-total disk (no div-by-zero) --
    #[test]
    fn test_disk_usage_percent_empty() {
        let disk = DiskInfo {
            name: "empty".to_string(),
            mount_point: "/mnt".to_string(),
            total_bytes: 0,
            available_bytes: 0,
            filesystem: "tmpfs".to_string(),
        };
        assert_eq!(disk.usage_percent(), 0.0);
    }

    // -- T8: temperature critical detection --
    #[test]
    fn test_temp_is_critical() {
        let hot = TempReading {
            label: "CPU".to_string(),
            current: 95.0,
            critical: Some(90.0),
        };
        assert!(hot.is_critical());

        let cool = TempReading {
            label: "CPU".to_string(),
            current: 50.0,
            critical: Some(90.0),
        };
        assert!(!cool.is_critical());

        let no_crit = TempReading {
            label: "GPU".to_string(),
            current: 80.0,
            critical: None,
        };
        assert!(!no_crit.is_critical());
    }

    // -- T9: match hosts to peers exactly --
    #[test]
    fn test_match_hosts_exact() {
        let hosts = vec![
            HostInfo {
                name: "laptop".to_string(),
                system: Some("x86_64-linux".to_string()),
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "server".to_string(),
                system: Some("x86_64-linux".to_string()),
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
        ];

        let mut peers = HashMap::new();
        peers.insert(
            "nodekey:a".to_string(),
            TailscalePeer {
                hostname: "laptop".to_string(),
                tailscale_ips: vec!["100.64.0.1".to_string()],
                online: true,
                last_seen: String::new(),
                os: "linux".to_string(),
            },
        );
        peers.insert(
            "nodekey:b".to_string(),
            TailscalePeer {
                hostname: "server".to_string(),
                tailscale_ips: vec!["100.64.0.2".to_string()],
                online: true,
                last_seen: String::new(),
                os: "linux".to_string(),
            },
        );
        let ts = TailscaleStatus {
            self_hostname: "laptop".to_string(),
            peers,
        };

        let statuses = match_hosts_to_peers(&hosts, Some(&ts));
        assert_eq!(statuses.len(), 2);
        assert!(statuses[0].tailscale.is_some());
        assert_eq!(statuses[0].tailscale.as_ref().unwrap().hostname, "laptop");
        assert!(statuses[1].tailscale.is_some());
        assert_eq!(statuses[1].tailscale.as_ref().unwrap().hostname, "server");
    }

    // -- T10: no tailscale available --
    #[test]
    fn test_match_hosts_no_tailscale() {
        let hosts = vec![HostInfo {
            name: "lonely".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        }];

        let statuses = match_hosts_to_peers(&hosts, None);
        assert_eq!(statuses.len(), 1);
        assert!(statuses[0].tailscale.is_none());
    }

    // -- T11: local hostname detection --
    #[test]
    fn test_match_hosts_local_detection() {
        let local = detect_local_hostname();
        let hosts = vec![
            HostInfo {
                name: local.clone(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "remote-box".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
        ];

        let statuses = match_hosts_to_peers(&hosts, None);
        assert!(statuses[0].is_local);
        assert!(!statuses[1].is_local);
    }

    // -- T12: CPU history ring buffer --
    #[test]
    fn test_cpu_history_ring_buffer() {
        let mut hist = CpuHistory::new(60);
        for i in 0..70 {
            hist.push(i as f64);
        }
        assert_eq!(hist.len(), 60);
        // Oldest should be 10.0 (0-9 dropped)
        assert_eq!(hist.samples()[0], 10.0);
        assert_eq!(hist.samples()[59], 69.0);
    }

    // -- T13: collect_metrics produces valid output --
    #[test]
    fn test_collect_metrics_basic() {
        let mut sys = System::new_all();
        sys.refresh_cpu_usage();
        std::thread::sleep(std::time::Duration::from_millis(200));
        sys.refresh_cpu_usage();
        sys.refresh_memory();

        let disks = Disks::new_with_refreshed_list();
        let components = Components::new_with_refreshed_list();

        let metrics = collect_metrics(&sys, &disks, &components);
        // CPU usage should be a valid percentage
        assert!(metrics.cpu_usage >= 0.0 && metrics.cpu_usage <= 100.0);
        // Total memory should be > 0 on any real system
        assert!(metrics.memory_total > 0);
    }
}
