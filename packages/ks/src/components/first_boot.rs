//! First-boot screen — post-install onboarding wizard.
//!
//! After a fresh Keystone install, on first boot the TUI detects a
//! `.first-boot-pending` marker in the installed system flake directory and
//! walks the user through:
//!
//! 1. Secure Boot enrollment
//! 2. TPM enrollment
//! 3. SSH key setup and push configuration
//! 4. Secrets setup

use std::path::PathBuf;

use crossterm::event::{Event, KeyCode, KeyEventKind};
use tokio::process::Command;
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame,
};

use crate::action::Action;
use crate::component::Component;
use crate::widgets::TextInput;

const REMOTE_MAIN_REF: &str = "origin/main";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct RepoHealthStatus {
    working_tree_changes: usize,
    ahead_count: usize,
}

impl RepoHealthStatus {
    fn needs_warning(&self) -> bool {
        self.working_tree_changes > 0 || self.ahead_count > 0
    }
}

/// Configuration for the first-boot flow.
#[derive(Debug, Clone)]
pub struct FirstBootConfig {
    pub config_dir: PathBuf,
    pub hostname: String,
    pub username: String,
    pub github_username: Option<String>,
}

impl FirstBootConfig {
    fn default_repo_owner() -> String {
        std::fs::read_to_string("/etc/keystone/install-config/username")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .or_else(|| std::env::var("USER").ok())
            .unwrap_or_else(|| "keystone".to_string())
    }

    fn installed_config_dir() -> Option<PathBuf> {
        // 1. Authoritative pointer file (written at NixOS activation time).
        if let Ok(content) = std::fs::read_to_string("/run/current-system/keystone-system-flake") {
            let path = content.trim();
            if !path.is_empty() {
                return Some(PathBuf::from(path));
            }
        }

        // 2. Fallback: derive from the install-config username.
        let default_owner = Self::default_repo_owner();
        let home = home::home_dir()?;
        Some(
            home.join("repos")
                .join(&default_owner)
                .join("keystone-config"),
        )
    }

    /// Detect first-boot mode by looking for the marker file.
    pub fn detect() -> Option<Self> {
        let config_dir = Self::installed_config_dir()?;
        let marker = config_dir.join(".first-boot-pending");

        if !marker.exists() {
            return None;
        }

        let hostname = std::fs::read_to_string("/etc/hostname")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "keystone".to_string());

        let username = std::fs::read_to_string("/etc/keystone/install-config/username")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| std::env::var("USER").unwrap_or_else(|_| "user".to_string()));

        let github_username =
            std::fs::read_to_string("/etc/keystone/install-config/github_username")
                .ok()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());

        Some(Self {
            config_dir,
            hostname,
            username,
            github_username,
        })
    }
}

fn count_nonempty_lines(text: &str) -> usize {
    text.lines().filter(|line| !line.trim().is_empty()).count()
}

fn parse_rev_list_counts(output: &str) -> Result<(usize, usize), String> {
    let mut fields = output.split_whitespace();
    let behind = fields
        .next()
        .ok_or_else(|| format!("Unexpected git rev-list output: {}", output.trim()))?
        .parse::<usize>()
        .map_err(|e| format!("Failed to parse behind count from git rev-list: {}", e))?;
    let ahead = fields
        .next()
        .ok_or_else(|| format!("Unexpected git rev-list output: {}", output.trim()))?
        .parse::<usize>()
        .map_err(|e| format!("Failed to parse ahead count from git rev-list: {}", e))?;

    Ok((behind, ahead))
}

