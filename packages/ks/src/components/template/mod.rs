//! Template component — generate new Keystone configs.
//!
//! This is a complex component with colocated CLI/JSON shared logic:
//! - `types.rs`: TemplateParams, TemplateResult (Serialize/Deserialize)
//! - `run.rs`: execute(params) -> Result (shared by JSON, CLI, and TUI)
//! - `mod.rs`: TUI form component (this file)

pub mod run;
pub mod types;

use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style, Stylize},
    text::Text,
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::action::Action;
use crate::component::Component;
use crate::template::{MachineType, StorageType};
use crate::widgets::TextInput;

/// Which form field is currently active.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FormField {
    MachineType,
    Hostname,
    StorageType,
    DiskDevice,
    Username,
    GitHubUsername,
    Password,
}

impl FormField {
    /// Whether this field uses text input (vs. selection).
    pub fn is_text_input(&self) -> bool {
        matches!(
            self,
            FormField::Hostname
                | FormField::DiskDevice
                | FormField::Username
                | FormField::GitHubUsername
                | FormField::Password
        )
    }
}

/// The ordered list of visible form fields.
const FIELD_ORDER: &[FormField] = &[
    FormField::MachineType,
    FormField::Hostname,
    FormField::StorageType,
    FormField::DiskDevice,
    FormField::Username,
    FormField::GitHubUsername,
    FormField::Password,
];

/// Action returned by the create-config screen.
#[derive(Debug)]
pub enum CreateConfigAction {
    None,
    Complete {
        machine_type: MachineType,
        hostname: String,
        storage_type: StorageType,
        disk_device: Option<String>,
        username: String,
        password: String,
        github_username: String,
    },
}

/// The create-configuration form screen.
pub struct CreateConfigScreen {
    repo_name: String,
    current_field: usize,

    // Selection fields
    machine_type: MachineType,
    storage_type: StorageType,

    // Text input fields
    hostname_input: TextInput,
    disk_device_input: TextInput,
    username_input: TextInput,
    github_username_input: TextInput,
    password_input: TextInput,
}

impl CreateConfigScreen {
    pub fn new(repo_name: String) -> Self {
        Self {
            repo_name,
            current_field: 0,
            machine_type: MachineType::Server,
            storage_type: StorageType::Zfs,
            hostname_input: TextInput::new().with_placeholder("my-machine"),
            disk_device_input: TextInput::new()
                .with_placeholder("/dev/disk/by-id/nvme-... (optional)"),
            username_input: TextInput::new().with_placeholder("admin"),
            github_username_input: TextInput::new().with_placeholder("octocat"),
            password_input: TextInput::new().with_placeholder("changeme"),
        }
    }

    pub fn current_form_field(&self) -> FormField {
        FIELD_ORDER[self.current_field]
    }

    /// Move to the next form field.
    pub fn next_field(&mut self) {
        self.unfocus_current();
        self.current_field = (self.current_field + 1) % FIELD_ORDER.len();
        self.focus_current();
    }

    /// Move to the previous form field.
    pub fn prev_field(&mut self) {
        self.unfocus_current();
        self.current_field = if self.current_field == 0 {
            FIELD_ORDER.len() - 1
        } else {
            self.current_field - 1
        };
        self.focus_current();
    }

    /// Cycle selection values (for MachineType / StorageType fields).
    pub fn cycle_selection_next(&mut self) {
        match self.current_form_field() {
            FormField::MachineType => {
                self.machine_type = match self.machine_type {
                    MachineType::Server => MachineType::Workstation,
                    MachineType::Workstation => MachineType::Laptop,
                    MachineType::Laptop => MachineType::Server,
                };
                // Auto-set storage type based on machine type
                self.storage_type = match self.machine_type {
                    MachineType::Laptop => StorageType::Ext4,
                    _ => StorageType::Zfs,
                };
            }
            FormField::StorageType => {
                self.storage_type = match self.storage_type {
                    StorageType::Zfs => StorageType::Ext4,
                    StorageType::Ext4 => StorageType::Zfs,
                };
            }
            _ => {}
        }
    }

