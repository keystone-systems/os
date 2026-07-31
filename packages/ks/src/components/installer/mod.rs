//! Installer component — build ISOs, detect USB targets, burn media.
//!
//! This is the sidebar "Installer" section. It orchestrates:
//! 1. Selecting a host to build an ISO for
//! 2. Choosing an install profile (desktop or server+terminal)
//! 3. Building the ISO via nix
//! 4. Detecting removable USB devices and writing the ISO
//!
//! The ISO bakes in:
//! - The user's SSH public keys (for remote access during install)
//! - The host's NixOS configuration (flake.nix + hosts/<name>/)
//! - NetworkManager for wired+wireless connectivity
//! - The ks installer which runs disko + nixos-install
//!
//! Future:
//! - WiFi setup screen during install
//! - Airgapped mode (pre-fetch all derivations)

use std::path::PathBuf;
use std::process::Stdio;

use crossterm::event::{Event, KeyCode, KeyEventKind};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::action::{Action, Screen};
use crate::component::Component;

/// Install profile — what gets included in the ISO.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallProfile {
    /// Full desktop: operating-system + desktop + terminal modules.
    Desktop,
    /// Headless: operating-system + terminal modules only.
    Server,
}

impl InstallProfile {
    fn label(&self) -> &'static str {
        match self {
            InstallProfile::Desktop => "Desktop (full Hyprland desktop)",
            InstallProfile::Server => "Server (headless + terminal)",
        }
    }
}

/// A detected USB device suitable for writing an ISO.
#[derive(Debug, Clone)]
pub struct UsbTarget {
    pub path: String,
    pub model: String,
    pub size: String,
}

/// The installer screen's internal phase.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Phase {
    Configure,
    Building,
    SelectTarget,
    Writing,
    Done,
    Failed(String),
}

/// Which section has focus on the Configure screen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ConfigFocus {
    Profile,
    UsbDevices,
}

/// Messages from async build/write operations.
enum InstallerMessage {
    BuildOutput(String),
    BuildFinished(bool),
    WriteOutput(String),
    WriteFinished(bool),
}

pub struct InstallerScreen {
    phase: Phase,
    profile: InstallProfile,
    focus: ConfigFocus,
    usb_targets: Vec<UsbTarget>,
    selected_target: usize,
    output_lines: Vec<String>,
    usb_rx: Option<mpsc::UnboundedReceiver<Vec<UsbTarget>>>,
    scanning: bool,
    /// Repo path for nix build.
    repo_path: Option<PathBuf>,
    /// Path to built ISO file.
    iso_path: Option<PathBuf>,
    /// Channel for build/write messages.
    build_rx: Option<mpsc::UnboundedReceiver<InstallerMessage>>,
}

impl Default for InstallerScreen {
    fn default() -> Self {
        Self::new()
    }
}

impl InstallerScreen {
    pub fn new() -> Self {
        let mut screen = Self {
            phase: Phase::Configure,
            profile: InstallProfile::Server,
            focus: ConfigFocus::Profile,
            usb_targets: Vec::new(),
            selected_target: 0,
            output_lines: Vec::new(),
            usb_rx: None,
            scanning: false,
            repo_path: None,
            iso_path: None,
            build_rx: None,
        };
        screen.spawn_usb_scan();
        screen
    }

    /// Set the repo path (called by App::navigate_to).
    pub fn with_repo_path(mut self, path: PathBuf) -> Self {
        self.repo_path = Some(path);
        self
    }

    /// Poll async channels — called from the event loop every tick.
    pub fn poll(&mut self) {
        self.poll_usb();
        self.poll_build();
    }

    fn toggle_profile(&mut self) {
        self.profile = match self.profile {
            InstallProfile::Desktop => InstallProfile::Server,
            InstallProfile::Server => InstallProfile::Desktop,
        };
    }

    fn spawn_usb_scan(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.usb_rx = Some(rx);
        self.scanning = true;
        tokio::spawn(async move {
            let targets = match crate::disk::discover_disks().await {
                Ok(disks) => disks
                    .into_iter()
                    .filter(|d| d.transport == "usb")
                    .map(|d| UsbTarget {
                        path: d.by_id_path,
                        model: d.model,
                        size: d.size,
                    })
                    .collect(),
                Err(_) => Vec::new(),
            };
            let _ = tx.send(targets);
        });
    }

    fn poll_usb(&mut self) {
        if let Some(ref mut rx) = self.usb_rx {
            if let Ok(targets) = rx.try_recv() {
                self.usb_targets = targets;
                self.selected_target = 0;
                self.scanning = false;
            }
        }
    }

