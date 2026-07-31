//! ISO screen — select destination, build installer ISO, then write.
//!
//! Phases:
//! 1. SelectTarget — choose USB device or ~/Downloads
//! 2. Building — runs `nix build .#iso` in the active repo
//! 3. Writing — `dd` to USB or `cp` to ~/Downloads
//! 4. Done / Failed

use std::path::PathBuf;
use std::process::Stdio;

use crossterm::event::{Event, KeyCode, KeyEventKind};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::action::Action;
use crate::component::Component;

/// A removable block device or the ~/Downloads save option.
#[derive(Debug, Clone)]
pub struct IsoTarget {
    pub label: String,
    pub path: String,
    pub is_usb: bool,
    pub size: String,
}

/// Messages from async operations back to the UI.
pub enum IsoMessage {
    BuildOutput(String),
    BuildFinished(bool),
    TargetsDiscovered(Vec<IsoTarget>),
    WriteOutput(String),
    WriteFinished(bool),
}

#[derive(Debug, Clone, PartialEq)]
pub enum IsoPhase {
    SelectTarget,
    Building,
    Writing,
    Done,
    Failed(String),
}

pub struct IsoScreen {
    phase: IsoPhase,
    repo_path: PathBuf,
    /// Host name to build the ISO for (used in flake ref).
    host_name: Option<String>,
    /// Lines of build/write output.
    output_lines: Vec<String>,
    scroll_offset: u16,
    auto_scroll: bool,
    /// Path to the built .iso file (set after build succeeds).
    iso_path: Option<PathBuf>,
    /// Available write targets.
    targets: Vec<IsoTarget>,
    selected_target: usize,
    /// The target chosen by the user (set when they press Enter on SelectTarget).
    chosen_target: Option<IsoTarget>,
    /// Async message channel.
    rx: Option<mpsc::UnboundedReceiver<IsoMessage>>,
}

impl IsoScreen {
    pub fn new(repo_path: PathBuf) -> Self {
        Self::new_for_host(repo_path, None)
    }

    /// Create an ISO screen targeting a specific host configuration.
    pub fn new_for_host(repo_path: PathBuf, host_name: Option<String>) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();

        // Discover USB devices and ~/Downloads immediately
        tokio::spawn(async move {
            Self::discover_targets(tx).await;
        });

