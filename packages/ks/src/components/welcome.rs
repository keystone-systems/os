use crate::action::{Action, Screen};
use crate::component::Component;
use crate::widgets::TextInput;
use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Text},
    widgets::{Block, Borders, Clear, Paragraph},
    Frame,
};

/// The Welcome screen, displayed on first run or when no repos are configured.
pub struct WelcomeScreen {
    state: WelcomeState,
    selected_option: WelcomeOption,
    git_url_input: TextInput,
    repo_name_input: TextInput,
    error_message: Option<String>,
    success_message: Option<String>,
    /// Pending async import (name, git_url) — picked up by the app event loop.
    pending_import: Option<(String, String)>,
}

/// State machine for the welcome screen flow.
#[derive(Debug, Default, PartialEq, Eq, Clone)]
pub enum WelcomeState {
    #[default]
    SelectAction,
    InputGitUrl,
    InputRepoName,
    Importing,
    Creating,
    Success,
    Error,
}

#[derive(Debug, Default, PartialEq, Eq, Clone, Copy)]
pub enum WelcomeOption {
    #[default]
    ImportExisting,
    CreateNew,
}

/// Result from handling input on the welcome screen.
#[derive(Debug)]
pub enum WelcomeAction {
    None,
    ImportRepo {
        name: String,
        git_url: String,
    },
    CreateRepo {
        name: String,
    },
    /// User acknowledged success - app should transition to repos view
    Complete,
}

impl Default for WelcomeScreen {
    fn default() -> Self {
        Self::new()
    }
}

impl WelcomeScreen {
    pub fn new() -> Self {
        Self {
            state: WelcomeState::SelectAction,
            selected_option: WelcomeOption::ImportExisting,
            git_url_input: TextInput::new().with_placeholder("https://github.com/user/repo.git"),
            repo_name_input: TextInput::new().with_placeholder("my-infrastructure"),
            error_message: None,
            success_message: None,
            pending_import: None,
        }
    }

    pub fn state(&self) -> &WelcomeState {
        &self.state
    }

    pub fn next(&mut self) {
        if self.state == WelcomeState::SelectAction {
            self.selected_option = match self.selected_option {
                WelcomeOption::ImportExisting => WelcomeOption::CreateNew,
                WelcomeOption::CreateNew => WelcomeOption::ImportExisting,
            };
        }
    }

    pub fn previous(&mut self) {
        if self.state == WelcomeState::SelectAction {
            self.selected_option = match self.selected_option {
                WelcomeOption::ImportExisting => WelcomeOption::CreateNew,
                WelcomeOption::CreateNew => WelcomeOption::ImportExisting,
            };
        }
    }

    pub fn get_selected_option(&self) -> WelcomeOption {
        self.selected_option
    }

    /// Handle Enter key press, returning an action to perform.
    pub fn confirm(&mut self) -> WelcomeAction {
        match self.state {
            WelcomeState::SelectAction => {
                match self.selected_option {
                    WelcomeOption::ImportExisting => {
                        self.state = WelcomeState::InputGitUrl;
                        self.git_url_input.set_focused(true);
                    }
                    WelcomeOption::CreateNew => {
                        self.state = WelcomeState::InputRepoName;
                        self.repo_name_input.set_focused(true);
                    }
                }
                WelcomeAction::None
            }
            WelcomeState::InputGitUrl => {
                let git_url = self.git_url_input.value().to_string();
                if git_url.is_empty() {
                    self.error_message = Some("Git URL cannot be empty".to_string());
                    self.state = WelcomeState::Error;
                    return WelcomeAction::None;
                }
                // Extract repo name from URL
                let name =
                    extract_repo_name(&git_url).unwrap_or_else(|| "keystone-config".to_string());
                self.state = WelcomeState::Importing;
                WelcomeAction::ImportRepo { name, git_url }
            }
            WelcomeState::InputRepoName => {
                let name = self.repo_name_input.value().to_string();
                if name.is_empty() {
                    self.error_message = Some("Repository name cannot be empty".to_string());
                    self.state = WelcomeState::Error;
                    return WelcomeAction::None;
                }
                self.state = WelcomeState::Creating;
                WelcomeAction::CreateRepo { name }
            }
            WelcomeState::Error => {
                // Dismiss error and go back to appropriate state
                self.error_message = None;
                self.state = WelcomeState::SelectAction;
                WelcomeAction::None
            }
            WelcomeState::Success => {
                // User acknowledged success - signal app to transition
                WelcomeAction::Complete
            }
            _ => WelcomeAction::None,
        }
    }

