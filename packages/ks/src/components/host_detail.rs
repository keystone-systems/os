//! Host detail screen - displays configuration summary for a single host.

use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::action::{Action, Screen};
use crate::component::Component;
use crate::nix::HostInfo;

/// Screen displaying details about a single NixOS host configuration.
pub struct HostDetailScreen {
    /// The host info being displayed.
    host: HostInfo,
}

impl HostDetailScreen {
    pub fn new(host: HostInfo) -> Self {
        Self { host }
    }

    pub fn host(&self) -> &HostInfo {
        &self.host
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Details
                Constraint::Length(3), // Help
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            format!("Host: {}", self.host.name),
            t.title_style(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Details
        let mut lines: Vec<Line> = Vec::new();
        lines.push(Line::from(""));

        // System
        let system_value = self.host.system.as_deref().unwrap_or("unknown");
        lines.push(Line::from(vec![
            Span::styled("  System:     ", t.inactive_style()),
            Span::styled(system_value, Style::default()),
        ]));

        lines.push(Line::from(""));

        // Keystone modules
        if self.host.keystone_modules.is_empty() {
            lines.push(Line::from(vec![
                Span::styled("  Modules:    ", t.inactive_style()),
                Span::styled("(none)", t.inactive_style()),
            ]));
        } else {
            for (i, module) in self.host.keystone_modules.iter().enumerate() {
                let label = if i == 0 {
                    "  Modules:    "
                } else {
                    "              "
                };
                lines.push(Line::from(vec![
                    Span::styled(label, t.inactive_style()),
                    Span::styled(module.as_str(), Style::default().fg(t.active)),
                ]));
            }
        }

        // Host metadata (from keystone.hosts)
        if let Some(meta) = &self.host.metadata {
            lines.push(Line::from(""));
            if !meta.role.is_empty() {
                lines.push(Line::from(vec![
                    Span::styled("  Role:       ", t.inactive_style()),
                    Span::styled(meta.role.as_str(), Style::default().fg(t.metadata)),
                ]));
            }
            if !meta.ssh_target.is_empty() {
                lines.push(Line::from(vec![
                    Span::styled("  SSH:        ", t.inactive_style()),
                    Span::styled(meta.ssh_target.as_str(), Style::default()),
                ]));
            }
            if !meta.fallback_ip.is_empty() {
                lines.push(Line::from(vec![
                    Span::styled("  Fallback IP:", t.inactive_style()),
                    Span::styled(format!(" {}", meta.fallback_ip), Style::default()),
                ]));
            }
            let mut flags = Vec::new();
            if meta.baremetal {
                flags.push("baremetal");
            }
            if meta.zfs {
                flags.push("zfs");
            }
            if meta.build_on_remote {
                flags.push("remote-build");
            }
            if !flags.is_empty() {
                lines.push(Line::from(vec![
                    Span::styled("  Flags:      ", t.inactive_style()),
                    Span::styled(flags.join(", "), Style::default().fg(t.accent)),
                ]));
            }
        }

        lines.push(Line::from(""));

        // Config files
        if self.host.config_files.is_empty() {
            lines.push(Line::from(vec![
                Span::styled("  Config:     ", t.inactive_style()),
                Span::styled("(none)", t.inactive_style()),
            ]));
        } else {
            for (i, path) in self.host.config_files.iter().enumerate() {
                let label = if i == 0 {
                    "  Config:     "
                } else {
                    "              "
                };
                lines.push(Line::from(vec![
                    Span::styled(label, t.inactive_style()),
                    Span::styled(path.as_str(), Style::default().fg(t.path)),
                ]));
            }
        }

        let details = Paragraph::new(lines).block(Block::default().borders(Borders::NONE));
        frame.render_widget(details, chunks[1]);

        // Help text
        let help = Paragraph::new(Text::styled(
            "b: build • Esc: back • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

impl Component for HostDetailScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match key.code {
                KeyCode::Char('q') => Some(Action::Quit),
                KeyCode::Esc => Some(Action::GoBack),
                KeyCode::Char('b') => {
                    let host_name = self.host.name.clone();
                    Some(Action::NavigateTo(Screen::Build { host_name }))
                }
                _ => None,
            });
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_host_accessor() {
        let host = HostInfo {
            name: "my-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec!["operating-system".to_string(), "desktop".to_string()],
            config_files: vec!["./configuration.nix".to_string()],
            metadata: None,
        };
        let screen = HostDetailScreen::new(host);
        assert_eq!(screen.host().name, "my-host");
        assert_eq!(screen.host().system.as_deref(), Some("x86_64-linux"));
        assert_eq!(screen.host().keystone_modules.len(), 2);
    }

    #[test]
    fn test_host_with_no_system() {
        let host = HostInfo {
            name: "unknown-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        };
        let screen = HostDetailScreen::new(host);
        assert_eq!(screen.host().name, "unknown-host");
        assert!(screen.host().system.is_none());
    }
}
