//! Hosts dashboard screen — split-panel host list with detail sidebar.

use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame,
};

use crate::theme;

use tokio::sync::mpsc;

use crate::action::{Action, Screen};
use crate::component::Component;
use crate::nix::HostInfo;
use crate::system::{DashboardMessage, HostStatus, SystemMetrics, TailscaleStatus};

/// Screen for the hosts dashboard with live system metrics.
pub struct HostsScreen {
    repo_name: String,
    statuses: Vec<HostStatus>,
    list_state: ListState,
    /// Channel for receiving async dashboard updates.
    rx: Option<mpsc::UnboundedReceiver<DashboardMessage>>,
    /// Latest tailscale status for online counting.
    tailscale_available: bool,
    /// Optional warning banner (e.g., legacy config version).
    warning: Option<String>,
}

impl HostsScreen {
    pub fn new(repo_name: String, hosts: Vec<HostInfo>) -> Self {
        Self::new_with_preferred_host(repo_name, hosts, None)
    }

    pub fn new_with_preferred_host(
        repo_name: String,
        hosts: Vec<HostInfo>,
        preferred_hostname: Option<&str>,
    ) -> Self {
        let statuses: Vec<HostStatus> = hosts
            .into_iter()
            .map(|h| HostStatus {
                host_info: h,
                tailscale: None,
                metrics: None,
                is_local: false,
            })
            .collect();

        Self::new_with_statuses_and_preferred_host(repo_name, statuses, preferred_hostname)
    }

    /// Create a dashboard from pre-built HostStatus entries.
    pub fn new_with_statuses(repo_name: String, statuses: Vec<HostStatus>) -> Self {
        Self::new_with_statuses_and_preferred_host(repo_name, statuses, None)
    }

    pub fn new_with_statuses_and_preferred_host(
        repo_name: String,
        statuses: Vec<HostStatus>,
        preferred_hostname: Option<&str>,
    ) -> Self {
        let mut list_state = ListState::default();
        if !statuses.is_empty() {
            let selected = preferred_hostname
                .and_then(|hostname| {
                    statuses
                        .iter()
                        .position(|s| s.host_info.name.eq_ignore_ascii_case(hostname))
                })
                .unwrap_or(0);
            list_state.select(Some(selected));
        }

        Self {
            repo_name,
            statuses,
            list_state,
            rx: None,
            tailscale_available: false,
            warning: None,
        }
    }

    /// Set a warning banner displayed at the top of the screen.
    pub fn set_warning(&mut self, msg: String) {
        self.warning = Some(msg);
    }

    /// Attach a channel for receiving dashboard messages.
    pub fn set_channel(&mut self, rx: mpsc::UnboundedReceiver<DashboardMessage>) {
        self.rx = Some(rx);
    }

    /// Create with a pre-built channel (for testing).
    pub fn new_with_channel(
        repo_name: String,
        statuses: Vec<HostStatus>,
        rx: mpsc::UnboundedReceiver<DashboardMessage>,
    ) -> Self {
        let mut screen = Self::new_with_statuses(repo_name, statuses);
        screen.rx = Some(rx);
        screen
    }

    pub fn hosts(&self) -> Vec<&HostInfo> {
        self.statuses.iter().map(|s| &s.host_info).collect()
    }

    pub fn statuses(&self) -> &[HostStatus] {
        &self.statuses
    }

    pub fn selected_host(&self) -> Option<&HostInfo> {
        self.list_state
            .selected()
            .and_then(|i| self.statuses.get(i))
            .map(|s| &s.host_info)
    }

    pub fn selected_status(&self) -> Option<&HostStatus> {
        self.list_state
            .selected()
            .and_then(|i| self.statuses.get(i))
    }

    /// Count of hosts that are online via Tailscale.
    pub fn online_count(&self) -> usize {
        self.statuses
            .iter()
            .filter(|s| s.tailscale.as_ref().is_some_and(|t| t.online))
            .count()
    }

    pub fn next(&mut self) {
        if self.statuses.is_empty() {
            return;
        }
        let i = match self.list_state.selected() {
            Some(i) => (i + 1) % self.statuses.len(),
            None => 0,
        };
        self.list_state.select(Some(i));
    }

