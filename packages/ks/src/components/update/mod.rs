//! Update component — pull, lock, build, push, deploy.
//!
//! Replaces the `ks update` shell script with a TUI/CLI/JSON interface.
//! Future: types.rs + run.rs for CLI/JSON shared logic.

use crate::action::Action;
use crate::component::Component;
use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Rect},
    style::{Color, Style, Stylize},
    text::Text,
    widgets::Paragraph,
    Frame,
};

#[derive(Default)]
pub struct UpdateScreen;

impl UpdateScreen {
    pub fn new() -> Self {
        Self
    }
}

impl Component for UpdateScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            match key.code {
                KeyCode::Char('q') => return Ok(Some(Action::Quit)),
                KeyCode::Esc => return Ok(Some(Action::GoBack)),
                _ => {}
            }
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        let text = Paragraph::new(Text::styled(
            "System update — coming soon",
            Style::default().bold().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, area);
        Ok(())
    }
}