    fn poll_build(&mut self) {
        let msgs: Vec<InstallerMessage> = if let Some(ref mut rx) = self.build_rx {
            let mut v = Vec::new();
            while let Ok(m) = rx.try_recv() {
                v.push(m);
            }
            v
        } else {
            return;
        };

        for msg in msgs {
            match msg {
                InstallerMessage::BuildOutput(line) => self.output_lines.push(line),
                InstallerMessage::BuildFinished(success) => {
                    if success {
                        self.iso_path = self.find_iso();
                        if self.iso_path.is_some() && !self.usb_targets.is_empty() {
                            self.start_write();
                        } else if let Some(ref path) = self.iso_path {
                            self.output_lines
                                .push(format!("ISO ready: {}", path.display()));
                            self.phase = Phase::Done;
                        } else {
                            self.phase = Phase::Failed("Build OK but no .iso found".to_string());
                        }
                    } else {
                        self.phase = Phase::Failed("nix build failed".to_string());
                    }
                }
                InstallerMessage::WriteOutput(line) => self.output_lines.push(line),
                InstallerMessage::WriteFinished(success) => {
                    if success {
                        self.phase = Phase::Done;
                    } else {
                        self.phase = Phase::Failed("dd write failed".to_string());
                    }
                }
            }
        }
    }

    fn start_build(&mut self) {
        let Some(repo_path) = self.repo_path.clone() else {
            self.phase = Phase::Failed("No repo path configured".to_string());
            return;
        };

        self.phase = Phase::Building;
        self.output_lines.clear();

        let (tx, rx) = mpsc::unbounded_channel();
        self.build_rx = Some(rx);

        let host_name = None; // TODO: select from hosts list
        tokio::spawn(async move {
            run_nix_build(tx, repo_path, host_name).await;
        });
    }

    fn start_write(&mut self) {
        let Some(iso_path) = self.iso_path.clone() else {
            return;
        };
        let usb = if self.usb_targets.is_empty() {
            return;
        } else {
            self.usb_targets[self.selected_target].clone()
        };

        self.phase = Phase::Writing;
        self.output_lines.clear();

        let (tx, rx) = mpsc::unbounded_channel();
        self.build_rx = Some(rx);

        tokio::spawn(async move {
            run_dd_write(tx, iso_path, usb).await;
        });
    }

    fn find_iso(&self) -> Option<PathBuf> {
        let repo = self.repo_path.as_ref()?;
        let result = repo.join("result");
        if !result.exists() {
            return None;
        }
        // result/iso/*.iso
        let iso_dir = result.join("iso");
        if iso_dir.is_dir() {
            if let Ok(entries) = std::fs::read_dir(&iso_dir) {
                for entry in entries.flatten() {
                    if entry.path().extension().is_some_and(|e| e == "iso") {
                        return Some(entry.path());
                    }
                }
            }
        }
        // result/*.iso
        if let Ok(entries) = std::fs::read_dir(&result) {
            for entry in entries.flatten() {
                if entry.path().extension().is_some_and(|e| e == "iso") {
                    return Some(entry.path());
                }
            }
        }
        None
    }
}

/// Run `nix build` for the ISO.
async fn run_nix_build(
    tx: mpsc::UnboundedSender<InstallerMessage>,
    repo_path: PathBuf,
    host_name: Option<String>,
) {
    let build_ref = match &host_name {
        Some(host) => format!(
            ".#nixosConfigurations.{}.config.keystone.os.installer.isoImage",
            host
        ),
        None => ".#iso".to_string(),
    };

    let _ = tx.send(InstallerMessage::BuildOutput(format!(
        "$ nix build {}",
        build_ref
    )));

    let child = tokio::process::Command::new("nix")
        .args(["build", &build_ref])
        .current_dir(&repo_path)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn();

    let mut child = match child {
        Ok(c) => c,
        Err(e) => {
            let _ = tx.send(InstallerMessage::BuildOutput(format!(
                "Failed to start: {}",
                e
            )));
            let _ = tx.send(InstallerMessage::BuildFinished(false));
            return;
        }
    };

    // Stream stderr (nix build output goes there)
    if let Some(stderr) = child.stderr.take() {
        let tx2 = tx.clone();
        tokio::spawn(async move {
            let mut lines = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if tx2.send(InstallerMessage::BuildOutput(line)).is_err() {
                    break;
                }
            }
        });
    }

    let status = child.wait().await;
    let _ = tx.send(InstallerMessage::BuildFinished(
        status.is_ok_and(|s| s.success()),
    ));
}

