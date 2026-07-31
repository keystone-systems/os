//! Render snapshot tests using ratatui TestBackend + insta.
//!
//! These tests render each screen to an in-memory buffer and snapshot
//! the output, ensuring the UI doesn't regress.

use ratatui::{backend::TestBackend, Terminal};

use ks::components::build::{BuildMessage, BuildResult, BuildScreen};
use ks::components::host_detail::HostDetailScreen;
use ks::components::hosts::HostsScreen;
use ks::components::welcome::WelcomeScreen;
use ks::nix::HostInfo;
use ks::system::{CpuHistory, DiskInfo, HostStatus, SystemMetrics, TailscalePeer, TempReading};
use tokio::sync::mpsc;

/// Render a screen to a string using TestBackend.
fn render_to_string<F>(width: u16, height: u16, mut render_fn: F) -> String
where
    F: FnMut(&mut ratatui::Frame),
{
    let backend = TestBackend::new(width, height);
    let mut terminal = Terminal::new(backend).unwrap();
    terminal
        .draw(|frame| {
            render_fn(frame);
        })
        .unwrap();

    // Convert the buffer to a string representation
    let backend = terminal.backend();
    let buffer = backend.buffer();
    let mut output = String::new();
    for y in 0..buffer.area.height {
        for x in 0..buffer.area.width {
            let cell = &buffer[(x, y)];
            output.push_str(cell.symbol());
        }
        output.push('\n');
    }
    output
}

