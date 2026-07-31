//! Realm connection screens
//!
//! Screens for connecting to and viewing connected realms.

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

use crate::app::{App, ConnectionMethod};

/// Render the connected realms list
pub fn render_list(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Instructions
            Constraint::Min(5),    // List
        ])
        .split(area);

    // Instructions
    let instructions = Paragraph::new("Press 'c' or 'n' to connect to a new realm")
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    frame.render_widget(instructions, chunks[0]);

    if app.realms.is_empty() {
        // Empty state
        let empty = Paragraph::new(vec![
            Line::from(""),
            Line::from("No connected realms"),
            Line::from(""),
            Line::from("Connect to another realm to use their granted resources"),
        ])
        .style(Style::default().fg(Color::Gray))
        .block(
            Block::default()
                .title(" Connected Realms ")
                .borders(Borders::ALL),
        )
        .alignment(Alignment::Center);
        frame.render_widget(empty, chunks[1]);
    } else {
        // Realm list
        let items: Vec<ListItem> = app
            .realms
            .iter()
            .map(|r| {
                let status_color = if r.connected { Color::Green } else { Color::Red };

                ListItem::new(Line::from(vec![
                    Span::raw(format!("{} ", r.name)),
                    Span::styled(
                        format!("({})", r.connection_type),
                        Style::default().fg(Color::DarkGray),
                    ),
                    Span::raw(" "),
                    Span::styled(
                        format!("[{}]", r.status_display()),
                        Style::default().fg(status_color),
                    ),
                ]))
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .title(format!(" Connected Realms ({}) ", app.realms.len()))
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

/// Render the realm connection screen
pub fn render_connect(frame: &mut Frame, area: Rect, app: &App, method: &Option<ConnectionMethod>) {
    match method {
        None => render_method_selection(frame, area, app),
        Some(m) => render_connection_form(frame, area, app, m),
    }
}

fn render_method_selection(frame: &mut Frame, area: Rect, app: &App) {
    let items = vec![
        ListItem::new(Line::from(vec![
            Span::styled("Tailscale", Style::default().add_modifier(Modifier::BOLD)),
            Span::styled(
                "  - Connect via shared Tailscale network",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("Headscale", Style::default().add_modifier(Modifier::BOLD)),
            Span::styled(
                "  - Connect via shared Headscale server",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("Grant Token", Style::default().add_modifier(Modifier::BOLD)),
            Span::styled(
                "  - Enter token received out-of-band",
                Style::default().fg(Color::DarkGray),
            ),
        ])),
    ];

    let list = List::new(items)
        .block(
            Block::default()
                .title(" Select Connection Method ")
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

    frame.render_stateful_widget(list, area, &mut state);
}

fn render_connection_form(frame: &mut Frame, area: Rect, app: &App, method: &ConnectionMethod) {
    let (title, placeholder) = match method {
        ConnectionMethod::Tailscale => (
            "Connect via Tailscale",
            "Enter hostname (e.g., alice-home.tailnet-name.ts.net)",
        ),
        ConnectionMethod::Headscale => (
            "Connect via Headscale",
            "Enter hostname (e.g., alice-home.headscale.example.com)",
        ),
        ConnectionMethod::Token => (
            "Connect via Grant Token",
            "Paste the grant token (keystone-grant://v1/...)",
        ),
    };

    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from(format!("Connection Method: {:?}", method)),
        Line::from(""),
        Line::from(vec![
            Span::raw("Input: "),
            Span::styled(
                if app.input_buffer.is_empty() {
                    placeholder.to_string()
                } else {
                    app.input_buffer.clone()
                },
                Style::default().fg(if app.input_buffer.is_empty() {
                    Color::DarkGray
                } else {
                    Color::White
                }),
            ),
            Span::styled("█", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "Press Enter to connect, Esc to go back",
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .block(
        Block::default()
            .title(format!(" {} ", title))
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

/// Render realm detail screen
pub fn render_detail(frame: &mut Frame, area: Rect, app: &App, id: &str) {
    let realm = app.realms.iter().find(|r| r.id == id);

    let content = if let Some(r) = realm {
        Paragraph::new(vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("Realm: ", Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(&r.name),
            ]),
            Line::from(""),
            Line::from(format!("ID: {}", r.id)),
            Line::from(format!("Connection: {}", r.connection_type)),
            Line::from(format!("Address: {}", r.address)),
            Line::from(""),
            Line::from(vec![
                Span::raw("Status: "),
                Span::styled(
                    r.status_display(),
                    Style::default().fg(if r.connected { Color::Green } else { Color::Red }),
                ),
            ]),
            Line::from(""),
            Line::from(Span::styled("Resource Limits:", Style::default().add_modifier(Modifier::BOLD))),
            Line::from(format!("  {}", r.resource_summary())),
            Line::from(""),
            Line::from(format!(
                "Egress Allowed: {}",
                if r.egress_allowed { "Yes" } else { "No" }
            )),
            Line::from(""),
            Line::from(Span::styled(
                "Press 'd' to disconnect, Esc to go back",
                Style::default().fg(Color::DarkGray),
            )),
        ])
    } else {
        Paragraph::new("Realm not found")
    };

    let widget = content
        .block(
            Block::default()
                .title(" Realm Details ")
                .borders(Borders::ALL),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}