/// Check if running as root.
fn is_root() -> bool {
    std::env::var("USER").map(|u| u == "root").unwrap_or(false)
        || std::path::Path::new("/run/keystone-installer").exists()
}

/// Write ISO to USB via dd.
///
/// Uses pkexec (polkit) for privilege escalation on desktop — shows a
/// graphical auth dialog instead of blocking the TUI with a sudo prompt.
/// Falls back to plain dd if already running as root (ISO installer).
async fn run_dd_write(
    tx: mpsc::UnboundedSender<InstallerMessage>,
    iso_path: PathBuf,
    target: UsbTarget,
) {
    let _ = tx.send(InstallerMessage::WriteOutput(format!(
        "Writing {} to {}...",
        iso_path.display(),
        target.path
    )));
    let _ = tx.send(InstallerMessage::WriteOutput(
        "This may take several minutes.".to_string(),
    ));

    let running_as_root = is_root();

    let child = if running_as_root {
        // Already root (ISO installer) — dd directly
        tokio::process::Command::new("dd")
            .args([
                &format!("if={}", iso_path.display()),
                &format!("of={}", target.path),
                "bs=4M",
                "status=progress",
                "conv=fsync",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
    } else {
        // Desktop — use pkexec for polkit-based privilege escalation
        let _ = tx.send(InstallerMessage::WriteOutput(
            "Requesting authorization via polkit...".to_string(),
        ));
        tokio::process::Command::new("pkexec")
            .args([
                "dd",
                &format!("if={}", iso_path.display()),
                &format!("of={}", target.path),
                "bs=4M",
                "status=progress",
                "conv=fsync",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
    };

    let mut child = match child {
        Ok(c) => c,
        Err(e) => {
            let _ = tx.send(InstallerMessage::WriteOutput(format!(
                "Failed to start dd: {}",
                e
            )));
            let _ = tx.send(InstallerMessage::WriteFinished(false));
            return;
        }
    };

    // dd progress goes to stderr
    if let Some(stderr) = child.stderr.take() {
        let tx2 = tx.clone();
        tokio::spawn(async move {
            let mut lines = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if tx2.send(InstallerMessage::WriteOutput(line)).is_err() {
                    break;
                }
            }
        });
    }

    let status = child.wait().await;
    let _ = tx.send(InstallerMessage::WriteFinished(
        status.is_ok_and(|s| s.success()),
    ));
}

impl Component for InstallerScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        self.poll_usb();
        self.poll_build();

        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match self.phase {
                Phase::Configure => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                    KeyCode::Tab | KeyCode::BackTab => {
                        self.focus = match self.focus {
                            ConfigFocus::Profile => ConfigFocus::UsbDevices,
                            ConfigFocus::UsbDevices => ConfigFocus::Profile,
                        };
                        None
                    }
                    KeyCode::Up | KeyCode::Char('k') => {
                        match self.focus {
                            ConfigFocus::Profile => self.toggle_profile(),
                            ConfigFocus::UsbDevices => {
                                if self.selected_target > 0 {
                                    self.selected_target -= 1;
                                }
                            }
                        }
                        None
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        match self.focus {
                            ConfigFocus::Profile => self.toggle_profile(),
                            ConfigFocus::UsbDevices => {
                                if !self.usb_targets.is_empty()
                                    && self.selected_target + 1 < self.usb_targets.len()
                                {
                                    self.selected_target += 1;
                                }
                            }
                        }
                        None
                    }
                    KeyCode::Enter => {
                        self.start_build();
                        None
                    }
                    KeyCode::Char('r') => {
                        self.spawn_usb_scan();
                        None
                    }
                    // Sidebar navigation
                    KeyCode::Char('1') => Some(Action::NavigateTo(Screen::Hosts)),
                    KeyCode::Char('2') => Some(Action::NavigateTo(Screen::Services)),
                    KeyCode::Char('3') => Some(Action::NavigateTo(Screen::Secrets)),
                    KeyCode::Char('4') => Some(Action::NavigateTo(Screen::Security)),
                    _ => None,
                },
                Phase::Building | Phase::Writing => match key.code {
                    KeyCode::Char('q') => Some(Action::Quit),
                    _ => None,
                },
                Phase::SelectTarget => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                    KeyCode::Up | KeyCode::Char('k') => {
                        if self.selected_target > 0 {
                            self.selected_target -= 1;
                        }
                        None
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        if self.selected_target + 1 < self.usb_targets.len() {
                            self.selected_target += 1;
                        }
                        None
                    }
                    _ => None,
                },
                Phase::Done | Phase::Failed(_) => match key.code {
                    KeyCode::Char('q') => Some(Action::Quit),
                    KeyCode::Esc => Some(Action::GoBack),
                    _ => None,
                },
            });
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        let help = match self.phase {
            Phase::Configure => {
                "Tab: switch section • ↑/↓: select • r: rescan USB • Enter: build • q: quit"
            }
            Phase::Building | Phase::Writing => "building...",
            Phase::SelectTarget => "↑/↓: select • Enter: write ISO • r: refresh • Esc: back",
            Phase::Done | Phase::Failed(_) => "Esc: back • q: quit",
        };

        let shell =
            crate::widgets::shell::render_shell(frame, area, "Installer", "", 4, help, None);

        let content = shell.content;
        match &self.phase {
            Phase::Configure => self.render_configure(frame, content, content),
            Phase::Building | Phase::Writing => self.render_building(frame, content),
            Phase::SelectTarget => {
                let panels = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([Constraint::Percentage(50), Constraint::Min(20)])
                    .split(content);
                self.render_select_target(frame, panels[0], panels[1]);
            }
            Phase::Done => self.render_done(frame, content),
            Phase::Failed(msg) => self.render_failed(frame, content, msg.clone()),
        }

        Ok(())
    }
}