    /// Handle Escape key press.
    pub fn cancel(&mut self) {
        match self.state {
            WelcomeState::InputGitUrl | WelcomeState::InputRepoName => {
                self.git_url_input.set_focused(false);
                self.repo_name_input.set_focused(false);
                self.state = WelcomeState::SelectAction;
            }
            WelcomeState::Error => {
                self.error_message = None;
                self.state = WelcomeState::SelectAction;
            }
            _ => {}
        }
    }

    /// Handle text input for the current state.
    pub fn handle_text_input(&mut self, key: KeyEvent) -> bool {
        match self.state {
            WelcomeState::InputGitUrl => self.git_url_input.handle_key(key),
            WelcomeState::InputRepoName => self.repo_name_input.handle_key(key),
            _ => false,
        }
    }

    /// Called when import/create operation completes successfully.
    pub fn set_success(&mut self, message: String) {
        self.success_message = Some(message);
        self.state = WelcomeState::Success;
    }

    /// Called when import/create operation fails.
    pub fn set_error(&mut self, message: String) {
        self.error_message = Some(message);
        self.state = WelcomeState::Error;
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match self.state {
            WelcomeState::SelectAction => self.render_select_action(frame, area),
            WelcomeState::InputGitUrl => self.render_input_git_url(frame, area),
            WelcomeState::InputRepoName => self.render_input_repo_name(frame, area),
            WelcomeState::Importing => self.render_loading(frame, area, "Cloning repository..."),
            WelcomeState::Creating => {
                self.render_loading(frame, area, "Creating repository from template...")
            }
            WelcomeState::Success => self.render_success(frame, area),
            WelcomeState::Error => self.render_error(frame, area),
        }
    }

    fn render_select_action(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Length(3),
                Constraint::Length(3),
                Constraint::Percentage(30),
                Constraint::Min(0),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled("Welcome to ks!", t.title_style()))
            .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Import option
        let import_style = if self.selected_option == WelcomeOption::ImportExisting {
            t.active_style()
        } else {
            Style::default()
        };
        let import_prefix = if self.selected_option == WelcomeOption::ImportExisting {
            "> "
        } else {
            "  "
        };
        let import_text = Paragraph::new(format!("{}Import existing repository", import_prefix))
            .style(import_style)
            .alignment(Alignment::Center);
        frame.render_widget(import_text, chunks[1]);

        // Create option
        let create_style = if self.selected_option == WelcomeOption::CreateNew {
            t.active_style()
        } else {
            Style::default()
        };
        let create_prefix = if self.selected_option == WelcomeOption::CreateNew {
            "> "
        } else {
            "  "
        };
        let create_text = Paragraph::new(format!("{}Create new repository", create_prefix))
            .style(create_style)
            .alignment(Alignment::Center);
        frame.render_widget(create_text, chunks[2]);

