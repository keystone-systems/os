//! Services component — keystoneServices host placement.

use crate::action::{Action, Screen};
use crate::component::Component;
use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Rect},
    text::Text,
    widgets::Paragraph,
    Frame,
};

#[derive(Default)]
pub struct ServicesScreen;

impl ServicesScreen {
    pub fn new() -> Self {
        Self
    }
}

impl Component for ServicesScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match key.code {
                KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                KeyCode::Char('1') => Some(Action::NavigateTo(Screen::Hosts)),
                KeyCode::Char('3') => Some(Action::NavigateTo(Screen::Secrets)),
                KeyCode::Char('4') => Some(Action::NavigateTo(Screen::Security)),
                KeyCode::Char('5') => Some(Action::NavigateTo(Screen::Installer)),
                _ => None,
            });
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        let shell = crate::widgets::shell::render_shell(
            frame,
            area,
            "Services",
            "",
            1,
            "1-5: sections • q: quit",
            None,
        );

        let t = crate::theme::default();
        let text = Paragraph::new(Text::styled(
            "Service placement — coming soon",
            t.inactive_style()
                .add_modifier(ratatui::style::Modifier::BOLD),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, shell.content);
        Ok(())
    }
}