impl InstallerScreen {
    fn render_configure(&self, frame: &mut Frame, area: Rect, _unused: Rect) {
        let t = crate::theme::default();

        let usb_height = if self.usb_targets.is_empty() {
            3
        } else {
            (self.usb_targets.len() as u16 * 2 + 2).min(10)
        };

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(5),          // Description
                Constraint::Length(1),          // Spacer
                Constraint::Length(4),          // Profile select
                Constraint::Length(1),          // Spacer
                Constraint::Length(5),          // Options
                Constraint::Length(1),          // Spacer
                Constraint::Length(usb_height), // USB targets
                Constraint::Min(0),             // Spacer
            ])
            .split(area);

        // Description text at top
        let desc = Paragraph::new(vec![
            Line::from(Span::styled(
                " Build a bootable ISO with your NixOS config, SSH keys, and installer.",
                Style::default(),
            )),
            Line::from(Span::styled(
                " Boot from USB → TUI runs disko → nixos-install → reboot → first-boot setup.",
                t.inactive_style(),
            )),
        ]);
        frame.render_widget(desc, chunks[0]);

        // Profile selection
        let desktop_style = if self.profile == InstallProfile::Desktop {
            t.active_style()
        } else {
            t.inactive_style()
        };
        let server_style = if self.profile == InstallProfile::Server {
            t.active_style()
        } else {
            t.inactive_style()
        };

        let profile_border = if self.focus == ConfigFocus::Profile {
            Style::default().fg(t.accent)
        } else {
            t.inactive_style()
        };
        let profile_widget = Paragraph::new(vec![
            Line::from(Span::styled(
                format!("  {}", InstallProfile::Desktop.label()),
                desktop_style,
            )),
            Line::from(Span::styled(
                format!("  {}", InstallProfile::Server.label()),
                server_style,
            )),
        ])
        .block(
            Block::default()
                .title(" Install Profile (↑/↓ to switch) ")
                .borders(Borders::ALL)
                .border_style(profile_border),
        );
        frame.render_widget(profile_widget, chunks[2]);

        // Options summary
        let options = Paragraph::new(vec![
            Line::from(vec![
                Span::styled("  SSH keys   ", t.inactive_style()),
                Span::styled("from ~/.ssh/ + GitHub", Style::default()),
            ]),
            Line::from(vec![
                Span::styled("  Network    ", t.inactive_style()),
                Span::styled("NetworkManager (wired + WiFi)", Style::default()),
            ]),
            Line::from(vec![
                Span::styled("  Airgapped  ", t.inactive_style()),
                Span::styled("not yet supported", t.inactive_style()),
            ]),
        ])
        .block(
            Block::default()
                .title(" Options ")
                .borders(Borders::ALL)
                .border_style(t.inactive_style()),
        );
        frame.render_widget(options, chunks[4]);

        // USB targets
        let usb_focused = self.focus == ConfigFocus::UsbDevices;
        let usb_border = if usb_focused {
            Style::default().fg(t.accent)
        } else {
            t.inactive_style()
        };

        let usb_widget = if self.scanning {
            Paragraph::new(Line::from(Span::styled(
                "  Scanning for USB devices...",
                t.inactive_style(),
            )))
            .block(
                Block::default()
                    .title(" USB Devices ")
                    .borders(Borders::ALL)
                    .border_style(usb_border),
            )
        } else if self.usb_targets.is_empty() {
            Paragraph::new(Line::from(Span::styled(
                "  No USB devices detected (r to rescan)",
                t.inactive_style(),
            )))
            .block(
                Block::default()
                    .title(" USB Devices ")
                    .borders(Borders::ALL)
                    .border_style(usb_border),
            )
        } else {
            let lines: Vec<Line> = self
                .usb_targets
                .iter()
                .enumerate()
                .flat_map(|(i, usb)| {
                    let selected = usb_focused && i == self.selected_target;
                    let name_style = if selected {
                        t.active_style()
                    } else {
                        Style::default()
                    };
                    vec![
                        Line::from(Span::styled(
                            format!("  {} ({})", usb.model, usb.size),
                            name_style,
                        )),
                        Line::from(Span::styled(
                            format!("    {}", usb.path),
                            t.inactive_style(),
                        )),
                    ]
                })
                .collect();
            Paragraph::new(lines).block(
                Block::default()
                    .title(format!(" USB Devices ({}) ", self.usb_targets.len()))
                    .borders(Borders::ALL)
                    .border_style(if usb_focused {
                        Style::default().fg(t.accent)
                    } else {
                        Style::default().fg(t.active)
                    }),
            )
        };
        frame.render_widget(usb_widget, chunks[6]);
    }

    fn render_building(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(1), Constraint::Min(5)])
            .split(area);

        let label = match self.phase {
            Phase::Writing => "Writing ISO to USB...",
            _ => "Building ISO...",
        };
        let title =
            Paragraph::new(Text::styled(label, t.title_style())).alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Show last N lines of output (auto-scroll to bottom)
        let visible_height = chunks[1].height.saturating_sub(2) as usize;
        let skip = self.output_lines.len().saturating_sub(visible_height);
        let output: Vec<Line> = self.output_lines[skip..]
            .iter()
            .map(|l| Line::from(l.as_str()))
            .collect();
        let log = Paragraph::new(output)
            .block(Block::default().borders(Borders::ALL))
            .wrap(Wrap { trim: false });
        frame.render_widget(log, chunks[1]);
    }

    fn render_select_target(&self, frame: &mut Frame, main: Rect, info: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(2),
            ])
            .split(main);

        let title = Paragraph::new(Text::styled("Select USB Target", t.title_style()))
            .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        if self.usb_targets.is_empty() {
            let msg = Paragraph::new(Text::styled(
                "No removable USB devices detected.\n\nInsert a USB drive and press 'r' to refresh.",
                t.inactive_style(),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(msg, chunks[1]);
        } else {
            let items: Vec<ListItem> = self
                .usb_targets
                .iter()
                .enumerate()
                .map(|(i, target)| {
                    let style = if i == self.selected_target {
                        t.active_style()
                    } else {
                        Style::default()
                    };
                    ListItem::new(vec![
                        Line::from(Span::styled(format!(" {}", target.model), style)),
                        Line::from(Span::styled(
                            format!("   {} — {}", target.path, target.size),
                            t.inactive_style(),
                        )),
                    ])
                })
                .collect();

            let list = List::new(items).block(
                Block::default()
                    .title(" USB Devices ")
                    .borders(Borders::ALL),
            );
            frame.render_widget(list, chunks[1]);
        }

        let help = Paragraph::new(Text::styled(
            "↑/↓: select • Enter: write ISO • r: refresh • Esc: back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);

        // Info panel
        let warning = Paragraph::new(vec![
            Line::from(Span::styled(
                " WARNING",
                t.error_style().add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
            Line::from(Span::styled(
                " Writing the ISO will ERASE all data",
                t.error_style(),
            )),
            Line::from(Span::styled(
                " on the selected USB device.",
                t.error_style(),
            )),
        ]);
        frame.render_widget(warning, info);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let msg = Paragraph::new(Text::styled(
            "ISO written successfully!\n\nRemove the USB drive and boot the target machine from it.",
            Style::default().fg(t.active),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(msg, area);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, msg: String) {
        let t = crate::theme::default();
        let text = Paragraph::new(Text::styled(format!("Failed: {}", msg), t.error_style()))
            .alignment(Alignment::Center);
        frame.render_widget(text, area);
    }
}