        // Help text
        let help = Paragraph::new(Text::styled(
            "↑/↓ or j/k to navigate • Enter to select • q to quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    fn render_input_git_url(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Length(3),
                Constraint::Length(3),
                Constraint::Min(0),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled("Import Existing Repository", t.title_style()))
            .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Input area (centered)
        let input_area = centered_rect(60, 3, chunks[1]);
        self.git_url_input.render(frame, input_area, "Git URL");

        // Help text
        let help = Paragraph::new(Text::styled(
            "Enter to confirm • Esc to cancel",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_input_repo_name(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Length(3),
                Constraint::Length(3),
                Constraint::Min(0),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled("Create New Repository", t.title_style()))
            .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Input area (centered)
        let input_area = centered_rect(60, 3, chunks[1]);
        self.repo_name_input
            .render(frame, input_area, "Repository Name");

        // Help text
        let help = Paragraph::new(Text::styled(
            "Enter to confirm • Esc to cancel",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_loading(&self, frame: &mut Frame, area: Rect, message: &str) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(45),
                Constraint::Length(3),
                Constraint::Percentage(45),
            ])
            .split(area);

        let loading =
            Paragraph::new(Text::styled(message, t.warning_style())).alignment(Alignment::Center);
        frame.render_widget(loading, chunks[1]);
    }

    fn render_success(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let popup_area = centered_rect(60, 20, area);
        frame.render_widget(Clear, popup_area);

        let message = self
            .success_message
            .as_deref()
            .unwrap_or("Operation completed successfully!");
        let lines: Vec<Line> = vec![
            Line::from("").style(Style::default()),
            Line::from("✓ Success!").style(t.active_style()),
            Line::from("").style(Style::default()),
            Line::from(message).style(Style::default()),
            Line::from("").style(Style::default()),
            Line::from("Press Enter to continue").style(t.inactive_style()),
        ];

        let paragraph = Paragraph::new(lines).alignment(Alignment::Center).block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(paragraph, popup_area);
    }

    fn render_error(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let popup_area = centered_rect(60, 20, area);
        frame.render_widget(Clear, popup_area);

        let message = self.error_message.as_deref().unwrap_or("An error occurred");
        let lines: Vec<Line> = vec![
            Line::from("").style(Style::default()),
            Line::from("✗ Error")
                .style(t.error_style().add_modifier(ratatui::style::Modifier::BOLD)),
            Line::from("").style(Style::default()),
            Line::from(message).style(Style::default()),
            Line::from("").style(Style::default()),
            Line::from("Press Enter or Esc to dismiss").style(t.inactive_style()),
        ];

        let paragraph = Paragraph::new(lines).alignment(Alignment::Center).block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.error)),
        );
        frame.render_widget(paragraph, popup_area);
    }
}

impl Component for WelcomeScreen {
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

impl WelcomeScreen {
    /// Handle a key event, returning an optional global Action for navigation.
    fn handle_key_event(&mut self, key: &KeyEvent) -> Option<Action> {
        match key.code {
            KeyCode::Char('q') if self.state == WelcomeState::SelectAction => Some(Action::Quit),
            KeyCode::Up | KeyCode::Char('k') => {
                self.previous();
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.next();
                None
            }
            KeyCode::Enter => self.handle_confirm(),
            KeyCode::Esc => {
                self.cancel();
                None
            }
            _ => {
                // Forward to text input if in an input state
                self.handle_text_input(*key);
                None
            }
        }
    }

    /// Handle Enter press, converting WelcomeAction to global Action.
    fn handle_confirm(&mut self) -> Option<Action> {
        match self.confirm() {
            WelcomeAction::ImportRepo { name, git_url } => {
                // Async operation — caller must handle this via the legacy path for now.
                // Store the intent so the app can pick it up.
                self.pending_import = Some((name, git_url));
                None
            }
            WelcomeAction::CreateRepo { name } => {
                Some(Action::NavigateTo(Screen::Template { repo_name: name }))
            }
            WelcomeAction::Complete => Some(Action::NavigateTo(Screen::Hosts)),
            WelcomeAction::None => None,
        }
    }