    pub fn cycle_selection_prev(&mut self) {
        // Same as next for 2-3 item cycles
        self.cycle_selection_next();
    }

    /// Handle text input for the current field.
    pub fn handle_text_input(&mut self, key: KeyEvent) -> bool {
        match self.current_form_field() {
            FormField::Hostname => self.hostname_input.handle_key(key),
            FormField::DiskDevice => self.disk_device_input.handle_key(key),
            FormField::Username => self.username_input.handle_key(key),
            FormField::GitHubUsername => self.github_username_input.handle_key(key),
            FormField::Password => self.password_input.handle_key(key),
            _ => false,
        }
    }

    /// Submit the form. Returns Complete if all required fields are filled.
    /// Disk device is optional — if empty, it will be selected at install time.
    pub fn submit(&mut self) -> CreateConfigAction {
        let hostname = self.hostname_input.value().to_string();
        let disk_device_raw = self.disk_device_input.value().to_string();
        let username = self.username_input.value().to_string();
        let password = self.password_input.value().to_string();
        let github_username = self.github_username_input.value().to_string();

        // Validate required fields (disk_device is optional)
        if hostname.is_empty() || username.is_empty() || password.is_empty() {
            return CreateConfigAction::None;
        }

        let disk_device = if disk_device_raw.is_empty() {
            None
        } else {
            Some(disk_device_raw)
        };

        CreateConfigAction::Complete {
            machine_type: self.machine_type,
            hostname,
            storage_type: self.storage_type,
            disk_device,
            username,
            password,
            github_username,
        }
    }

    fn unfocus_current(&mut self) {
        match self.current_form_field() {
            FormField::Hostname => self.hostname_input.set_focused(false),
            FormField::DiskDevice => self.disk_device_input.set_focused(false),
            FormField::Username => self.username_input.set_focused(false),
            FormField::GitHubUsername => self.github_username_input.set_focused(false),
            FormField::Password => self.password_input.set_focused(false),
            _ => {}
        }
    }

