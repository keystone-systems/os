//! Text input widget for the ks.

use crossterm::event::{KeyCode, KeyEvent};
use ratatui::{
    layout::Rect,
    style::Style,
    widgets::{Block, Borders, Paragraph},
    Frame,
};

/// A simple text input field.
#[derive(Default, Clone)]
pub struct TextInput {
    /// The current input value.
    value: String,
    /// Cursor position within the input.
    cursor_position: usize,
    /// Placeholder text shown when empty.
    placeholder: String,
    /// Whether the input is focused.
    focused: bool,
}

impl TextInput {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_placeholder(mut self, placeholder: impl Into<String>) -> Self {
        self.placeholder = placeholder.into();
        self
    }

    pub fn value(&self) -> &str {
        &self.value
    }

    pub fn set_value(&mut self, value: impl Into<String>) {
        self.value = value.into();
        self.cursor_position = self.value.len();
    }

    pub fn clear(&mut self) {
        self.value.clear();
        self.cursor_position = 0;
    }

    pub fn set_focused(&mut self, focused: bool) {
        self.focused = focused;
    }

    pub fn is_focused(&self) -> bool {
        self.focused
    }

    /// Handle a key event, returning true if the event was consumed.
    pub fn handle_key(&mut self, key: KeyEvent) -> bool {
        match key.code {
            KeyCode::Char(c) => {
                self.value.insert(self.cursor_position, c);
                self.cursor_position += 1;
                true
            }
            KeyCode::Backspace => {
                if self.cursor_position > 0 {
                    self.cursor_position -= 1;
                    self.value.remove(self.cursor_position);
                }
                true
            }
            KeyCode::Delete => {
                if self.cursor_position < self.value.len() {
                    self.value.remove(self.cursor_position);
                }
                true
            }
            KeyCode::Left => {
                if self.cursor_position > 0 {
                    self.cursor_position -= 1;
                }
                true
            }
            KeyCode::Right => {
                if self.cursor_position < self.value.len() {
                    self.cursor_position += 1;
                }
                true
            }
            KeyCode::Home => {
                self.cursor_position = 0;
                true
            }
            KeyCode::End => {
                self.cursor_position = self.value.len();
                true
            }
            _ => false,
        }
    }

    /// Get the current cursor position.
    pub fn cursor_position(&self) -> usize {
        self.cursor_position
    }

    /// Render the text input widget.
    pub fn render(&self, frame: &mut Frame, area: Rect, title: &str) {
        let t = crate::theme::default();
        let display_text = if self.value.is_empty() && !self.focused {
            self.placeholder.clone()
        } else {
            self.value.clone()
        };

        let style = if self.focused {
            Style::default().fg(t.accent)
        } else if self.value.is_empty() {
            t.inactive_style()
        } else {
            Style::default()
        };

        let border_style = if self.focused {
            Style::default().fg(t.accent)
        } else {
            Style::default()
        };

        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(border_style);

        let paragraph = Paragraph::new(display_text).style(style).block(block);

        frame.render_widget(paragraph, area);

        // Show cursor when focused
        if self.focused {
            let cursor_x = area.x + 1 + self.cursor_position as u16;
            let cursor_y = area.y + 1;
            if cursor_x < area.x + area.width - 1 {
                frame.set_cursor_position((cursor_x, cursor_y));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyEventKind, KeyEventState, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent {
            code,
            modifiers: KeyModifiers::NONE,
            kind: KeyEventKind::Press,
            state: KeyEventState::NONE,
        }
    }

    #[test]
    fn test_typing_characters() {
        let mut input = TextInput::new();
        input.handle_key(key(KeyCode::Char('h')));
        input.handle_key(key(KeyCode::Char('i')));
        assert_eq!(input.value(), "hi");
        assert_eq!(input.cursor_position(), 2);
    }

    #[test]
    fn test_backspace() {
        let mut input = TextInput::new();
        input.set_value("hello");
        input.handle_key(key(KeyCode::Backspace));
        assert_eq!(input.value(), "hell");
        assert_eq!(input.cursor_position(), 4);
    }

    #[test]
    fn test_backspace_at_start_is_noop() {
        let mut input = TextInput::new();
        input.handle_key(key(KeyCode::Backspace));
        assert_eq!(input.value(), "");
        assert_eq!(input.cursor_position(), 0);
    }

    #[test]
    fn test_cursor_movement_left_right() {
        let mut input = TextInput::new();
        input.set_value("abc");
        assert_eq!(input.cursor_position(), 3);

        input.handle_key(key(KeyCode::Left));
        assert_eq!(input.cursor_position(), 2);

        input.handle_key(key(KeyCode::Left));
        assert_eq!(input.cursor_position(), 1);

        input.handle_key(key(KeyCode::Right));
        assert_eq!(input.cursor_position(), 2);
    }

    #[test]
    fn test_home_and_end() {
        let mut input = TextInput::new();
        input.set_value("hello");

        input.handle_key(key(KeyCode::Home));
        assert_eq!(input.cursor_position(), 0);

        input.handle_key(key(KeyCode::End));
        assert_eq!(input.cursor_position(), 5);
    }

    #[test]
    fn test_delete_key() {
        let mut input = TextInput::new();
        input.set_value("abc");
        input.handle_key(key(KeyCode::Home));
        input.handle_key(key(KeyCode::Delete));
        assert_eq!(input.value(), "bc");
        assert_eq!(input.cursor_position(), 0);
    }

    #[test]
    fn test_insert_at_cursor_position() {
        let mut input = TextInput::new();
        input.set_value("ac");
        input.handle_key(key(KeyCode::Home));
        input.handle_key(key(KeyCode::Right)); // cursor at 1
        input.handle_key(key(KeyCode::Char('b')));
        assert_eq!(input.value(), "abc");
        assert_eq!(input.cursor_position(), 2);
    }
}