    /// Check and take any pending async import action.
    pub fn take_pending_import(&mut self) -> Option<(String, String)> {
        self.pending_import.take()
    }
}

/// Extract repository name from a git URL.
fn extract_repo_name(url: &str) -> Option<String> {
    // Handle both HTTPS and SSH URLs
    // https://github.com/user/repo.git -> repo
    // git@github.com:user/repo.git -> repo
    let url = url.trim_end_matches(".git");
    url.rsplit('/')
        .next()
        .or_else(|| url.rsplit(':').next())
        .map(|s| s.to_string())
}

/// Create a centered rectangle within the given area.
fn centered_rect(percent_x: u16, height: u16, area: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(area);

    Rect {
        x: popup_layout[1].x,
        y: popup_layout[1].y,
        width: popup_layout[1].width,
        height: height.min(popup_layout[1].height),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state() {
        let screen = WelcomeScreen::new();
        assert_eq!(*screen.state(), WelcomeState::SelectAction);
        assert_eq!(screen.get_selected_option(), WelcomeOption::ImportExisting);
    }

    #[test]
    fn test_toggle_options() {
        let mut screen = WelcomeScreen::new();
        assert_eq!(screen.get_selected_option(), WelcomeOption::ImportExisting);
        screen.next();
        assert_eq!(screen.get_selected_option(), WelcomeOption::CreateNew);
        screen.next();
        assert_eq!(screen.get_selected_option(), WelcomeOption::ImportExisting);
    }

    #[test]
    fn test_previous_toggles() {
        let mut screen = WelcomeScreen::new();
        screen.previous();
        assert_eq!(screen.get_selected_option(), WelcomeOption::CreateNew);
    }

    #[test]
    fn test_confirm_import_transitions_to_input() {
        let mut screen = WelcomeScreen::new();
        // Select ImportExisting (default) and confirm
        let action = screen.confirm();
        assert!(matches!(action, WelcomeAction::None));
        assert_eq!(*screen.state(), WelcomeState::InputGitUrl);
    }

    #[test]
    fn test_confirm_create_transitions_to_input() {
        let mut screen = WelcomeScreen::new();
        screen.next(); // Select CreateNew
        let action = screen.confirm();
        assert!(matches!(action, WelcomeAction::None));
        assert_eq!(*screen.state(), WelcomeState::InputRepoName);
    }

    #[test]
    fn test_empty_git_url_produces_error() {
        let mut screen = WelcomeScreen::new();
        screen.confirm(); // Go to InputGitUrl
                          // Confirm with empty URL
        let action = screen.confirm();
        assert!(matches!(action, WelcomeAction::None));
        assert_eq!(*screen.state(), WelcomeState::Error);
    }

    #[test]
    fn test_cancel_returns_to_select() {
        let mut screen = WelcomeScreen::new();
        screen.confirm(); // Go to InputGitUrl
        assert_eq!(*screen.state(), WelcomeState::InputGitUrl);
        screen.cancel();
        assert_eq!(*screen.state(), WelcomeState::SelectAction);
    }

    #[test]
    fn test_success_then_complete() {
        let mut screen = WelcomeScreen::new();
        screen.set_success("Repo imported!".to_string());
        assert_eq!(*screen.state(), WelcomeState::Success);
        let action = screen.confirm();
        assert!(matches!(action, WelcomeAction::Complete));
    }

    #[test]
    fn test_git_url_entry_and_confirm() {
        let mut screen = WelcomeScreen::new();
        screen.confirm(); // Go to InputGitUrl
        assert_eq!(*screen.state(), WelcomeState::InputGitUrl);

        // Type a URL via handle_text_input
        use crossterm::event::{KeyCode, KeyEventKind, KeyEventState, KeyModifiers};
        let chars = "https://github.com/user/my-repo.git";
        for c in chars.chars() {
            screen.handle_text_input(KeyEvent {
                code: KeyCode::Char(c),
                modifiers: KeyModifiers::NONE,
                kind: KeyEventKind::Press,
                state: KeyEventState::NONE,
            });
        }

        let action = screen.confirm();
        match action {
            WelcomeAction::ImportRepo { name, git_url } => {
                assert_eq!(git_url, "https://github.com/user/my-repo.git");
                assert_eq!(name, "my-repo");
            }
            other => panic!("Expected ImportRepo, got {:?}", other),
        }
        assert_eq!(*screen.state(), WelcomeState::Importing);
    }

    #[test]
    fn test_extract_repo_name_https() {
        assert_eq!(
            extract_repo_name("https://github.com/user/my-repo.git"),
            Some("my-repo".to_string())
        );
    }

    #[test]
    fn test_extract_repo_name_ssh() {
        assert_eq!(
            extract_repo_name("git@github.com:user/my-repo.git"),
            Some("my-repo".to_string())
        );
    }
}
