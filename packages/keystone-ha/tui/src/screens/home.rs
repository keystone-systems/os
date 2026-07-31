//! Home screen rendering
//!
//! Main menu with navigation to all workflow areas.

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
};

use crate::app::App;

/// Render the home screen / main menu
pub fn render(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4), // Welcome message
            Constraint::Min(10),   // Menu
        ])
        .split(area);

    // Welcome message
    let welcome = Paragraph::new(vec![
        Line::from(""),
        Line::from("Welcome to the Keystone Cross-Realm Manager"),
        Line::from("Select a workflow area to get started"),
    ])
    .style(Style::default().fg(Color::Gray))
    .alignment(Alignment::Center);

    frame.render_widget(welcome, chunks[0]);

    // Main menu items
    let menu_items = vec![
        ListItem::new(Line::from(vec![
            Span::styled("[1] ", Style::default().fg(Color::Yellow)),
            Span::raw("Grant Management"),
            Span::styled(
                "  - Create and manage resource grants",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("[2] ", Style::default().fg(Color::Yellow)),
            Span::raw("Realm Connections"),
            Span::styled(
                "  - Connect to other realms",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("[3] ", Style::default().fg(Color::Yellow)),
            Span::raw("Workloads"),
            Span::styled(
                "  - Deploy and manage workloads",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("[4] ", Style::default().fg(Color::Yellow)),
            Span::raw("Super Entities"),
            Span::styled(
                "  - Shared ownership structures",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("[5] ", Style::default().fg(Color::Yellow)),
            Span::raw("Backups"),
            Span::styled(
                "  - View and verify backups",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
    ];

    let menu = List::new(menu_items)
        .block(
            Block::default()
                .title(" Main Menu ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::White)),
        )
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");

    let mut state = ListState::default();
    state.select(Some(app.list_index));

    frame.render_stateful_widget(menu, chunks[1], &mut state);
}
