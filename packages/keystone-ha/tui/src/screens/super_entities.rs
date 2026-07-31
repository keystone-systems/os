//! Super entity management screens
//!
//! Screens for creating and managing super entities (shared ownership structures).

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

use crate::app::App;
use crate::types::SuperEntityPhase;

/// Render the super entity list screen
pub fn render_list(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Instructions
            Constraint::Min(5),    // List
        ])
        .split(area);

    // Instructions
    let instructions = Paragraph::new("Press 'c' or 'n' to create a new super entity")
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    frame.render_widget(instructions, chunks[0]);

    if app.super_entities.is_empty() {
        // Empty state
        let empty = Paragraph::new(vec![
            Line::from(""),
            Line::from("No super entities"),
            Line::from(""),
            Line::from("Create a super entity to share infrastructure with other realms"),
            Line::from("(e.g., family backup pool, business partnership)"),
        ])
        .style(Style::default().fg(Color::Gray))
        .block(
            Block::default()
                .title(" Super Entities ")
                .borders(Borders::ALL),
        )
        .alignment(Alignment::Center);
        frame.render_widget(empty, chunks[1]);
    } else {
        // Super entity list
        let items: Vec<ListItem> = app
            .super_entities
            .iter()
            .map(|e| {
                let phase = e.status.as_ref().map(|s| s.phase.clone()).unwrap_or_default();
                let status_color = match phase {
                    SuperEntityPhase::Active => Color::Green,
                    SuperEntityPhase::Pending => Color::Yellow,
                    SuperEntityPhase::Incomplete => Color::Red,
                };

                ListItem::new(Line::from(vec![
                    Span::raw(format!("{} ", e.spec.name)),
                    Span::styled(
                        format!("({} members)", e.spec.member_realms.len()),
                        Style::default().fg(Color::DarkGray),
                    ),
                    Span::raw(" "),
                    Span::styled(
                        format!("[{}]", phase),
                        Style::default().fg(status_color),
                    ),
                ]))
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .title(format!(" Super Entities ({}) ", app.super_entities.len()))
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

/// Render the super entity creation screen
pub fn render_create(frame: &mut Frame, area: Rect, app: &App) {
    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled("Create Super Entity", Style::default().add_modifier(Modifier::BOLD))),
        Line::from(""),
        Line::from("A super entity is a shared ownership structure allowing multiple"),
        Line::from("realms to pool resources (e.g., distributed backups)."),
        Line::from(""),
        Line::from(vec![
            Span::styled("Name: ", Style::default().fg(if app.form_field == 0 { Color::Cyan } else { Color::White })),
            Span::raw(if app.input_buffer.is_empty() { "<entity name>" } else { &app.input_buffer }),
            if app.form_field == 0 { Span::styled("█", Style::default().fg(Color::Cyan)) } else { Span::raw("") },
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("Purpose: ", Style::default().fg(if app.form_field == 1 { Color::Cyan } else { Color::White })),
            Span::raw("<e.g., Family Backup Pool>"),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("Members: ", Style::default().fg(if app.form_field == 2 { Color::Cyan } else { Color::White })),
            Span::raw("<comma-separated realm IDs>"),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "Note: All members must approve before the super entity becomes active",
            Style::default().fg(Color::DarkGray),
        )),
        Line::from(""),
        Line::from(Span::styled(
            "Tab to switch fields, Enter to create, Esc to cancel",
            Style::default().fg(Color::Yellow),
        )),
    ])
    .block(
        Block::default()
            .title(" Create Super Entity ")
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

/// Render super entity detail screen
pub fn render_detail(frame: &mut Frame, area: Rect, app: &App, id: &str) {
    let entity = app.super_entities.iter().find(|e| e.name() == id);

    let content = if let Some(e) = entity {
        let phase = e.status.as_ref().map(|s| s.phase.clone()).unwrap_or_default();
        let status_color = match phase {
            SuperEntityPhase::Active => Color::Green,
            SuperEntityPhase::Pending => Color::Yellow,
            SuperEntityPhase::Incomplete => Color::Red,
        };

        let mut lines = vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("Super Entity: ", Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(&e.spec.name),
            ]),
            Line::from(""),
            Line::from(format!("ID: {}", e.name())),
            Line::from(format!("Purpose: {}", e.spec.purpose)),
            Line::from(""),
            Line::from(vec![
                Span::raw("Status: "),
                Span::styled(phase.to_string(), Style::default().fg(status_color)),
            ]),
            Line::from(""),
            Line::from(Span::styled("Members:", Style::default().add_modifier(Modifier::BOLD))),
        ];

        for member in &e.spec.member_realms {
            lines.push(Line::from(format!("  • {}", member)));
        }

        lines.push(Line::from(""));
        lines.push(Line::from(format!("Storage Contributed: {}", e.spec.storage_contributed)));
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "Press 'c' to contribute storage, Esc to go back",
            Style::default().fg(Color::DarkGray),
        )));

        Paragraph::new(lines)
    } else {
        Paragraph::new("Super entity not found")
    };

    let widget = content
        .block(
            Block::default()
                .title(" Super Entity Details ")
                .borders(Borders::ALL),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}