        Self {
            phase: IsoPhase::SelectTarget,
            repo_path,
            host_name,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            iso_path: None,
            targets: Vec::new(),
            selected_target: 0,
            chosen_target: None,
            rx: Some(rx),
        }
    }

    /// For testing — inject a channel instead of spawning discovery.
    #[cfg(test)]
    pub fn new_with_channel(repo_path: PathBuf, rx: mpsc::UnboundedReceiver<IsoMessage>) -> Self {
        Self {
            phase: IsoPhase::SelectTarget,
            repo_path,
            host_name: None,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            iso_path: None,
            targets: Vec::new(),
            selected_target: 0,
            chosen_target: None,
            rx: Some(rx),
        }
    }

    pub fn phase(&self) -> &IsoPhase {
        &self.phase
    }

    pub fn targets(&self) -> &[IsoTarget] {
        &self.targets
    }

    pub fn selected_target(&self) -> usize {
        self.selected_target
    }

    pub fn iso_path(&self) -> Option<&PathBuf> {
        self.iso_path.as_ref()
    }

    /// Poll for async messages (non-blocking).
    pub fn poll(&mut self) {
        let messages: Vec<IsoMessage> = {
            if let Some(ref mut rx) = self.rx {
                let mut msgs = Vec::new();
                while let Ok(msg) = rx.try_recv() {
                    msgs.push(msg);
                }
                msgs
            } else {
                Vec::new()
            }
        };

        for msg in messages {
            match msg {
                IsoMessage::TargetsDiscovered(targets) => {
                    self.targets = targets;
                }
                IsoMessage::BuildOutput(line) => {
                    self.output_lines.push(line);
                }
                IsoMessage::BuildFinished(success) => {
                    if success {
                        self.iso_path = Self::find_iso_file(&self.repo_path);
                        if let Some(ref iso_path) = self.iso_path {
                            // Start writing to the previously chosen target
                            if let Some(target) = self.chosen_target.take() {
                                self.phase = IsoPhase::Writing;
                                self.output_lines.clear();
                                self.auto_scroll = true;

                                let (tx, rx) = mpsc::unbounded_channel();
                                self.rx = Some(rx);
                                let iso = iso_path.clone();
                                tokio::spawn(async move {
                                    Self::run_write(tx, iso, target).await;
                                });
                            } else {
                                self.phase = IsoPhase::Done;
                            }
                        } else {
                            let result_path = self.repo_path.join("result");
                            let contents = if result_path.exists() {
                                std::fs::read_dir(&result_path)
                                    .map(|entries| {
                                        entries
                                            .flatten()
                                            .map(|e| e.file_name().to_string_lossy().to_string())
                                            .collect::<Vec<_>>()
                                            .join(", ")
                                    })
                                    .unwrap_or_else(|e| format!("(unreadable: {e})"))
                            } else {
                                "(no result symlink)".to_string()
                            };
                            self.phase = IsoPhase::Failed(format!(
                                "Build succeeded but no .iso found. result contains: {contents}"
                            ));
                        }
                    } else {
                        self.phase = IsoPhase::Failed("ISO build failed".to_string());
                    }
                }
                IsoMessage::WriteOutput(line) => {
                    self.output_lines.push(line);
                }
                IsoMessage::WriteFinished(success) => {
                    if success {
                        self.phase = IsoPhase::Done;
                    } else {
                        self.phase = IsoPhase::Failed("Write failed".to_string());
                    }
                }
            }
        }
    }

    pub fn target_up(&mut self) {
        if !self.targets.is_empty() && self.selected_target > 0 {
            self.selected_target -= 1;
        }
    }

    pub fn target_down(&mut self) {
        if !self.targets.is_empty() && self.selected_target < self.targets.len() - 1 {
            self.selected_target += 1;
        }
    }

    /// User confirmed a target — save it and start the ISO build.
    pub fn select_target(&mut self) {
        if self.targets.is_empty() || self.phase != IsoPhase::SelectTarget {
            return;
        }

        self.chosen_target = Some(self.targets[self.selected_target].clone());
        self.phase = IsoPhase::Building;
        self.output_lines.clear();
        self.auto_scroll = true;

        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let repo = self.repo_path.clone();
        let host = self.host_name.clone();
        tokio::spawn(async move {
            Self::run_build(tx, repo, host).await;
        });
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

    // -- async operations --

    async fn discover_targets(tx: mpsc::UnboundedSender<IsoMessage>) {
        let mut targets = Vec::new();

        // Always offer ~/Downloads
        let downloads = home::home_dir().unwrap_or_default().join("Downloads");
        targets.push(IsoTarget {
            label: format!("Save to {}", downloads.display()),
            path: downloads.to_string_lossy().to_string(),
            is_usb: false,
            size: String::new(),
        });

        // Discover removable USB devices via lsblk
        if let Ok(output) = tokio::process::Command::new("lsblk")
            .args(["--json", "-d", "-o", "NAME,SIZE,MODEL,TRAN,TYPE,RM"])
            .output()
            .await
        {
            if let Ok(text) = String::from_utf8(output.stdout) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(devices) = json["blockdevices"].as_array() {
                        for dev in devices {
                            let rm = parse_rm(&dev["rm"]);
                            let dev_type = dev["type"].as_str().unwrap_or("");
                            let tran = dev["tran"].as_str().unwrap_or("");
                            let name = dev["name"].as_str().unwrap_or("");

                            // Only removable disks (USB sticks, etc.)
                            if !rm || dev_type != "disk" || name.is_empty() {
                                continue;
                            }

                            let model = dev["model"]
                                .as_str()
                                .unwrap_or("Unknown")
                                .trim()
                                .to_string();
                            let size = dev["size"].as_str().unwrap_or("?").to_string();

                            targets.push(IsoTarget {
                                label: format!("/dev/{name} — {model} ({size}, {tran})"),
                                path: format!("/dev/{name}"),
                                is_usb: true,
                                size,
                            });
                        }
                    }
                }
            }
        }

        let _ = tx.send(IsoMessage::TargetsDiscovered(targets));
    }

    async fn run_build(
        tx: mpsc::UnboundedSender<IsoMessage>,
        repo_path: PathBuf,
        host_name: Option<String>,
    ) {
        // Build host-specific ISO if a host is selected, otherwise generic .#iso
        let build_ref = match &host_name {
            Some(host) => format!(
                ".#nixosConfigurations.{}.config.system.build.isoImage",
                host
            ),
            None => ".#iso".to_string(),
        };

        let _ = tx.send(IsoMessage::BuildOutput(format!(
            "$ nix build {}",
            build_ref
        )));
        let _ = tx.send(IsoMessage::BuildOutput(String::new()));

        let child_result = Command::new("nix")
            .args(["build", &build_ref])
            .current_dir(&repo_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn();

        let mut child = match child_result {
            Ok(c) => c,
            Err(e) => {
                let _ = tx.send(IsoMessage::BuildOutput(format!(
                    "Failed to start nix build: {e}"
                )));
                let _ = tx.send(IsoMessage::BuildFinished(false));
                return;
            }
        };

        // Stream stderr (nix build output goes to stderr)
        let stderr = child.stderr.take();
        let stdout = child.stdout.take();

        let tx_stderr = tx.clone();
        let stderr_task = tokio::spawn(async move {
            if let Some(stderr) = stderr {
                let reader = BufReader::new(stderr);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    if tx_stderr.send(IsoMessage::BuildOutput(line)).is_err() {
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
                    if tx_stdout.send(IsoMessage::BuildOutput(line)).is_err() {
                        break;
                    }
                }
            }
        });

        let status = child.wait().await;
        let _ = stderr_task.await;
        let _ = stdout_task.await;

        let success = status.is_ok_and(|s| s.success());
        let _ = tx.send(IsoMessage::BuildFinished(success));
    }

    fn find_iso_file(repo_path: &std::path::Path) -> Option<PathBuf> {
        // nix build .#iso creates a `result` symlink pointing to a nix store
        // derivation directory containing iso/<name>.iso
        let result = repo_path.join("result");
        if !result.exists() {
            return None;
        }

        // Primary path: result/iso/*.iso (standard NixOS isoImage output)
        let iso_dir = result.join("iso");
        if iso_dir.is_dir() {
            if let Ok(entries) = std::fs::read_dir(&iso_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().is_some_and(|e| e == "iso") {
                        return Some(path);
                    }
                }
            }
        }

        // Fallback: .iso file directly in result/
        if result.is_dir() {
            if let Ok(entries) = std::fs::read_dir(&result) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() && path.extension().is_some_and(|e| e == "iso") {
                        return Some(path);
                    }
                }
            }
        }

        // Maybe the result symlink points directly to an .iso file
        if result.is_file() && result.extension().is_some_and(|e| e == "iso") {
            return Some(result);
        }

        None
    }

    async fn run_write(
        tx: mpsc::UnboundedSender<IsoMessage>,
        iso_path: PathBuf,
        target: IsoTarget,
    ) {
        let iso_display = iso_path.display().to_string();

        if target.is_usb {
            // Write to USB with dd
            let _ = tx.send(IsoMessage::WriteOutput(format!(
                "Writing {} to {}...",
                iso_display, target.path
            )));
            let _ = tx.send(IsoMessage::WriteOutput(
                "This may take several minutes.".to_string(),
            ));
            let _ = tx.send(IsoMessage::WriteOutput(String::new()));

            let child_result = Command::new("sudo")
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
                .spawn();

            let mut child = match child_result {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(IsoMessage::WriteOutput(format!("Failed to start dd: {e}")));
                    let _ = tx.send(IsoMessage::WriteFinished(false));
                    return;
                }
            };

            // dd writes progress to stderr
            let stderr = child.stderr.take();
            let tx_stderr = tx.clone();
            let stderr_task = tokio::spawn(async move {
                if let Some(stderr) = stderr {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        if tx_stderr.send(IsoMessage::WriteOutput(line)).is_err() {
                            break;
                        }
                    }
                }
            });

            let status = child.wait().await;
            let _ = stderr_task.await;

            let success = status.is_ok_and(|s| s.success());
            if success {
                let _ = tx.send(IsoMessage::WriteOutput(String::new()));
                let _ = tx.send(IsoMessage::WriteOutput(format!(
                    "ISO written to {}",
                    target.path
                )));
            }
            let _ = tx.send(IsoMessage::WriteFinished(success));
        } else {
            // Copy to ~/Downloads as keystone-installer.iso
            let dest_dir = PathBuf::from(&target.path);
            if let Err(e) = std::fs::create_dir_all(&dest_dir) {
                let _ = tx.send(IsoMessage::WriteOutput(format!(
                    "Failed to create {}: {e}",
                    dest_dir.display()
                )));
                let _ = tx.send(IsoMessage::WriteFinished(false));
                return;
            }

            let dest = dest_dir.join("keystone-installer.iso");

            // Remove existing read-only file (nix store copies inherit 444 perms)
            if dest.exists() {
                if let Err(e) = std::fs::remove_file(&dest) {
                    let _ = tx.send(IsoMessage::WriteOutput(format!(
                        "Failed to remove existing {}: {e}",
                        dest.display()
                    )));
                    let _ = tx.send(IsoMessage::WriteFinished(false));
                    return;
                }
            }

            let _ = tx.send(IsoMessage::WriteOutput(format!(
                "Copying to {}...",
                dest.display()
            )));

            match std::fs::copy(&iso_path, &dest) {
                Ok(bytes) => {
                    let mb = bytes / (1024 * 1024);
                    let _ = tx.send(IsoMessage::WriteOutput(format!(
                        "Copied {mb} MiB to {}",
                        dest.display()
                    )));
                    let _ = tx.send(IsoMessage::WriteFinished(true));
                }
                Err(e) => {
                    let _ = tx.send(IsoMessage::WriteOutput(format!("Copy failed: {e}")));
                    let _ = tx.send(IsoMessage::WriteFinished(false));
                }
            }
        }
    }

    // -- rendering --

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        match &self.phase {
            IsoPhase::SelectTarget => self.render_select_target(frame, area),
            IsoPhase::Building => self.render_output(frame, area, "Building ISO...", t.accent),
            IsoPhase::Writing => self.render_output(frame, area, "Writing ISO...", t.accent),
            IsoPhase::Done => self.render_output(frame, area, "ISO Complete", t.active),
            IsoPhase::Failed(msg) => {
                self.render_output(frame, area, &format!("Failed: {msg}"), t.error)
            }
        }
    }

    fn render_output(&self, frame: &mut Frame, area: Rect, title: &str, title_color: Color) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        // Title
        let title_widget = Paragraph::new(Text::styled(
            title,
            Style::default()
                .fg(title_color)
                .add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title_widget, chunks[0]);

        // Output area
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

        // Help text
        let help_text = match &self.phase {
            IsoPhase::Done | IsoPhase::Failed(_) => "Esc: back • q: quit",
            _ => "Esc: cancel",
        };
        let help = Paragraph::new(Text::styled(help_text, t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_select_target(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            "Build ISO — Select Destination",
            Style::default().fg(t.path).add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Target list
        let items: Vec<ListItem> = self
            .targets
            .iter()
            .enumerate()
            .map(|(i, target)| {
                let style = if i == self.selected_target {
                    Style::default().fg(t.accent).add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                };

                let prefix = if i == self.selected_target {
                    "▸ "
                } else {
                    "  "
                };

                let warning = if target.is_usb {
                    Span::styled(" (ALL DATA WILL BE ERASED)", Style::default().fg(t.error))
                } else {
                    Span::raw("")
                };

                ListItem::new(Line::from(vec![
                    Span::styled(format!("{prefix}{}", target.label), style),
                    warning,
                ]))
            })
            .collect();

        let list = List::new(items).block(
            Block::default()
                .title(" Destination ")
                .borders(Borders::ALL)
                .border_style(t.inactive_style()),
        );
        frame.render_widget(list, chunks[1]);

        // Help
        let help_text = if self.targets.is_empty() {
            "Discovering devices..."
        } else {
            "↑/↓: navigate • Enter: build & write • Esc: cancel"
        };
        let help = Paragraph::new(Text::styled(help_text, t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

/// Interpret the `"rm"` field from `lsblk --json` output as a boolean.
///
/// `lsblk` may encode the removable flag as a JSON bool, integer (0/1), or
/// string ("0"/"1"/"true"/"false") depending on the kernel and util-linux
/// version.  Try each representation in turn so USB sticks are detected on all
/// supported platforms.
pub(crate) fn parse_rm(value: &serde_json::Value) -> bool {
    value.as_bool().unwrap_or(false)
        || value.as_u64().map(|v| v != 0).unwrap_or(false)
        || value.as_i64().map(|v| v != 0).unwrap_or(false)
        || value
            .as_str()
            .map(|v| v == "1" || v == "true")
            .unwrap_or(false)
}

impl Component for IsoScreen {
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

impl IsoScreen {
    /// Handle a key press, returning an optional global Action.
    fn handle_key_event(&mut self, code: KeyCode) -> Option<Action> {
        match self.phase() {
            IsoPhase::Building => match code {
                KeyCode::Esc | KeyCode::Char('q') => Some(Action::GoBack),
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
            IsoPhase::SelectTarget => match code {
                KeyCode::Up | KeyCode::Char('k') => {
                    self.target_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.target_down();
                    None
                }
                KeyCode::Enter => {
                    self.select_target();
                    None
                }
                KeyCode::Esc | KeyCode::Char('q') => Some(Action::GoBack),
                _ => None,
            },
            IsoPhase::Writing => match code {
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
            IsoPhase::Done | IsoPhase::Failed(_) => match code {
                KeyCode::Esc => Some(Action::GoBack),
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_repo_path() -> PathBuf {
        PathBuf::from("/tmp/test-repo")
    }

    #[test]
    fn test_initial_phase_is_select_target() {
        let (_, rx) = mpsc::unbounded_channel();
        let screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        assert_eq!(*screen.phase(), IsoPhase::SelectTarget);
    }

    #[test]
    fn test_poll_collects_build_output() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        screen.phase = IsoPhase::Building;

        tx.send(IsoMessage::BuildOutput("line 1".to_string()))
            .unwrap();
        tx.send(IsoMessage::BuildOutput("line 2".to_string()))
            .unwrap();

        screen.poll();
        assert_eq!(screen.output_lines.len(), 2);
        assert_eq!(screen.output_lines[0], "line 1");
    }

    #[test]
    fn test_build_failure_goes_to_failed() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        screen.phase = IsoPhase::Building;

        tx.send(IsoMessage::BuildFinished(false)).unwrap();
        screen.poll();

        assert!(matches!(screen.phase(), IsoPhase::Failed(_)));
    }

    #[test]
    fn test_target_navigation() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);

        tx.send(IsoMessage::TargetsDiscovered(vec![
            IsoTarget {
                label: "~/Downloads".to_string(),
                path: "/home/user/Downloads".to_string(),
                is_usb: false,
                size: String::new(),
            },
            IsoTarget {
                label: "/dev/sda".to_string(),
                path: "/dev/sda".to_string(),
                is_usb: true,
                size: "32G".to_string(),
            },
        ]))
        .unwrap();
        screen.poll();

        assert_eq!(screen.selected_target(), 0);
        screen.target_down();
        assert_eq!(screen.selected_target(), 1);
        screen.target_down(); // at end, no-op
        assert_eq!(screen.selected_target(), 1);
        screen.target_up();
        assert_eq!(screen.selected_target(), 0);
    }

    #[test]
    fn test_target_up_at_zero_is_noop() {
        let (_, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        screen.target_up();
        assert_eq!(screen.selected_target(), 0);
    }

    #[test]
    fn test_scroll_disables_auto_scroll() {
        let (_, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        screen.phase = IsoPhase::Building;
        assert!(screen.auto_scroll);
        screen.scroll_up();
        assert!(!screen.auto_scroll);
        screen.scroll_down();
        assert!(screen.auto_scroll);
    }

    #[test]
    fn test_find_iso_file_in_result_iso_dir() {
        let tmp = std::env::temp_dir().join("ks-test-iso");
        let iso_dir = tmp.join("result").join("iso");
        std::fs::create_dir_all(&iso_dir).unwrap();
        let iso_file = iso_dir.join("nixos-minimal-26.05pre-git-x86_64-linux.iso");
        std::fs::write(&iso_file, b"fake iso").unwrap();

        let found = IsoScreen::find_iso_file(&tmp);
        assert!(found.is_some(), "should find .iso in result/iso/");
        assert_eq!(found.unwrap(), iso_file);

        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn test_find_iso_file_returns_none_without_result() {
        let tmp = std::env::temp_dir().join("ks-test-no-result");
        let _ = std::fs::remove_dir_all(&tmp);
        let found = IsoScreen::find_iso_file(&tmp);
        assert!(found.is_none());
    }

    #[test]
    fn test_parse_rm_bool_true() {
        assert!(parse_rm(&serde_json::Value::Bool(true)));
    }

    #[test]
    fn test_parse_rm_bool_false() {
        assert!(!parse_rm(&serde_json::Value::Bool(false)));
    }

    #[test]
    fn test_parse_rm_integer_one() {
        assert!(parse_rm(&serde_json::json!(1)));
    }

    #[test]
    fn test_parse_rm_integer_zero() {
        assert!(!parse_rm(&serde_json::json!(0)));
    }

    #[test]
    fn test_parse_rm_string_one() {
        assert!(parse_rm(&serde_json::Value::String("1".to_string())));
    }

    #[test]
    fn test_parse_rm_string_true() {
        assert!(parse_rm(&serde_json::Value::String("true".to_string())));
    }

    #[test]
    fn test_parse_rm_string_zero() {
        assert!(!parse_rm(&serde_json::Value::String("0".to_string())));
    }

    #[test]
    fn test_parse_rm_null() {
        assert!(!parse_rm(&serde_json::Value::Null));
    }
}
