//! Deploy screen — discover ISO instances via mDNS and deploy with nixos-anywhere.
//!
//! Phases:
//! 1. Discovery — scan for `_keystone-iso._tcp.local` mDNS services + manual IP entry
//! 2. Confirm — show target info, confirm deployment
//! 3. Deploying — run `nixos-anywhere` streaming output
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
use crate::widgets::TextInput;

/// A discovered or manually entered deployment target.
#[derive(Debug, Clone)]
pub struct DeployTarget {
    /// Display label.
    pub label: String,
    /// SSH target (user@host or IP).
    pub ssh_target: String,
    /// Whether this was discovered via mDNS.
    pub is_mdns: bool,
}

/// Messages from async deploy operations.
pub enum DeployMessage {
    TargetsDiscovered(Vec<DeployTarget>),
    Output(String),
    Finished(bool),
}

#[derive(Debug, Clone, PartialEq)]
pub enum DeployPhase {
    Discovery,
    ManualInput,
    Confirm,
    Deploying,
    Done,
    Failed(String),
}

pub struct DeployScreen {
    phase: DeployPhase,
    repo_path: PathBuf,
    host_name: String,
    /// Discovered mDNS targets.
    targets: Vec<DeployTarget>,
    selected_target: usize,
    /// The chosen target for deployment.
    chosen_target: Option<DeployTarget>,
    /// Manual IP/hostname input.
    manual_input: TextInput,
    /// Output lines from nixos-anywhere.
    output_lines: Vec<String>,
    scroll_offset: u16,
    auto_scroll: bool,
    /// Whether mDNS scanning is still running.
    scanning: bool,
    rx: Option<mpsc::UnboundedReceiver<DeployMessage>>,
}

impl DeployScreen {
    pub fn new(repo_path: PathBuf, host_name: String) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();

        // Start mDNS discovery in background
        tokio::spawn(async move {
            Self::discover_mdns_targets(tx).await;
        });