    fn focus_current(&mut self) {
        match self.current_form_field() {
            FormField::Hostname => self.hostname_input.set_focused(true),
            FormField::DiskDevice => self.disk_device_input.set_focused(true),
            FormField::Username => self.username_input.set_focused(true),
            FormField::GitHubUsername => self.github_username_input.set_focused(true),
            FormField::Password => self.password_input.set_focused(true),
            _ => {}
        }
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(0),    // Form body
                Constraint::Length(2), // Help text
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            format!("New Configuration — {}", self.repo_name),
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Form fields
        let field_count = FIELD_ORDER.len() as u16;
        let mut field_constraints = Vec::with_capacity(field_count as usize + 1);
        for _ in 0..field_count {
            field_constraints.push(Constraint::Length(3));
        }
        field_constraints.push(Constraint::Min(0)); // spacer

        let form_area = centered_rect(70, chunks[1]);
        let field_chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints(field_constraints)
            .split(form_area);

        for (i, field) in FIELD_ORDER.iter().enumerate() {
            let is_active = i == self.current_field;
            self.render_field(frame, field_chunks[i], *field, is_active);
        }

        // Help text
        let help = Paragraph::new(Text::styled(
            "Tab/Shift-Tab: navigate fields • ←/→: cycle options • Enter: create • Esc: cancel",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_field(&self, frame: &mut Frame, area: Rect, field: FormField, is_active: bool) {
        match field {
            FormField::MachineType => {
                self.render_selection_field(
                    frame,
                    area,
                    "Machine Type",
                    self.machine_type.label(),
                    is_active,
                );
            }
            FormField::StorageType => {
                self.render_selection_field(
                    frame,
                    area,
                    "Storage Type",
                    self.storage_type.label(),
                    is_active,
                );
            }
            FormField::Hostname => {
                self.hostname_input.render(frame, area, "Hostname");
                if is_active {
                    self.highlight_border(frame, area);
                }
            }
            FormField::DiskDevice => {
                self.disk_device_input.render(frame, area, "Disk Device");
                if is_active {
                    self.highlight_border(frame, area);
                }
            }
            FormField::Username => {
                self.username_input.render(frame, area, "Username");
                if is_active {
                    self.highlight_border(frame, area);
                }
            }
            FormField::GitHubUsername => {
                self.github_username_input.render(
                    frame,
                    area,
                    "GitHub Username (optional — fetches SSH keys)",
                );
                if is_active {
                    self.highlight_border(frame, area);
                }
            }
            FormField::Password => {
                self.password_input.render(frame, area, "Password");
                if is_active {
                    self.highlight_border(frame, area);
                }
            }
        }
    }

    fn render_selection_field(
        &self,
        frame: &mut Frame,
        area: Rect,
        title: &str,
        value: &str,
        is_active: bool,
    ) {
        let style = if is_active {
            Style::default().fg(Color::Yellow)
        } else {
            Style::default()
        };

        let border_style = if is_active {
            Style::default().fg(Color::Yellow)
        } else {
            Style::default()
        };

        let indicator = if is_active { " ◄ ► " } else { "" };
        let display = format!("{}{}", value, indicator);

        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(border_style);

        let paragraph = Paragraph::new(display).style(style).block(block);
        frame.render_widget(paragraph, area);
    }

    fn highlight_border(&self, _frame: &mut Frame, _area: Rect) {
        // TextInput already handles its own border color when focused.
        // This is a no-op placeholder for consistency.
    }
}

/// Create a horizontally centered rectangle with the given width percentage.
fn centered_rect(percent_x: u16, area: Rect) -> Rect {
    let margin = (100 - percent_x) / 2;
    let layout = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(margin),
            Constraint::Percentage(percent_x),
            Constraint::Percentage(margin),
        ])
        .split(area);
    layout[1]
}

impl Component for CreateConfigScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(self.handle_key_event(key));
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

impl CreateConfigScreen {
    /// Handle a key event, returning an optional global Action for navigation.
    fn handle_key_event(&mut self, key: &KeyEvent) -> Option<Action> {
        let field = self.current_form_field();

        if field.is_text_input() {
            match key.code {
                KeyCode::Tab => {
                    self.next_field();
                    None
                }
                KeyCode::BackTab => {
                    self.prev_field();
                    None
                }
                KeyCode::Enter => {
                    // Submit returns a CreateConfigAction; async handling
                    // stays in the legacy path until fully migrated.
                    let _action = self.submit();
                    None
                }
                KeyCode::Esc => Some(Action::Quit),
                _ => {
                    self.handle_text_input(*key);
                    None
                }
            }
        } else {
            // Selection field (MachineType, StorageType)
            match key.code {
                KeyCode::Tab | KeyCode::Down | KeyCode::Char('j') => {
                    self.next_field();
                    None
                }
                KeyCode::BackTab | KeyCode::Up | KeyCode::Char('k') => {
                    self.prev_field();
                    None
                }
                KeyCode::Left | KeyCode::Char('h') => {
                    self.cycle_selection_prev();
                    None
                }
                KeyCode::Right | KeyCode::Char('l') => {
                    self.cycle_selection_next();
                    None
                }
                KeyCode::Enter => {
                    let _action = self.submit();
                    None
                }
                KeyCode::Esc => Some(Action::Quit),
                _ => None,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state() {
        let screen = CreateConfigScreen::new("test-repo".to_string());
        assert_eq!(screen.current_form_field(), FormField::MachineType);
    }

    #[test]
    fn test_field_cycle() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());

        // Walk through all fields
        let expected = [
            FormField::MachineType,
            FormField::Hostname,
            FormField::StorageType,
            FormField::DiskDevice,
            FormField::Username,
            FormField::GitHubUsername,
            FormField::Password,
        ];

        for (i, expected_field) in expected.iter().enumerate() {
            assert_eq!(
                screen.current_form_field(),
                *expected_field,
                "Field {} should be {:?}",
                i,
                expected_field
            );
            screen.next_field();
        }

        // Should wrap back to start
        assert_eq!(screen.current_form_field(), FormField::MachineType);
    }

    #[test]
    fn test_prev_field_wraps() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());
        screen.prev_field();
        assert_eq!(screen.current_form_field(), FormField::Password);
    }

