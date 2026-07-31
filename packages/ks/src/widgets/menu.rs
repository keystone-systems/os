//! Selection menu widget for the ks.

use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::Text,
    widgets::Paragraph,
    Frame,
};

/// A selectable menu with items.
pub struct SelectMenu<T> {
    items: Vec<MenuItem<T>>,
    selected: usize,
}

/// An item in a selection menu.
pub struct MenuItem<T> {
    pub label: String,
    pub value: T,
}

impl<T> SelectMenu<T> {
    pub fn new(items: Vec<MenuItem<T>>) -> Self {
        Self { items, selected: 0 }
    }

    pub fn selected_index(&self) -> usize {
        self.selected
    }

    pub fn selected_value(&self) -> Option<&T> {
        self.items.get(self.selected).map(|item| &item.value)
    }

    pub fn next(&mut self) {
        if !self.items.is_empty() {
            self.selected = (self.selected + 1) % self.items.len();
        }
    }

    pub fn previous(&mut self) {
        if !self.items.is_empty() {
            self.selected = if self.selected == 0 {
                self.items.len() - 1
            } else {
                self.selected - 1
            };
        }
    }

    /// Render the menu centered in the given area.
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        if self.items.is_empty() {
            return;
        }

        // Create constraints for each item
        let constraints: Vec<Constraint> =
            self.items.iter().map(|_| Constraint::Length(1)).collect();

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints(constraints)
            .split(area);

        for (i, item) in self.items.iter().enumerate() {
            let is_selected = i == self.selected;

            let style = if is_selected {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let prefix = if is_selected { "> " } else { "  " };
            let text = Text::styled(format!("{}{}", prefix, item.label), style);

            let paragraph = Paragraph::new(text);
            frame.render_widget(paragraph, chunks[i]);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_menu() -> SelectMenu<&'static str> {
        SelectMenu::new(vec![
            MenuItem {
                label: "Alpha".to_string(),
                value: "a",
            },
            MenuItem {
                label: "Beta".to_string(),
                value: "b",
            },
            MenuItem {
                label: "Gamma".to_string(),
                value: "c",
            },
        ])
    }

    #[test]
    fn test_initial_selection_is_zero() {
        let menu = test_menu();
        assert_eq!(menu.selected_index(), 0);
        assert_eq!(menu.selected_value(), Some(&"a"));
    }

    #[test]
    fn test_next_wraps_around() {
        let mut menu = test_menu();
        menu.next(); // 1
        menu.next(); // 2
        menu.next(); // wraps to 0
        assert_eq!(menu.selected_index(), 0);
    }

    #[test]
    fn test_previous_wraps_around() {
        let mut menu = test_menu();
        menu.previous(); // wraps to 2
        assert_eq!(menu.selected_index(), 2);
        assert_eq!(menu.selected_value(), Some(&"c"));
    }

    #[test]
    fn test_empty_menu() {
        let mut menu: SelectMenu<()> = SelectMenu::new(vec![]);
        assert_eq!(menu.selected_value(), None);
        menu.next(); // should not panic
        menu.previous(); // should not panic
        assert_eq!(menu.selected_index(), 0);
    }
}