    pub fn previous(&mut self) {
        if self.statuses.is_empty() {
            return;
        }
        let i = match self.list_state.selected() {
            Some(i) => {
                if i == 0 {
                    self.statuses.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.list_state.select(Some(i));
    }

    /// Poll for dashboard messages (non-blocking, mirrors BuildScreen::poll).
    pub fn poll(&mut self) {
        // Take the receiver out to avoid borrowing self mutably twice
        let mut rx = match self.rx.take() {
            Some(rx) => rx,
            None => return,
        };

        // Collect all pending messages
        let mut messages = Vec::new();
        while let Ok(msg) = rx.try_recv() {
            messages.push(msg);
        }

        // Put the receiver back
        self.rx = Some(rx);

        // Process messages
        for msg in messages {
            match msg {
                DashboardMessage::TailscaleUpdate(ts) => {
                    self.tailscale_available = true;
                    self.apply_tailscale_update(&ts);
                }
                DashboardMessage::MetricsUpdate(metrics) => {
                    self.apply_metrics_update(metrics);
                }
                DashboardMessage::TailscaleUnavailable => {
                    self.tailscale_available = false;
                }
            }
        }
    }

    fn apply_tailscale_update(&mut self, ts: &TailscaleStatus) {
        for status in &mut self.statuses {
            status.tailscale = ts
                .peers
                .values()
                .find(|p| p.hostname.eq_ignore_ascii_case(&status.host_info.name))
                .cloned();
        }
    }

    fn apply_metrics_update(&mut self, metrics: SystemMetrics) {
        // Apply metrics to the local host
        for status in &mut self.statuses {
            if status.is_local {
                status.metrics = Some(metrics.clone());
            }
        }
        // If no local host was found, apply to the first host (fallback for single-host repos)
        if !self.statuses.iter().any(|s| s.is_local) {
            if let Some(first) = self.statuses.first_mut() {
                first.metrics = Some(metrics);
            }
        }
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect) {
        let online = self.online_count();
        let total = self.statuses.len();

        let subtitle = if self.tailscale_available {
            format!("{}/{} online", online, total)
        } else if total > 0 {
            format!("{} hosts", total)
        } else {
            String::new()
        };

        let help_text = if self.statuses.is_empty() {
            "1-5: sections • a: add host • q: quit"
        } else {
            "1-5: sections • ↑/↓: navigate • Enter: details • r: refresh • q: quit"
        };

        let shell = crate::widgets::shell::render_shell(
            frame,
            area,
            &self.repo_name,
            &subtitle,
            0, // Hosts = sidebar index 0
            help_text,
            self.warning.as_deref(),
        );

        self.render_content(frame, shell.content);
    }

    fn render_content(&mut self, frame: &mut Frame, area: Rect) {
        let t = theme::default();
        if self.statuses.is_empty() {
            let empty_msg = Paragraph::new(Text::styled(
                "No hosts found\n\nPress 'a' to add",
                t.inactive_style(),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(empty_msg, area);
            return;
        }

        let panels = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(45), Constraint::Min(20)])
            .split(area);

        self.render_host_list(frame, panels[0]);
        self.render_host_info_panel(frame, panels[1]);
    }

    fn render_host_list(&mut self, frame: &mut Frame, area: Rect) {
        let t = theme::default();
        let list_width = area.width.saturating_sub(2) as usize; // account for borders

        let items: Vec<ListItem> = self
            .statuses
            .iter()
            .map(|status| {
                let name = &status.host_info.name;

                let role_badge = status
                    .host_info
                    .metadata
                    .as_ref()
                    .and_then(|m| {
                        if m.role.is_empty() {
                            None
                        } else {
                            Some(format!(" [{}]", m.role))
                        }
                    })
                    .unwrap_or_default();

                let (indicator, indicator_style) = match &status.tailscale {
                    Some(peer) if peer.online => (" ●", Style::default().fg(t.active)),
                    Some(_) => (" ○", Style::default().fg(t.error)),
                    None => ("", Style::default()),
                };

                // First line: hostname + role (left), status dot (right)
                let left_len = name.len() + role_badge.len();
                let right_len = indicator.len();
                let padding = " ".repeat(list_width.saturating_sub(left_len + right_len + 2));

                let line1 = Line::from(vec![
                    Span::styled(format!(" {}", name), Style::default()),
                    Span::styled(role_badge, Style::default().fg(t.metadata)),
                    Span::raw(padding),
                    Span::styled(indicator.to_string(), indicator_style),
                ]);

                // Second line: IP, ssh_target, or last-seen (subtle, indented)
                let subtitle = status
                    .tailscale
                    .as_ref()
                    .and_then(|p| {
                        if p.online {
                            p.tailscale_ips.first().map(|ip| ip.to_string())
                        } else if !p.last_seen.is_empty() {
                            Some(format_last_seen(&p.last_seen))
                        } else {
                            None
                        }
                    })
                    .or_else(|| {
                        let meta = status.host_info.metadata.as_ref()?;
                        if !meta.ssh_target.is_empty() {
                            Some(meta.ssh_target.clone())
                        } else if !meta.fallback_ip.is_empty() {
                            Some(meta.fallback_ip.clone())
                        } else {
                            None
                        }
                    })
                    .or_else(|| {
                        if status.is_local {
                            Some("localhost".to_string())
                        } else {
                            None
                        }
                    });

                if let Some(sub) = subtitle {
                    let line2 = Line::from(vec![Span::styled(
                        format!("   {}", sub),
                        t.inactive_style(),
                    )]);
                    ListItem::new(vec![line1, line2])
                } else {
                    ListItem::new(vec![line1])
                }
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .borders(Borders::RIGHT)
                    .border_style(t.inactive_style()),
            )
            .highlight_style(t.active_style());

        frame.render_stateful_widget(list, area, &mut self.list_state);
    }

    fn render_host_info_panel(&self, frame: &mut Frame, area: Rect) {
        let selected = match self.selected_status() {
            Some(s) => s,
            None => return,
        };

        let lines = build_host_info_lines(selected);
        let panel = Paragraph::new(lines).block(Block::default().borders(Borders::NONE));
        frame.render_widget(panel, area);
    }
}

impl Component for HostsScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match key.code {
                KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                KeyCode::Up | KeyCode::Char('k') => {
                    self.previous();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.next();
                    None
                }
                KeyCode::Enter => self
                    .selected_host()
                    .map(|host| Action::NavigateTo(Screen::HostDetail(Box::new(host.clone())))),
                KeyCode::Char('i') => {
                    let host_name = self.selected_host().map(|h| h.name.clone());
                    Some(Action::NavigateTo(Screen::Iso { host_name }))
                }
                KeyCode::Char('d') => self.selected_host().map(|h| {
                    Action::NavigateTo(Screen::Deploy {
                        host_name: h.name.clone(),
                    })
                }),
                KeyCode::Char('r') => Some(Action::RefreshDashboard),
                // Sidebar navigation
                KeyCode::Char('2') => Some(Action::NavigateTo(Screen::Services)),
                KeyCode::Char('3') => Some(Action::NavigateTo(Screen::Secrets)),
                KeyCode::Char('4') => Some(Action::NavigateTo(Screen::Security)),
                KeyCode::Char('5') => Some(Action::NavigateTo(Screen::Installer)),
                _ => None,
            });
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build the info lines for the selected host's detail sidebar.
fn build_host_info_lines(status: &HostStatus) -> Vec<Line<'_>> {
    let t = theme::default();
    let host = &status.host_info;
    let mut lines: Vec<Line> = Vec::new();

    // Architecture
    let system = host.system.as_deref().unwrap_or("unknown");
    lines.push(Line::from(vec![
        Span::styled("  Arch   ", t.inactive_style()),
        Span::styled(system, Style::default()),
    ]));
    lines.push(Line::from(""));

    // Keystone modules
    build_modules_lines(host, &mut lines);
    lines.push(Line::from(""));

    // Metadata from keystone.hosts
    build_metadata_lines(host, &mut lines);
    lines.push(Line::from(""));

    // Config files
    for (i, path) in host.config_files.iter().enumerate() {
        let label = if i == 0 { "  Config " } else { "         " };
        lines.push(Line::from(vec![
            Span::styled(label, t.inactive_style()),
            Span::styled(path.as_str(), Style::default().fg(t.path)),
        ]));
    }

    // Tailscale status
    if let Some(peer) = &status.tailscale {
        lines.push(Line::from(""));
        let (text, color) = if peer.online {
            ("online", t.active)
        } else {
            ("offline", t.error)
        };
        lines.push(Line::from(vec![
            Span::styled("  Status ", t.inactive_style()),
            Span::styled(text, Style::default().fg(color)),
        ]));
        if let Some(ip) = peer.tailscale_ips.first() {
            lines.push(Line::from(vec![
                Span::styled("  TS IP  ", t.inactive_style()),
                Span::styled(ip.as_str(), Style::default()),
            ]));
        }
    }

    lines
}

fn build_modules_lines<'a>(host: &'a HostInfo, lines: &mut Vec<Line<'a>>) {
    let t = theme::default();
    if host.keystone_modules.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("  Modules", t.inactive_style()),
            Span::styled("  (none)", t.inactive_style()),
        ]));
    } else {
        for (i, module) in host.keystone_modules.iter().enumerate() {
            let label = if i == 0 { "  Modules" } else { "         " };
            lines.push(Line::from(vec![
                Span::styled(label, t.inactive_style()),
                Span::styled(format!("  {}", module), Style::default().fg(t.active)),
            ]));
        }
    }
}