    #[test]
    fn test_github_username_in_field_list() {
        assert!(FIELD_ORDER.contains(&FormField::GitHubUsername));
        // Should be after Username and before Password
        let gh_pos = FIELD_ORDER
            .iter()
            .position(|f| *f == FormField::GitHubUsername)
            .unwrap();
        let username_pos = FIELD_ORDER
            .iter()
            .position(|f| *f == FormField::Username)
            .unwrap();
        let password_pos = FIELD_ORDER
            .iter()
            .position(|f| *f == FormField::Password)
            .unwrap();
        assert!(gh_pos > username_pos);
        assert!(gh_pos < password_pos);
    }

    #[test]
    fn test_submit_empty_returns_none() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());
        let action = screen.submit();
        assert!(matches!(action, CreateConfigAction::None));
    }

    #[test]
    fn test_submit_complete() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());
        screen.hostname_input.set_value("my-host");
        screen.disk_device_input.set_value("/dev/sda");
        screen.username_input.set_value("admin");
        screen.password_input.set_value("pass123");
        screen.github_username_input.set_value("octocat");

        let action = screen.submit();
        match action {
            CreateConfigAction::Complete {
                hostname,
                disk_device,
                username,
                github_username,
                ..
            } => {
                assert_eq!(hostname, "my-host");
                assert_eq!(disk_device, Some("/dev/sda".to_string()));
                assert_eq!(username, "admin");
                assert_eq!(github_username, "octocat");
            }
            CreateConfigAction::None => panic!("Expected Complete, got None"),
        }
    }

    #[test]
    fn test_submit_without_disk_device() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());
        screen.hostname_input.set_value("my-host");
        // disk_device left empty — should succeed with None
        screen.username_input.set_value("admin");
        screen.password_input.set_value("pass123");

        let action = screen.submit();
        match action {
            CreateConfigAction::Complete { disk_device, .. } => {
                assert!(disk_device.is_none());
            }
            CreateConfigAction::None => panic!("Expected Complete"),
        }
    }

    #[test]
    fn test_submit_without_github_username() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());
        screen.hostname_input.set_value("my-host");
        screen.disk_device_input.set_value("/dev/sda");
        screen.username_input.set_value("admin");
        screen.password_input.set_value("pass123");
        // github_username left empty

        let action = screen.submit();
        match action {
            CreateConfigAction::Complete {
                github_username, ..
            } => {
                assert_eq!(github_username, "");
            }
            CreateConfigAction::None => panic!("Expected Complete"),
        }
    }

    #[test]
    fn test_machine_type_cycle() {
        let mut screen = CreateConfigScreen::new("test-repo".to_string());
        assert_eq!(screen.machine_type, MachineType::Server);

        screen.cycle_selection_next();
        assert_eq!(screen.machine_type, MachineType::Workstation);
        assert_eq!(screen.storage_type, StorageType::Zfs);

        screen.cycle_selection_next();
        assert_eq!(screen.machine_type, MachineType::Laptop);
        assert_eq!(screen.storage_type, StorageType::Ext4); // auto-set

        screen.cycle_selection_next();
        assert_eq!(screen.machine_type, MachineType::Server);
    }

    #[test]
    fn test_github_username_is_text_input() {
        assert!(FormField::GitHubUsername.is_text_input());
    }
}