#[test]
fn test_render_welcome_screen() {
    let screen = WelcomeScreen::new();
    let output = render_to_string(60, 20, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_hosts_list() {
    let hosts = vec![
        HostInfo {
            name: "laptop".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec!["operating-system".to_string()],
            config_files: vec![],
            metadata: None,
        },
        HostInfo {
            name: "server".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec!["operating-system".to_string()],
            config_files: vec![],
            metadata: None,
        },
    ];
    let mut screen = HostsScreen::new("my-infra".to_string(), hosts);
    let output = render_to_string(60, 15, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_host_detail() {
    let host = HostInfo {
        name: "workstation".to_string(),
        system: Some("x86_64-linux".to_string()),
        keystone_modules: vec!["operating-system".to_string(), "desktop".to_string()],
        config_files: vec![
            "./configuration.nix".to_string(),
            "./hardware.nix".to_string(),
        ],
        metadata: None,
    };
    let screen = HostDetailScreen::new(host);
    let output = render_to_string(60, 18, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_empty_hosts() {
    let mut screen = HostsScreen::new("empty-repo".to_string(), Vec::new());
    let output = render_to_string(60, 15, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_build_screen_with_output() {
    let (tx, rx) = mpsc::unbounded_channel();
    let mut screen = BuildScreen::new_with_channel("test-host".to_string(), rx);

    tx.send(BuildMessage::Output(
        "$ nixos-rebuild build --flake .#test-host".to_string(),
    ))
    .unwrap();
    tx.send(BuildMessage::Output(String::new())).unwrap();
    tx.send(BuildMessage::Output(
        "building '/nix/store/...'".to_string(),
    ))
    .unwrap();
    tx.send(BuildMessage::Finished(BuildResult::Success))
        .unwrap();
    screen.poll();

    let output = render_to_string(60, 15, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

// ---------------------------------------------------------------------------
// T21-T25: Dashboard snapshot tests
// ---------------------------------------------------------------------------

fn make_dashboard_statuses() -> Vec<HostStatus> {
    vec![
        HostStatus {
            host_info: HostInfo {
                name: "laptop".to_string(),
                system: Some("x86_64-linux".to_string()),
                keystone_modules: vec!["operating-system".to_string()],
                config_files: vec![],
                metadata: None,
            },
            tailscale: Some(TailscalePeer {
                hostname: "laptop".to_string(),
                tailscale_ips: vec!["100.64.0.1".to_string()],
                online: true,
                last_seen: String::new(),
                os: "linux".to_string(),
            }),
            metrics: Some(SystemMetrics {
                cpu_usage: 45.2,
                cpu_history: CpuHistory::new(60),
                memory_used: 8_589_934_592,
                memory_total: 17_179_869_184,
                swap_used: 536_870_912,
                swap_total: 4_294_967_296,
                disks: vec![
                    DiskInfo {
                        name: "nvme0n1p2".to_string(),
                        mount_point: "/".to_string(),
                        total_bytes: 500_000_000_000,
                        available_bytes: 110_000_000_000,
                        filesystem: "ext4".to_string(),
                    },
                    DiskInfo {
                        name: "nvme0n1p3".to_string(),
                        mount_point: "/nix".to_string(),
                        total_bytes: 500_000_000_000,
                        available_bytes: 180_000_000_000,
                        filesystem: "ext4".to_string(),
                    },
                ],
                temperatures: vec![
                    TempReading {
                        label: "CPU".to_string(),
                        current: 52.0,
                        critical: Some(100.0),
                    },
                    TempReading {
                        label: "GPU".to_string(),
                        current: 48.0,
                        critical: Some(95.0),
                    },
                ],
            }),
            is_local: true,
        },
        HostStatus {
            host_info: HostInfo {
                name: "server".to_string(),
                system: Some("x86_64-linux".to_string()),
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            tailscale: Some(TailscalePeer {
                hostname: "server".to_string(),
                tailscale_ips: vec!["100.64.0.2".to_string()],
                online: true,
                last_seen: String::new(),
                os: "linux".to_string(),
            }),
            metrics: None,
            is_local: false,
        },
        HostStatus {
            host_info: HostInfo {
                name: "rpi".to_string(),
                system: Some("aarch64-linux".to_string()),
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            tailscale: Some(TailscalePeer {
                hostname: "rpi".to_string(),
                tailscale_ips: vec!["100.64.0.3".to_string()],
                online: false,
                last_seen: "2026-03-12T08:00:00Z".to_string(),
                os: "linux".to_string(),
            }),
            metrics: None,
            is_local: false,
        },
    ]
}

// T21: dashboard with metrics (CPU, memory, disks, gauges)
#[test]
fn test_render_dashboard_with_metrics() {
    let statuses = make_dashboard_statuses();
    let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
    // Simulate tailscale being available
    let output = render_to_string(80, 25, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

// T22: dashboard with tailscale status indicators
#[test]
fn test_render_dashboard_with_tailscale() {
    let statuses = make_dashboard_statuses();
    let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
    let output = render_to_string(80, 20, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

// T23: dashboard without tailscale (graceful fallback)
#[test]
fn test_render_dashboard_no_tailscale() {
    let statuses = vec![
        HostStatus {
            host_info: HostInfo {
                name: "laptop".to_string(),
                system: Some("x86_64-linux".to_string()),
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            tailscale: None,
            metrics: None,
            is_local: true,
        },
        HostStatus {
            host_info: HostInfo {
                name: "server".to_string(),
                system: Some("x86_64-linux".to_string()),
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            tailscale: None,
            metrics: None,
            is_local: false,
        },
    ];
    let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
    let output = render_to_string(80, 20, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

// T24: dashboard with temperature readings and color coding
#[test]
fn test_render_dashboard_with_temps() {
    let mut statuses = make_dashboard_statuses();
    // Add a critical temp to the local host metrics
    if let Some(ref mut metrics) = statuses[0].metrics {
        metrics.temperatures.push(TempReading {
            label: "NVMe".to_string(),
            current: 95.0,
            critical: Some(90.0),
        });
    }
    let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
    let output = render_to_string(80, 25, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

// T25: dashboard with empty hosts (still works)
#[test]
fn test_render_dashboard_empty() {
    let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), Vec::new());
    let output = render_to_string(80, 20, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}