fn build_metadata_lines<'a>(host: &'a HostInfo, lines: &mut Vec<Line<'a>>) {
    let t = theme::default();
    let Some(meta) = &host.metadata else { return };

    if !meta.role.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("  Role   ", t.inactive_style()),
            Span::styled(meta.role.as_str(), Style::default().fg(t.metadata)),
        ]));
    }
    if !meta.ssh_target.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("  SSH    ", t.inactive_style()),
            Span::styled(meta.ssh_target.as_str(), Style::default()),
        ]));
    }
    if !meta.fallback_ip.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("  IP     ", t.inactive_style()),
            Span::styled(meta.fallback_ip.as_str(), Style::default()),
        ]));
    }

    let mut flags = Vec::new();
    if meta.baremetal {
        flags.push("baremetal");
    }
    if meta.zfs {
        flags.push("zfs");
    }
    if meta.build_on_remote {
        flags.push("remote-build");
    }
    if !flags.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("  Flags  ", t.inactive_style()),
            Span::styled(flags.join(", "), Style::default().fg(t.accent)),
        ]));
    }
}

fn format_last_seen(ts: &str) -> String {
    if ts.len() > 16 {
        ts[..16].to_string()
    } else {
        ts.to_string()
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::system::TailscalePeer;
    use std::collections::HashMap;

    fn sample_statuses() -> Vec<HostStatus> {
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

    // -- T14: constructor with statuses --
    #[test]
    fn test_dashboard_new_with_statuses() {
        let statuses = sample_statuses();
        let screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
        assert_eq!(screen.statuses().len(), 3);
        assert_eq!(screen.selected_status().unwrap().host_info.name, "laptop");
    }

    // -- T15: navigation returns correct status --
    #[test]
    fn test_dashboard_selected_status() {
        let statuses = sample_statuses();
        let mut screen = HostsScreen::new_with_statuses("my-infra".to_string(), statuses);
        screen.next(); // move to server
        assert_eq!(screen.selected_status().unwrap().host_info.name, "server");
    }

    // -- T17: poll tailscale via channel --
    #[test]
    fn test_dashboard_poll_tailscale() {
        let (tx, rx) = mpsc::unbounded_channel();
        // Start without any tailscale data
        let statuses = vec![HostStatus {
            host_info: HostInfo {
                name: "laptop".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            tailscale: None,
            metrics: None,
            is_local: false,
        }];
        let mut screen = HostsScreen::new_with_channel("test".to_string(), statuses, rx);

        // Send tailscale update
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
        let ts = TailscaleStatus {
            self_hostname: "laptop".to_string(),
            peers,
        };
        tx.send(DashboardMessage::TailscaleUpdate(ts)).unwrap();
        screen.poll();

        assert!(screen.statuses()[0].tailscale.is_some());
        assert!(screen.statuses()[0].tailscale.as_ref().unwrap().online);
    }

    // -- T18: online count --
    #[test]
    fn test_dashboard_online_count() {
        let statuses = sample_statuses(); // 2 online, 1 offline
        let screen = HostsScreen::new_with_statuses("test".to_string(), statuses);
        assert_eq!(screen.online_count(), 2);
    }

    // -- Existing tests (preserved) --

    #[test]
    fn test_initial_selection() {
        let hosts = vec![HostInfo {
            name: "laptop".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        }];
        let screen = HostsScreen::new("repo".to_string(), hosts);
        assert_eq!(screen.selected_host().unwrap().name, "laptop");
    }

    #[test]
    fn test_preferred_host_selection() {
        let hosts = vec![
            HostInfo {
                name: "server".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "laptop".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
        ];
        let screen =
            HostsScreen::new_with_preferred_host("repo".to_string(), hosts, Some("laptop"));
        assert_eq!(screen.selected_host().unwrap().name, "laptop");
    }

    #[test]
    fn test_missing_preferred_host_falls_back_to_first() {
        let hosts = vec![
            HostInfo {
                name: "server".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "laptop".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
        ];
        let screen = HostsScreen::new_with_preferred_host("repo".to_string(), hosts, Some("rpi"));
        assert_eq!(screen.selected_host().unwrap().name, "server");
    }

    #[test]
    fn test_next_wraps() {
        let hosts = vec![
            HostInfo {
                name: "a".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "b".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "c".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
        ];
        let mut screen = HostsScreen::new("repo".to_string(), hosts);
        screen.next(); // b
        screen.next(); // c
        screen.next(); // wraps to a
        assert_eq!(screen.selected_host().unwrap().name, "a");
    }

    #[test]
    fn test_previous_wraps() {
        let hosts = vec![
            HostInfo {
                name: "a".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
            HostInfo {
                name: "b".to_string(),
                system: None,
                keystone_modules: vec![],
                config_files: vec![],
                metadata: None,
            },
        ];
        let mut screen = HostsScreen::new("repo".to_string(), hosts);
        screen.previous(); // wraps to b
        assert_eq!(screen.selected_host().unwrap().name, "b");
    }

    #[test]
    fn test_empty_hosts() {
        let mut screen = HostsScreen::new("repo".to_string(), Vec::new());
        assert!(screen.selected_host().is_none());
        screen.next();
        screen.previous();
        assert!(screen.selected_host().is_none());
    }
}