async fn git_remote_get_url(repo_dir: &PathBuf, remote: &str) -> Result<Option<String>, String> {
    let output = Command::new("git")
        .args(["remote", "get-url", remote])
        .current_dir(repo_dir)
        .output()
        .await
        .map_err(|e| format!("git remote get-url {} failed: {}", remote, e))?;

    if !output.status.success() {
        return Ok(None);
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if stdout.is_empty() {
        Ok(None)
    } else {
        Ok(Some(stdout))
    }
}

async fn ensure_origin_remote(repo_dir: &PathBuf, remote_url: &str) -> Result<(), String> {
    match git_remote_get_url(repo_dir, "origin").await? {
        Some(current_url) if current_url == remote_url => Ok(()),
        Some(_) => Command::new("git")
            .args(["remote", "set-url", "origin", remote_url])
            .current_dir(repo_dir)
            .output()
            .await
            .map_err(|e| format!("git remote set-url failed: {}", e))
            .and_then(|output| {
                if output.status.success() {
                    Ok(())
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                    Err(format!(
                        "git remote set-url failed: {}",
                        if stderr.is_empty() {
                            "no output".to_string()
                        } else {
                            stderr
                        }
                    ))
                }
            }),
        None => Command::new("git")
            .args(["remote", "add", "origin", remote_url])
            .current_dir(repo_dir)
            .output()
            .await
            .map_err(|e| format!("git remote add failed: {}", e))
            .and_then(|output| {
                if output.status.success() {
                    Ok(())
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                    Err(format!(
                        "git remote add failed: {}",
                        if stderr.is_empty() {
                            "no output".to_string()
                        } else {
                            stderr
                        }
                    ))
                }
            }),
    }
}

async fn gather_repo_health(repo_dir: &PathBuf) -> Result<RepoHealthStatus, String> {
    let status_output = Command::new("git")
        .args(["status", "--porcelain"])
        .current_dir(repo_dir)
        .output()
        .await
        .map_err(|e| format!("git status --porcelain failed: {}", e))?;

    if !status_output.status.success() {
        let stderr = String::from_utf8_lossy(&status_output.stderr)
            .trim()
            .to_string();
        return Err(format!(
            "git status --porcelain failed: {}",
            if stderr.is_empty() {
                "no output".to_string()
            } else {
                stderr
            }
        ));
    }

    let working_tree_changes =
        count_nonempty_lines(String::from_utf8_lossy(&status_output.stdout).as_ref());

    let remote_ref_output = Command::new("git")
        .args(["rev-parse", "--verify", REMOTE_MAIN_REF])
        .current_dir(repo_dir)
        .output()
        .await
        .map_err(|e| format!("git rev-parse {} failed: {}", REMOTE_MAIN_REF, e))?;

    let ahead_count = if remote_ref_output.status.success() {
        let rev_list_output = Command::new("git")
            .args(["rev-list", "--left-right", "--count", "origin/main...HEAD"])
            .current_dir(repo_dir)
            .output()
            .await
            .map_err(|e| format!("git rev-list origin/main...HEAD failed: {}", e))?;

        if !rev_list_output.status.success() {
            let stderr = String::from_utf8_lossy(&rev_list_output.stderr)
                .trim()
                .to_string();
            return Err(format!(
                "git rev-list origin/main...HEAD failed: {}",
                if stderr.is_empty() {
                    "no output".to_string()
                } else {
                    stderr
                }
            ));
        }

        let (_, ahead) =
            parse_rev_list_counts(String::from_utf8_lossy(&rev_list_output.stdout).as_ref())?;
        ahead
    } else {
        0
    };

    Ok(RepoHealthStatus {
        working_tree_changes,
        ahead_count,
    })
}

/// Phases of the first-boot wizard.
///
/// Onboarding flow (REQ-008):
/// Stage 5: Secure Boot → TPM → reboot
/// Stage 6: SSH keys → repo review → push pending install commit → secrets
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirstBootPhase {
    // Stage 5: First boot after install
    Welcome,
    // Security enrollment (Stage 5 continued)
    SecureBootEnroll,
    TpmEnroll,
    RebootPrompt, // reboot for SB+TPM to take effect
    // Stage 6: After security reboot
    SshKeySetup,       // TODO: detect/generate/import SSH keys
    ShowSshKey,        // display public key for user to add to GitHub
    RemoteInput,       // enter git remote URL
    PreparingPush,     // set remote and inspect repo health before push
    RepoHealthWarning, // warn when local repo state is not fully committed/pushed
    Pushing,           // push the pending install commit
    SecretsSetup,      // TODO: agenix secrets initialization
    Done,
    Failed(String),
}

/// Messages from first-boot async operations.
enum FirstBootMessage {
    Output(String),
    SshKey(String),
    RepoPrepared(Result<RepoHealthStatus, String>),
    PushResult(Result<(), String>),
    Failed(String),
    SecureBootStatus(super::security::secure_boot::Status),
    SecureBootEnrollResult(Result<String, String>),
    TpmStatus(super::security::tpm::Status),
}

pub struct FirstBootScreen {
    config: FirstBootConfig,
    phase: FirstBootPhase,
    output_lines: Vec<String>,
    ssh_public_key: Option<String>,
    repo_health_status: RepoHealthStatus,
    remote_input: TextInput,
    rx: Option<mpsc::UnboundedReceiver<FirstBootMessage>>,
    push_skipped: bool,
    done_message: String,
    marker_removed: bool,
    sb_status: Option<super::security::secure_boot::Status>,
    sb_busy: bool,
    sb_enroll_result: Option<Result<String, String>>,
    tpm_status: Option<super::security::tpm::Status>,
    tpm_busy: bool,
}

impl FirstBootScreen {
    pub fn new(config: FirstBootConfig) -> Self {
        let default_repo_name = config
            .config_dir
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.is_empty())
            .unwrap_or("keystone-config");
        let default_remote = config
            .github_username
            .as_ref()
            .map(|gh| format!("git@github.com:{}/{}.git", gh, default_repo_name))
            .unwrap_or_default();

        let mut remote_input =
            TextInput::new().with_placeholder("git@github.com:user/keystone-config.git");
        if !default_remote.is_empty() {
            remote_input.set_value(&default_remote);
        }

        Self {
            config,
            phase: FirstBootPhase::Welcome,
            output_lines: Vec::new(),
            ssh_public_key: None,
            repo_health_status: RepoHealthStatus::default(),
            remote_input,
            rx: None,
            push_skipped: false,
            done_message: "Setup complete.".to_string(),
            marker_removed: false,
            sb_status: None,
            sb_busy: false,
            sb_enroll_result: None,
            tpm_status: None,
            tpm_busy: false,
        }
    }

    pub fn phase(&self) -> &FirstBootPhase {
        &self.phase
    }

    pub fn ssh_public_key(&self) -> Option<&str> {
        self.ssh_public_key.as_deref()
    }

    /// Start the first-boot process (Welcome → SecureBootEnroll).
    pub fn start(&mut self) {
        if self.phase != FirstBootPhase::Welcome {
            return;
        }
        self.phase = FirstBootPhase::SecureBootEnroll;
        self.spawn_sb_check();
    }

    fn spawn_sb_check(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        self.sb_busy = true;

        tokio::spawn(async move {
            let status = super::security::secure_boot::check_status().await;
            let _ = tx.send(FirstBootMessage::SecureBootStatus(status));
        });
    }

    fn spawn_sb_enroll(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        self.sb_busy = true;

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Provisioning Secure Boot keys...".to_string(),
            ));
            match super::security::secure_boot::provision().await {
                Ok(out) => {
                    let _ = tx.send(FirstBootMessage::SecureBootEnrollResult(Ok(out)));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::SecureBootEnrollResult(Err(e.to_string())));
                }
            }
        });
    }

    fn spawn_tpm_check(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        self.tpm_busy = true;

        tokio::spawn(async move {
            let status = super::security::tpm::check_status().await;
            let _ = tx.send(FirstBootMessage::TpmStatus(status));
        });
    }

    fn spawn_ssh_key_check(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let username = self.config.username.clone();

        tokio::spawn(async move {
            let home = home::home_dir().unwrap_or_else(|| PathBuf::from("/root"));
            let pub_key_path = home.join(".ssh").join("id_ed25519.pub");

            if !pub_key_path.exists() {
                let _ = tx.send(FirstBootMessage::Output(
                    "Generating SSH key...".to_string(),
                ));

                let hostname = tokio::fs::read_to_string("/etc/hostname")
                    .await
                    .unwrap_or_else(|_| "keystone".to_string());
                let hostname = hostname.trim();

                let keygen = Command::new("ssh-keygen")
                    .args([
                        "-t",
                        "ed25519",
                        "-N",
                        "",
                        "-C",
                        &format!("{}@{}", username, hostname),
                        "-f",
                        &home.join(".ssh").join("id_ed25519").display().to_string(),
                    ])
                    .output()
                    .await;

                if let Err(e) = keygen {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "ssh-keygen failed: {}",
                        e
                    )));
                    return;
                }
            }

            match tokio::fs::read_to_string(&pub_key_path).await {
                Ok(key) => {
                    let _ = tx.send(FirstBootMessage::SshKey(key.trim().to_string()));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "Failed to read SSH public key: {}",
                        e
                    )));
                }
            }
        });
    }

    fn spawn_prepare_push(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();
        let remote_url = self.remote_input.value().to_string();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(format!(
                "Adding remote: {}",
                remote_url
            )));

            if let Err(e) = ensure_origin_remote(&config_dir, &remote_url).await {
                let _ = tx.send(FirstBootMessage::RepoPrepared(Err(e)));
                return;
            }

            let _ = tx.send(FirstBootMessage::Output(
                "Checking keystone-config repo health...".to_string(),
            ));

            match gather_repo_health(&config_dir).await {
                Ok(status) => {
                    let _ = tx.send(FirstBootMessage::RepoPrepared(Ok(status)));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::RepoPrepared(Err(e)));
                }
            }
        });
    }

    fn spawn_push(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output("Pushing to remote...".to_string()));

            let push = Command::new("git")
                .args(["push", "-u", "origin", "main"])
                .current_dir(&config_dir)
                .output()
                .await;

            match push {
                Ok(out) if out.status.success() => {
                    let _ = tx.send(FirstBootMessage::PushResult(Ok(())));
                }
                Ok(out) => {
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let _ = tx.send(FirstBootMessage::PushResult(Err(format!(
                        "git push failed: {}",
                        stderr
                    ))));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::PushResult(Err(format!(
                        "git push failed: {}",
                        e
                    ))));
                }
            }
        });
    }

    /// Skip the current step.
    pub fn skip(&mut self) {
        match self.phase {
            FirstBootPhase::SshKeySetup => {
                self.push_skipped = true;
                self.complete(
                    true,
                    "Post-install onboarding completed without pushing the install commit.",
                );
            }
            FirstBootPhase::ShowSshKey => {
                self.phase = FirstBootPhase::RemoteInput;
                self.remote_input.set_focused(true);
            }
            FirstBootPhase::RemoteInput
            | FirstBootPhase::PreparingPush
            | FirstBootPhase::RepoHealthWarning
            | FirstBootPhase::Pushing
            | FirstBootPhase::Failed(_) => {
                self.push_skipped = true;
                self.complete(
                    true,
                    "Post-install onboarding completed without pushing the install commit.",
                );
            }
            _ => {}
        }
    }

    /// Continue from ShowSshKey to RemoteInput.
    pub fn continue_to_remote(&mut self) {
        if matches!(
            self.phase,
            FirstBootPhase::ShowSshKey | FirstBootPhase::SshKeySetup
        ) {
            self.phase = FirstBootPhase::RemoteInput;
            self.remote_input.set_focused(true);
        }
    }

    /// Submit the remote URL and review repo state before pushing.
    pub fn submit_remote(&mut self) {
        if self.phase != FirstBootPhase::RemoteInput {
            return;
        }
        let url = self.remote_input.value().to_string();
        if url.is_empty() {
            self.push_skipped = true;
            self.complete(
                true,
                "Post-install onboarding completed without pushing the install commit.",
            );
            return;
        }
        self.repo_health_status = RepoHealthStatus::default();
        self.phase = FirstBootPhase::PreparingPush;
        self.spawn_prepare_push();
    }

    /// Retry a failed push.
    pub fn retry_push(&mut self) {
        if matches!(self.phase, FirstBootPhase::Failed(_)) {
            self.phase = FirstBootPhase::PreparingPush;
            self.spawn_prepare_push();
        }
    }

    pub fn continue_after_repo_warning(&mut self) {
        if self.phase == FirstBootPhase::RepoHealthWarning {
            self.phase = FirstBootPhase::Pushing;
            self.spawn_push();
        }
    }

    pub fn handle_text_input(&mut self, key: crossterm::event::KeyEvent) {
        if self.phase == FirstBootPhase::RemoteInput {
            self.remote_input.handle_key(key);
        }
    }

    fn complete(&mut self, remove_marker: bool, message: &str) {
        self.done_message = message.to_string();
        self.marker_removed = remove_marker;
        if remove_marker {
            let marker = self.config.config_dir.join(".first-boot-pending");
            let _ = std::fs::remove_file(&marker);
        }
        self.phase = FirstBootPhase::Done;
    }

    pub fn poll(&mut self) {
        let rx = match self.rx.as_mut() {
            Some(rx) => rx,
            None => return,
        };

        let mut messages = Vec::new();
        while let Ok(msg) = rx.try_recv() {
            messages.push(msg);
        }

        for msg in messages {
            match msg {
                FirstBootMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                FirstBootMessage::SshKey(key) => {
                    self.ssh_public_key = Some(key);
                }
                FirstBootMessage::RepoPrepared(Ok(status)) => {
                    self.repo_health_status = status;
                    if self.repo_health_status.needs_warning() {
                        self.phase = FirstBootPhase::RepoHealthWarning;
                    } else {
                        self.phase = FirstBootPhase::Pushing;
                        self.spawn_push();
                    }
                }
                FirstBootMessage::RepoPrepared(Err(e)) => {
                    self.output_lines.push(format!("Repo check failed: {}", e));
                    self.phase = FirstBootPhase::Failed(e);
                }
                FirstBootMessage::PushResult(Ok(())) => {
                    self.output_lines.push("Push successful!".to_string());
                    self.complete(
                        true,
                        "Post-install onboarding finished and the install commit was pushed successfully.",
                    );
                }
                FirstBootMessage::PushResult(Err(e)) => {
                    self.output_lines.push(format!("Push failed: {}", e));
                    self.phase = FirstBootPhase::Failed(e);
                }
                FirstBootMessage::Failed(e) => {
                    self.phase = FirstBootPhase::Failed(e);
                }
                FirstBootMessage::SecureBootStatus(status) => {
                    self.sb_busy = false;
                    self.sb_status = Some(status);
                }
                FirstBootMessage::SecureBootEnrollResult(result) => {
                    self.sb_busy = false;
                    self.sb_enroll_result = Some(result);
                }
                FirstBootMessage::TpmStatus(status) => {
                    self.tpm_busy = false;
                    self.tpm_status = Some(status);
                }
            }
        }
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match &self.phase {
            FirstBootPhase::Welcome => self.render_welcome(frame, area),
            // Security enrollment (Stage 5)
            FirstBootPhase::SecureBootEnroll => self.render_secure_boot(frame, area),
            FirstBootPhase::TpmEnroll => self.render_tpm(frame, area),
            FirstBootPhase::RebootPrompt => self.render_reboot_prompt(frame, area),
            // SSH + push (Stage 6)
            FirstBootPhase::SshKeySetup => {
                self.render_enrollment_step(frame, area, "SSH Keys", "ssh-keygen / GitHub import")
            }
            FirstBootPhase::ShowSshKey => self.render_ssh_key(frame, area),
            FirstBootPhase::RemoteInput => self.render_remote_input(frame, area),
            FirstBootPhase::PreparingPush => self.render_progress(frame, area),
            FirstBootPhase::RepoHealthWarning => self.render_repo_health_warning(frame, area),
            FirstBootPhase::Pushing => self.render_progress(frame, area),
            FirstBootPhase::SecretsSetup => {
                self.render_enrollment_step(frame, area, "Secrets", "agenix init")
            }
            FirstBootPhase::Done => self.render_done(frame, area),
            FirstBootPhase::Failed(err) => self.render_failed(frame, area, err),
        }
    }

    fn render_welcome(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("First boot: onboarding", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let message = Paragraph::new(Text::styled(
            format!(
                "\n  Your system '{}' has been installed.\n\n  \
                 This wizard will:\n  \
                 1. Continue Secure Boot enrollment\n  \
                 2. Continue TPM2 enrollment\n  \
                 3. Set up SSH keys, review repo state, and push the install commit\n  \
                 4. Initialize secrets for services\n\n  \
                 Hardware detection and the initial local commit already happened during install.\n",
                self.config.hostname
            ),
            Style::default(),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: continue • q: exit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_progress(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let phase_label = match &self.phase {
            FirstBootPhase::PreparingPush => "Checking repo state...",
            FirstBootPhase::Pushing => "Pushing to remote...",
            _ => "Working...",
        };

        let title = Paragraph::new(Text::styled(phase_label, t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let output_lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|line| Line::from(format!("  {}", line)))
            .collect();

        let output = Paragraph::new(output_lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(t.inactive_style()),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled("Please wait...", t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_ssh_key(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("SSH Public Key", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let key_display = self.ssh_public_key.as_deref().unwrap_or("Loading...");

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from("  Add this SSH key to GitHub:"),
            Line::from("  https://github.com/settings/keys"),
            Line::from(""),
            Line::from(Span::styled(format!("  {}", key_display), t.title_style())),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        )
        .wrap(Wrap { trim: false });
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: continue to remote setup • s: skip push",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_remote_input(&self, frame: &mut Frame, area: Rect) {
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

        let title = Paragraph::new(Text::styled("Git Remote", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let instructions = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from("  Enter the git remote URL for your config repository:"),
            Line::from(""),
        ]))
        .block(Block::default());
        frame.render_widget(instructions, chunks[1]);

        self.remote_input.render(frame, chunks[2], "Remote URL");

        let help = Paragraph::new(Text::styled(
            "Enter: review repo • Esc: skip push",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    fn render_repo_health_warning(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled(
            "Repo state warning",
            t.warning_style().add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let mut lines = vec![
            Line::from(""),
            Line::from("  Keystone found local repo state that is not fully committed and pushed."),
            Line::from(""),
        ];

        if self.repo_health_status.working_tree_changes > 0 {
            lines.push(Line::from(Span::styled(
                format!(
                    "  {} working tree change(s) are still uncommitted.",
                    self.repo_health_status.working_tree_changes
                ),
                t.warning_style(),
            )));
            lines.push(Line::from(
                "  Those changes will not be included in the push unless you commit them first.",
            ));
            lines.push(Line::from(""));
        }

        if self.repo_health_status.ahead_count > 0 {
            lines.push(Line::from(Span::styled(
                format!(
                    "  {} local commit(s) are ahead of {}.",
                    self.repo_health_status.ahead_count, REMOTE_MAIN_REF
                ),
                t.warning_style(),
            )));
            lines.push(Line::from(
                "  Continuing will push those local commits to the configured origin.",
            ));
            lines.push(Line::from(""));
        }

        lines.push(Line::from(format!(
            "  Repo: {}",
            self.config.config_dir.display()
        )));

        let body = Paragraph::new(lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.warning)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(body, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: continue to push • s: skip push • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    /// Generic enrollment step placeholder for SB, TPM, SSH, secrets.
    fn render_enrollment_step(&self, frame: &mut Frame, area: Rect, title: &str, tool: &str) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled(format!("Setup: {}", title), t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let body = Paragraph::new(Text::styled(
            format!(
                "\n  TODO: {} enrollment\n\n  \
                 Tool: {}\n\n  \
                 Press Enter to continue or 's' to skip.",
                title, tool,
            ),
            Style::default(),
        ))
        .block(Block::default().borders(Borders::ALL));
        frame.render_widget(body, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: proceed • s: skip • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_secure_boot(&self, frame: &mut Frame, area: Rect) {
        use super::security::secure_boot::Status as SbStatus;

        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled("Setup: Secure Boot", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let body_text = if self.sb_busy {
            "\n  Checking Secure Boot status...".to_string()
        } else {
            match (&self.sb_status, &self.sb_enroll_result) {
                (Some(SbStatus::Enrolled), _) => {
                    "\n  [ok] Secure Boot keys are enrolled and active.\n\n  \
                     Press Enter to continue."
                        .to_string()
                }
                (Some(SbStatus::KeysGenerated), _) => "\n  [ok] Secure Boot keys generated.\n  \
                     A reboot is needed to activate Secure Boot.\n\n  \
                     Press Enter to continue."
                    .to_string(),
                (Some(SbStatus::SetupMode), Some(Ok(_))) => {
                    "\n  [ok] Secure Boot keys enrolled successfully!\n\n  \
                     Press Enter to continue."
                        .to_string()
                }
                (Some(SbStatus::SetupMode), Some(Err(e))) => {
                    format!(
                        "\n  [error] Enrollment failed: {}\n\n  \
                         Press Enter to retry or 's' to skip.",
                        e
                    )
                }
                (Some(SbStatus::SetupMode), None) => {
                    "\n  UEFI is in Setup Mode — ready to enroll keys.\n\n  \
                     Press Enter to enroll Secure Boot keys or 's' to skip."
                        .to_string()
                }
                (Some(SbStatus::NotInSetupMode), _) => "\n  Secure Boot is not in Setup Mode.\n  \
                     Keys cannot be enrolled from the OS.\n\n  \
                     To enroll: enable Setup Mode in BIOS, then reboot.\n\n  \
                     Press Enter to continue or 's' to skip."
                    .to_string(),
                _ => "\n  Could not determine Secure Boot status.\n\n  \
                     Press Enter to continue or 's' to skip."
                    .to_string(),
            }
        };

        let body = Paragraph::new(Text::styled(body_text, Style::default()))
            .block(Block::default().borders(Borders::ALL))
            .wrap(Wrap { trim: false });
        frame.render_widget(body, chunks[1]);

        let help_text = if self.sb_busy {
            "Checking..."
        } else {
            "Enter: proceed • s: skip • q: quit"
        };
        let help = Paragraph::new(Text::styled(help_text, t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_tpm(&self, frame: &mut Frame, area: Rect) {
        use super::security::tpm::Status as TpmStatus;

        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled("Setup: TPM2", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let body_text = if self.tpm_busy {
            "\n  Checking TPM status...".to_string()
        } else {
            match &self.tpm_status {
                Some(TpmStatus::Enrolled) => "\n  [ok] TPM auto-unlock is configured.\n\n  \
                     Press Enter to continue."
                    .to_string(),
                Some(TpmStatus::Available) => {
                    format!(
                        "\n  TPM2 device detected but not yet enrolled.\n\n  \
                         {}\n\n  \
                         Press Enter to continue (you can enroll after this wizard).",
                        super::security::tpm::enroll_instructions()
                    )
                }
                Some(TpmStatus::NotAvailable) => "\n  No TPM2 device detected.\n\n  \
                     TPM auto-unlock is not available on this system.\n\n  \
                     Press Enter to continue."
                    .to_string(),
                _ => "\n  Could not determine TPM status.\n\n  \
                     Press Enter to continue or 's' to skip."
                    .to_string(),
            }
        };

        let body = Paragraph::new(Text::styled(body_text, Style::default()))
            .block(Block::default().borders(Borders::ALL))
            .wrap(Wrap { trim: false });
        frame.render_widget(body, chunks[1]);

        let help_text = if self.tpm_busy {
            "Checking..."
        } else {
            "Enter: continue • s: skip • q: quit"
        };
        let help = Paragraph::new(Text::styled(help_text, t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_reboot_prompt(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled("Reboot required", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let body = Paragraph::new(Text::styled(
            "\n  Secure Boot and TPM enrollment require a reboot to take effect.\n\n  \
             After rebooting, the TUI will continue with SSH key setup,\n  \
             review the repo state, and push the pending install commit.",
            Style::default(),
        ))
        .block(Block::default().borders(Borders::ALL));
        frame.render_widget(body, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: reboot now • s: skip (continue without reboot) • q: quit",
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
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("First-boot flow complete", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let marker_status = if self.marker_removed {
            "  First-boot marker: cleared"
        } else {
            "  First-boot marker: preserved"
        };

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from(format!("  {}", self.done_message)),
            Line::from(marker_status),
            Line::from(""),
            Line::from(format!("  Config: {}", self.config.config_dir.display())),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled("q: exit", t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, error: &str) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "First-boot flow failed",
            t.error_style().add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let mut lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|l| Line::from(format!("  {}", l)))
            .collect();
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            format!("  Error: {}", error),
            t.error_style().add_modifier(Modifier::BOLD),
        )));

        let output = Paragraph::new(lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.error)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: retry • s: skip • q: exit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

impl Component for FirstBootScreen {
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

impl FirstBootScreen {
    /// Handle a key press, returning an optional global Action.
    fn handle_key_event(
        &mut self,
        code: KeyCode,
        key: &crossterm::event::KeyEvent,
    ) -> Option<Action> {
        match self.phase() {
            FirstBootPhase::Welcome => match code {
                KeyCode::Enter => {
                    self.start();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::PreparingPush | FirstBootPhase::Pushing => {
                // No user input during async phases
                None
            }
            // Security enrollment (Stage 5)
            FirstBootPhase::SecureBootEnroll => {
                if self.sb_busy {
                    return None;
                }
                match code {
                    KeyCode::Enter => {
                        use super::security::secure_boot::Status as SbStatus;
                        match (&self.sb_status, &self.sb_enroll_result) {
                            // Setup mode, no enrollment attempted yet → enroll
                            (Some(SbStatus::SetupMode), None) => {
                                self.spawn_sb_enroll();
                                None
                            }
                            // Setup mode, enrollment failed → retry
                            (Some(SbStatus::SetupMode), Some(Err(_))) => {
                                self.sb_enroll_result = None;
                                self.spawn_sb_enroll();
                                None
                            }
                            // Any other state → advance to TPM
                            _ => {
                                self.phase = FirstBootPhase::TpmEnroll;
                                self.spawn_tpm_check();
                                None
                            }
                        }
                    }
                    KeyCode::Char('s') => {
                        self.phase = FirstBootPhase::TpmEnroll;
                        self.spawn_tpm_check();
                        None
                    }
                    KeyCode::Char('q') => Some(Action::Quit),
                    _ => None,
                }
            }
            FirstBootPhase::TpmEnroll => {
                if self.tpm_busy {
                    return None;
                }
                match code {
                    KeyCode::Enter | KeyCode::Char('s') => {
                        self.phase = FirstBootPhase::RebootPrompt;
                        None
                    }
                    KeyCode::Char('q') => Some(Action::Quit),
                    _ => None,
                }
            }
            FirstBootPhase::RebootPrompt => match code {
                KeyCode::Char('r') => Some(Action::Reboot),
                KeyCode::Char('s') => {
                    // Skip reboot, continue to SSH key setup
                    self.phase = FirstBootPhase::SshKeySetup;
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            // Stage 6: SSH keys + push
            FirstBootPhase::SshKeySetup => match code {
                // TODO: wire to security::yubikey::detect_devices()
                // TODO: offer ssh-keygen, GitHub import, YubiKey enrollment
                KeyCode::Enter => {
                    self.phase = FirstBootPhase::ShowSshKey;
                    self.spawn_ssh_key_check();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::SecretsSetup => match code {
                // TODO: wire to agenix secrets init
                KeyCode::Enter | KeyCode::Char('s') => {
                    self.complete(true, "Onboarding complete!");
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::ShowSshKey => match code {
                KeyCode::Enter => {
                    self.continue_to_remote();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::RemoteInput => match code {
                KeyCode::Enter => {
                    self.submit_remote();
                    None
                }
                KeyCode::Esc => {
                    self.skip();
                    None
                }
                _ => {
                    self.handle_text_input(*key);
                    None
                }
            },
            FirstBootPhase::RepoHealthWarning => match code {
                KeyCode::Enter => {
                    self.continue_after_repo_warning();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::Done => match code {
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::Failed(_) => match code {
                KeyCode::Char('r') => {
                    self.retry_push();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::components::security::{secure_boot, tpm};

    fn test_first_boot_config() -> FirstBootConfig {
        FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/repos/testuser/keystone-config"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: Some("octocat".to_string()),
        }
    }

    #[test]
    fn test_initial_phase_is_welcome() {
        let screen = FirstBootScreen::new(test_first_boot_config());
        assert_eq!(*screen.phase(), FirstBootPhase::Welcome);
    }

    #[tokio::test]
    async fn test_start_moves_into_secure_boot_enrollment() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.start();
        assert_eq!(*screen.phase(), FirstBootPhase::SecureBootEnroll);
    }

    #[test]
    fn test_remote_input_pre_filled() {
        let screen = FirstBootScreen::new(test_first_boot_config());
        assert_eq!(
            screen.remote_input.value(),
            "git@github.com:octocat/keystone-config.git"
        );
    }

    #[test]
    fn test_remote_input_empty_without_github() {
        let config = FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/repos/testuser/keystone-config"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: None,
        };
        let screen = FirstBootScreen::new(config);
        assert_eq!(screen.remote_input.value(), "");
    }

    #[test]
    fn test_remote_input_uses_custom_installed_repo_name() {
        let config = FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/repos/testuser/custom-config"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: Some("octocat".to_string()),
        };
        let screen = FirstBootScreen::new(config);
        assert_eq!(
            screen.remote_input.value(),
            "git@github.com:octocat/custom-config.git"
        );
    }

    #[test]
    fn test_count_nonempty_lines_ignores_blank_lines() {
        assert_eq!(count_nonempty_lines(" M flake.lock\n\n?? notes.txt\n"), 2);
    }

    #[test]
    fn test_parse_rev_list_counts_reads_ahead_and_behind() {
        assert_eq!(parse_rev_list_counts("3\t2\n").unwrap(), (3, 2));
    }

    #[test]
    fn test_skip_from_ssh_key_setup_completes_onboarding() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::SshKeySetup;
        screen.skip();

        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(screen.push_skipped);
        assert!(screen.marker_removed);
    }

    #[test]
    fn test_skip_from_ssh_key() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::ShowSshKey;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::RemoteInput);
    }

    #[test]
    fn test_skip_from_remote_input() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::RemoteInput;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(screen.push_skipped);
        assert!(screen.marker_removed);
    }

    #[tokio::test]
    async fn test_sb_enrolled_advances_to_tpm() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::SecureBootEnroll;
        screen.sb_status = Some(secure_boot::Status::Enrolled);
        screen.handle_key_event(
            KeyCode::Enter,
            &crossterm::event::KeyEvent::new(KeyCode::Enter, crossterm::event::KeyModifiers::NONE),
        );
        assert_eq!(*screen.phase(), FirstBootPhase::TpmEnroll);
    }

    #[tokio::test]
    async fn test_sb_skip_advances_to_tpm() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::SecureBootEnroll;
        screen.handle_key_event(
            KeyCode::Char('s'),
            &crossterm::event::KeyEvent::new(
                KeyCode::Char('s'),
                crossterm::event::KeyModifiers::NONE,
            ),
        );
        assert_eq!(*screen.phase(), FirstBootPhase::TpmEnroll);
    }

    #[test]
    fn test_sb_busy_ignores_input() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::SecureBootEnroll;
        screen.sb_busy = true;
        screen.handle_key_event(
            KeyCode::Enter,
            &crossterm::event::KeyEvent::new(KeyCode::Enter, crossterm::event::KeyModifiers::NONE),
        );
        // Should stay on SecureBootEnroll since busy
        assert_eq!(*screen.phase(), FirstBootPhase::SecureBootEnroll);
    }

    #[test]
    fn test_poll_sb_status() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::SecureBootEnroll;
        screen.sb_busy = true;

        tx.send(FirstBootMessage::SecureBootStatus(
            secure_boot::Status::Enrolled,
        ))
        .unwrap();

        screen.poll();
        assert!(!screen.sb_busy);
        assert_eq!(screen.sb_status, Some(secure_boot::Status::Enrolled));
    }

    #[test]
    fn test_poll_tpm_status() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::TpmEnroll;
        screen.tpm_busy = true;

        tx.send(FirstBootMessage::TpmStatus(tpm::Status::Available))
            .unwrap();

        screen.poll();
        assert!(!screen.tpm_busy);
        assert_eq!(screen.tpm_status, Some(tpm::Status::Available));
    }

    #[test]
    fn test_skip_from_failed_completes_onboarding() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::Failed("auth failed".to_string());
        screen.skip();

        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(screen.push_skipped);
        assert!(screen.marker_removed);
    }

    #[test]
    fn test_poll_ssh_key() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::ShowSshKey;

        tx.send(FirstBootMessage::SshKey(
            "ssh-ed25519 AAAAC3test testuser@test-machine".to_string(),
        ))
        .unwrap();

        screen.poll();
        assert!(screen.ssh_public_key().is_some());
        assert!(screen.ssh_public_key().unwrap().contains("ssh-ed25519"));
    }

    #[tokio::test]
    async fn test_continue_after_repo_warning_starts_push_phase() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::RepoHealthWarning;

        screen.continue_after_repo_warning();

        assert_eq!(*screen.phase(), FirstBootPhase::Pushing);
        assert!(screen.rx.is_some());
    }

    #[test]
    fn test_poll_repo_prepared_warns_when_repo_is_dirty() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::PreparingPush;

        tx.send(FirstBootMessage::RepoPrepared(Ok(RepoHealthStatus {
            working_tree_changes: 2,
            ahead_count: 0,
        })))
        .unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), FirstBootPhase::RepoHealthWarning);
        assert_eq!(screen.repo_health_status.working_tree_changes, 2);
    }

    #[tokio::test]
    async fn test_poll_repo_prepared_pushes_clean_repo() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::PreparingPush;

        tx.send(FirstBootMessage::RepoPrepared(Ok(RepoHealthStatus {
            working_tree_changes: 0,
            ahead_count: 0,
        })))
        .unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), FirstBootPhase::Pushing);
        assert!(screen.rx.is_some());
    }

    #[test]
    fn test_poll_push_success() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::Pushing;

        tx.send(FirstBootMessage::PushResult(Ok(()))).unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(!screen.push_skipped);
        assert!(screen.marker_removed);
    }

    #[test]
    fn test_poll_push_failure() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::Pushing;

        tx.send(FirstBootMessage::PushResult(Err("auth failed".to_string())))
            .unwrap();

        screen.poll();
        assert!(matches!(screen.phase(), FirstBootPhase::Failed(_)));
    }
}
