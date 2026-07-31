//! Backup management screens
//!
//! Screens for viewing and verifying distributed backups.

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

use crate::app::App;
use crate::types::{BackupPhase, BackupType};

/// Render the backup list screen
pub fn render_list(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Instructions
            Constraint::Min(5),    // List
        ])
        .split(area);

    // Instructions
    let instructions = Paragraph::new("Select a backup to view details or verify")
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    frame.render_widget(instructions, chunks[0]);

    if app.backups.is_empty() {
        // Empty state
        let empty = Paragraph::new(vec![
            Line::from(""),
            Line::from("No backups found"),
            Line::from(""),
            Line::from("Backups will appear here once configured"),
            Line::from("through super entity storage pools"),
        ])
        .style(Style::default().fg(Color::Gray))
        .block(
            Block::default()
                .title(" Backup Status ")
                .borders(Borders::ALL),
        )
        .alignment(Alignment::Center);
        frame.render_widget(empty, chunks[1]);
    } else {
        // Backup list
        let items: Vec<ListItem> = app
            .backups
            .iter()
            .map(|b| {
                let (status_icon, status_color) = match b.status {
                    BackupPhase::Healthy => ("✓", Color::Green),
                    BackupPhase::Degraded => ("⚠", Color::Yellow),
                    BackupPhase::Verifying => ("⟳", Color::Cyan),
                    BackupPhase::Failed => ("✗", Color::Red),
                    BackupPhase::Unknown => ("?", Color::Gray),
                };

                let type_label = match b.backup_type {
                    BackupType::Local => "[Local]",
                    BackupType::SuperEntity => "[Super Entity]",
                    BackupType::Remote => "[Remote]",
                };

                ListItem::new(Line::from(vec![
                    Span::styled(status_icon, Style::default().fg(status_color)),
                    Span::raw(format!(" {} ", b.name)),
                    Span::styled(type_label, Style::default().fg(Color::DarkGray)),
                    Span::raw(format!(" ({} copies)", b.copy_count)),
                ]))
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .title(format!(" Backups ({}) ", app.backups.len()))
                    .borders(Borders::ALL),
            )
            .highlight_style(
                Style::default()
                    .bg(Color::DarkGray)
                    .add_modifier(Modifier::BOLD),
            )
            .highlight_symbol("▶ ");

        let mut state = ListState::default();
        state.select(Some(app.list_index));

        frame.render_stateful_widget(list, chunks[1], &mut state);
    }
}

/// Render the backup verification screen
pub fn render_verify(frame: &mut Frame, area: Rect, app: &App, id: &str) {
    let backup = app.backups.iter().find(|b| b.id == id);

    let content = if let Some(b) = backup {
        let (status_icon, status_color, status_text) = match b.status {
            BackupPhase::Healthy => ("✓", Color::Green, "All copies verified and healthy"),
            BackupPhase::Degraded => ("⚠", Color::Yellow, "Some copies missing or degraded"),
            BackupPhase::Verifying => ("⟳", Color::Cyan, "Verification in progress..."),
            BackupPhase::Failed => ("✗", Color::Red, "Verification failed"),
            BackupPhase::Unknown => ("?", Color::Gray, "Status unknown"),
        };

        let mut lines = vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("Backup: ", Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(&b.name),
            ]),
            Line::from(""),
            Line::from(format!("Type: {}", b.backup_type)),
            Line::from(format!("Size: {}", b.size.as_deref().unwrap_or("Unknown"))),
            Line::from(""),
            Line::from(vec![
                Span::raw("Status: "),
                Span::styled(
                    format!("{} {}", status_icon, status_text),
                    Style::default().fg(status_color),
                ),
            ]),
            Line::from(""),
            Line::from(format!("Copy Count: {}", b.copy_count)),
            Line::from(""),
            Line::from(Span::styled("Locations:", Style::default().add_modifier(Modifier::BOLD))),
        ];

        for location in &b.locations {
            lines.push(Line::from(format!("  • {}", location)));
        }

        lines.push(Line::from(""));
        lines.push(Line::from(format!(
            "Last Verified: {}",
            b.last_verified.as_deref().unwrap_or("Never")
        )));
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "Press 'v' to verify now, Esc to go back",
            Style::default().fg(Color::Yellow),
        )));

        Paragraph::new(lines)
    } else {
        Paragraph::new("Backup not found")
    };

    let widget = content
        .block(
            Block::default()
                .title(" Backup Verification ")
                .borders(Borders::ALL),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}