        Self {
            phase: DeployPhase::Discovery,
            repo_path,
            host_name,
            targets: Vec::new(),
            selected_target: 0,
            chosen_target: None,
            manual_input: TextInput::new().with_placeholder("root@192.168.1.100"),
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            scanning: true,
            rx: Some(rx),
        }
    }

    /// For testing — create without spawning mDNS discovery.
    #[cfg(test)]
    pub fn new_for_test(repo_path: PathBuf, host_name: String) -> Self {
        Self {
            phase: DeployPhase::Discovery,
            repo_path,
            host_name,
            targets: Vec::new(),
            selected_target: 0,
            chosen_target: None,
            manual_input: TextInput::new().with_placeholder("root@192.168.1.100"),
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            scanning: false,
            rx: None,
        }
    }

    pub fn phase(&self) -> &DeployPhase {
        &self.phase
    }

    /// Poll for async messages.
    pub fn poll(&mut self) {
        let messages: Vec<DeployMessage> = {
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
                DeployMessage::TargetsDiscovered(discovered) => {
                    self.scanning = false;
                    self.targets = discovered;
                }
                DeployMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                DeployMessage::Finished(success) => {
                    if success {
                        self.phase = DeployPhase::Done;
                    } else {
                        self.phase =
                            DeployPhase::Failed("nixos-anywhere failed — see output above".into());
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

    /// Select the currently highlighted target and move to Confirm.
    pub fn select_target(&mut self) {
        if self.targets.is_empty() {
            return;
        }
        self.chosen_target = Some(self.targets[self.selected_target].clone());
        self.phase = DeployPhase::Confirm;
    }

    /// Switch to manual IP input mode.
    pub fn enter_manual_input(&mut self) {
        self.phase = DeployPhase::ManualInput;
        self.manual_input.set_focused(true);
    }

    /// Submit manual input and move to Confirm.
    pub fn submit_manual(&mut self) {
        let value = self.manual_input.value().trim().to_string();
        if value.is_empty() {
            return;
        }
        // Default to root@ if no user specified
        let ssh_target = if value.contains('@') {
            value.clone()
        } else {
            format!("root@{}", value)
        };
        self.chosen_target = Some(DeployTarget {
            label: format!("Manual: {}", ssh_target),
            ssh_target,
            is_mdns: false,
        });
        self.phase = DeployPhase::Confirm;
    }

    /// Confirm and start deployment.
    pub fn confirm_deploy(&mut self) {
        if self.phase != DeployPhase::Confirm {
            return;
        }
        let target = match &self.chosen_target {
            Some(t) => t.clone(),
            None => return,
        };

        self.phase = DeployPhase::Deploying;
        self.output_lines.clear();
        self.auto_scroll = true;

        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let repo = self.repo_path.clone();
        let host = self.host_name.clone();
        tokio::spawn(async move {
            Self::run_deploy(tx, repo, host, target).await;
        });
    }

    /// Go back from confirm/manual to discovery.
    pub fn go_back(&mut self) {
        match self.phase {
            DeployPhase::Confirm | DeployPhase::ManualInput => {
                self.phase = DeployPhase::Discovery;
                self.chosen_target = None;
            }
            _ => {}
        }
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

    pub fn handle_text_input(&mut self, key: crossterm::event::KeyEvent) {
        if self.phase == DeployPhase::ManualInput {
            self.manual_input.handle_key(key);
        }
    }

    // -- async operations --

    async fn discover_mdns_targets(tx: mpsc::UnboundedSender<DeployMessage>) {
        let mut targets = Vec::new();

        // Use avahi-browse to find _keystone-iso._tcp services (available on NixOS ISOs)
        if let Ok(output) = Command::new("avahi-browse")
            .args([
                "-t", // terminate after timeout
                "-r", // resolve
                "-p", // parseable output
                "_keystone-iso._tcp",
            ])
            .output()
            .await
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines() {
                    // Parseable format: =;iface;protocol;name;type;domain;hostname;address;port;txt
                    let fields: Vec<&str> = line.split(';').collect();
                    if fields.len() >= 8 && fields[0] == "=" {
                        let hostname = fields[6].trim_end_matches('.');
                        let address = fields[7];
                        if !address.is_empty() {
                            targets.push(DeployTarget {
                                label: format!("{} ({})", hostname, address),
                                ssh_target: format!("root@{}", address),
                                is_mdns: true,
                            });
                        }
                    }
                }
            }
        }

        let _ = tx.send(DeployMessage::TargetsDiscovered(targets));
    }

    async fn run_deploy(
        tx: mpsc::UnboundedSender<DeployMessage>,
        repo_path: PathBuf,
        host_name: String,
        target: DeployTarget,
    ) {
        let flake_ref = format!(".#{}", host_name);
        let _ = tx.send(DeployMessage::Output(format!(
            "$ nixos-anywhere --flake {} {}",
            flake_ref, target.ssh_target
        )));
        let _ = tx.send(DeployMessage::Output(String::new()));

        let child_result = Command::new("nixos-anywhere")
            .args(["--flake", &flake_ref, &target.ssh_target])
            .current_dir(&repo_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn();

        let mut child = match child_result {
            Ok(c) => c,
            Err(e) => {
                let _ = tx.send(DeployMessage::Output(format!(
                    "Failed to start nixos-anywhere: {e}"
                )));
                let _ = tx.send(DeployMessage::Output(
                    "Is nixos-anywhere installed? Try: nix shell github:nix-community/nixos-anywhere"
                        .to_string(),
                ));
                let _ = tx.send(DeployMessage::Finished(false));
                return;
            }
        };

        // Stream both stdout and stderr
        let stderr = child.stderr.take();
        let stdout = child.stdout.take();

        let tx_stderr = tx.clone();
        let stderr_task = tokio::spawn(async move {
            if let Some(stderr) = stderr {
                let reader = BufReader::new(stderr);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    if tx_stderr.send(DeployMessage::Output(line)).is_err() {
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
                    if tx_stdout.send(DeployMessage::Output(line)).is_err() {
                        break;
                    }
                }
            }
        });

        let status = child.wait().await;
        let _ = stderr_task.await;
        let _ = stdout_task.await;

        let success = status.is_ok_and(|s| s.success());
        let _ = tx.send(DeployMessage::Finished(success));
    }

    // -- rendering --

    pub fn render(&mut self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        match &self.phase {
            DeployPhase::Discovery => self.render_discovery(frame, area),
            DeployPhase::ManualInput => self.render_manual_input(frame, area),
            DeployPhase::Confirm => self.render_confirm(frame, area),
            DeployPhase::Deploying => self.render_output(frame, area, "Deploying...", t.accent),
            DeployPhase::Done => self.render_output(frame, area, "Deployment Complete", t.active),
            DeployPhase::Failed(msg) => {
                self.render_output(frame, area, &format!("Failed: {msg}"), t.error)
            }
        }
    }

    fn render_discovery(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title_text = format!("Deploy '{}' — Select Target", self.host_name);
        let title = Paragraph::new(Text::styled(
            title_text,
            Style::default().fg(t.path).add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        if self.scanning {
            let scanning = Paragraph::new(Text::styled(
                "  Scanning for Keystone ISO instances via mDNS...",
                t.warning_style(),
            ))
            .block(Block::default().borders(Borders::ALL));
            frame.render_widget(scanning, chunks[1]);
        } else if self.targets.is_empty() {
            let empty = Paragraph::new(Text::from(vec![
                Line::from(""),
                Line::from("  No Keystone ISO instances found on the network."),
                Line::from(""),
                Line::from(Span::styled(
                    "  Press 'm' to enter an IP address manually.",
                    t.warning_style(),
                )),
            ]))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(t.inactive_style()),
            );
            frame.render_widget(empty, chunks[1]);
        } else {
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
                    let badge = if target.is_mdns {
                        Span::styled(" (mDNS)", Style::default().fg(t.active))
                    } else {
                        Span::raw("")
                    };
                    ListItem::new(Line::from(vec![
                        Span::styled(format!("{prefix}{}", target.label), style),
                        badge,
                    ]))
                })
                .collect();

            let list = List::new(items).block(
                Block::default()
                    .title(" Targets ")
                    .borders(Borders::ALL)
                    .border_style(t.inactive_style()),
            );
            frame.render_widget(list, chunks[1]);
        }

        let help = Paragraph::new(Text::styled(
            "↑/↓: navigate • Enter: select • m: manual IP • Esc: back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_manual_input(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Length(5),
                Constraint::Min(3),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Enter Target Address",
            Style::default().fg(t.path).add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let instructions = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from("  Enter the IP address or hostname of the target machine:"),
            Line::from("  (root@ will be prepended if no user is specified)"),
        ]));
        frame.render_widget(instructions, chunks[1]);

        self.manual_input.render(frame, chunks[2], "SSH Target");

        let help = Paragraph::new(Text::styled(
            "Enter: deploy • Esc: back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    fn render_confirm(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Confirm Deployment", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let target_str = self
            .chosen_target
            .as_ref()
            .map(|ct| ct.ssh_target.as_str())
            .unwrap_or("unknown");

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("  Host:   ", t.inactive_style()),
                Span::styled(
                    &self.host_name,
                    Style::default().add_modifier(Modifier::BOLD),
                ),
            ]),
            Line::from(vec![
                Span::styled("  Target: ", t.inactive_style()),
                Span::styled(
                    target_str,
                    Style::default().fg(t.accent).add_modifier(Modifier::BOLD),
                ),
            ]),
            Line::from(""),
            Line::from(Span::styled(
                "  This will ERASE the target disk and install NixOS.",
                Style::default().fg(t.error).add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.accent)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: deploy • Esc: cancel",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
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

        let title_widget = Paragraph::new(Text::styled(
            title,
            Style::default()
                .fg(title_color)
                .add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title_widget, chunks[0]);

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

        let help_text = match &self.phase {
            DeployPhase::Done | DeployPhase::Failed(_) => "Esc: back • q: quit",
            _ => "↑/↓: scroll",
        };
        let help = Paragraph::new(Text::styled(help_text, t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

impl Component for DeployScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(self.handle_key_event(key.code, key));
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

impl DeployScreen {
    /// Handle a key press, returning an optional global Action.
    fn handle_key_event(
        &mut self,
        code: KeyCode,
        key: &crossterm::event::KeyEvent,
    ) -> Option<Action> {
        match self.phase() {
            DeployPhase::Discovery => match code {
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
                KeyCode::Char('m') => {
                    self.enter_manual_input();
                    None
                }
                KeyCode::Esc | KeyCode::Char('q') => Some(Action::GoBack),
                _ => None,
            },
            DeployPhase::ManualInput => match code {
                KeyCode::Enter => {
                    self.submit_manual();
                    None
                }
                KeyCode::Esc => {
                    self.go_back();
                    None
                }
                _ => {
                    self.handle_text_input(*key);
                    None
                }
            },
            DeployPhase::Confirm => match code {
                KeyCode::Enter => {
                    self.confirm_deploy();
                    None
                }
                KeyCode::Esc => {
                    self.go_back();
                    None
                }
                _ => None,
            },
            DeployPhase::Deploying => match code {
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
            DeployPhase::Done | DeployPhase::Failed(_) => match code {
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

    #[test]
    fn test_deploy_target_manual_input() {
        let mut screen =
            DeployScreen::new_for_test(PathBuf::from("/tmp/test"), "test-host".to_string());
        // Simulate receiving empty mDNS results
        screen.scanning = false;
        screen.targets = Vec::new();

        screen.enter_manual_input();
        assert_eq!(*screen.phase(), DeployPhase::ManualInput);
    }

    #[test]
    fn test_deploy_go_back_from_confirm() {
        let mut screen =
            DeployScreen::new_for_test(PathBuf::from("/tmp/test"), "test-host".to_string());
        screen.phase = DeployPhase::Confirm;
        screen.chosen_target = Some(DeployTarget {
            label: "test".to_string(),
            ssh_target: "root@192.168.1.1".to_string(),
            is_mdns: false,
        });

        screen.go_back();
        assert_eq!(*screen.phase(), DeployPhase::Discovery);
        assert!(screen.chosen_target.is_none());
    }

    #[test]
    fn test_deploy_target_selection() {
        let mut screen =
            DeployScreen::new_for_test(PathBuf::from("/tmp/test"), "test-host".to_string());
        screen.scanning = false;
        screen.targets = vec![
            DeployTarget {
                label: "keystone-iso (192.168.1.50)".to_string(),
                ssh_target: "root@192.168.1.50".to_string(),
                is_mdns: true,
            },
            DeployTarget {
                label: "another (192.168.1.51)".to_string(),
                ssh_target: "root@192.168.1.51".to_string(),
                is_mdns: true,
            },
        ];

        assert_eq!(screen.selected_target, 0);
        screen.target_down();
        assert_eq!(screen.selected_target, 1);
        screen.select_target();
        assert_eq!(*screen.phase(), DeployPhase::Confirm);
        assert_eq!(
            screen.chosen_target.as_ref().unwrap().ssh_target,
            "root@192.168.1.51"
        );
    }
}
