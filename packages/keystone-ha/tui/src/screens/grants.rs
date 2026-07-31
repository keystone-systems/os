//! Grant management screens
//!
//! Screens for creating, viewing, and revoking grants.

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

use crate::app::{App, GrantStep};

/// Render the grant list screen
pub fn render_list(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Instructions
            Constraint::Min(5),    // List
        ])
        .split(area);

    // Instructions
    let instructions = Paragraph::new("Press 'c' or 'n' to create a new grant")
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    frame.render_widget(instructions, chunks[0]);

    if app.grants.is_empty() {
        // Empty state
        let empty = Paragraph::new(vec![
            Line::from(""),
            Line::from("No grants found"),
            Line::from(""),
            Line::from("Create a grant to allow another realm to use your resources"),
        ])
        .style(Style::default().fg(Color::Gray))
        .block(
            Block::default()
                .title(" Grants ")
                .borders(Borders::ALL),
        )
        .alignment(Alignment::Center);
        frame.render_widget(empty, chunks[1]);
    } else {
        // Grant list
        let items: Vec<ListItem> = app
            .grants
            .iter()
            .map(|g| {
                let status_color = match g.status.as_ref().map(|s| &s.phase) {
                    Some(crate::types::GrantPhase::Active) => Color::Green,
                    Some(crate::types::GrantPhase::Pending) => Color::Yellow,
                    Some(crate::types::GrantPhase::Revoked) => Color::Red,
                    _ => Color::Gray,
                };

                ListItem::new(Line::from(vec![
                    Span::raw(format!("{} ", g.name())),
                    Span::styled("→ ", Style::default().fg(Color::DarkGray)),
                    Span::raw(&g.spec.grantee_realm),
                    Span::raw(" "),
                    Span::styled(
                        format!(
                            "[{}]",
                            g.status
                                .as_ref()
                                .map(|s| s.phase.to_string())
                                .unwrap_or_else(|| "Unknown".to_string())
                        ),
                        Style::default().fg(status_color),
                    ),
                ]))
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .title(format!(" Grants ({}) ", app.grants.len()))
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

/// Render the grant creation wizard
pub fn render_create(frame: &mut Frame, area: Rect, app: &App, step: &GrantStep) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Progress
            Constraint::Min(10),   // Form
        ])
        .split(area);

    // Progress indicator
    let steps = ["Grantee", "Resources", "Network", "Confirm"];
    let current_step = match step {
        GrantStep::Grantee => 0,
        GrantStep::Resources => 1,
        GrantStep::Network => 2,
        GrantStep::Confirm => 3,
    };

    let progress_text: Vec<Span> = steps
        .iter()
        .enumerate()
        .flat_map(|(i, s)| {
            let style = if i == current_step {
                Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
            } else if i < current_step {
                Style::default().fg(Color::Green)
            } else {
                Style::default().fg(Color::DarkGray)
            };
            vec![
                Span::styled(format!(" {} ", s), style),
                if i < steps.len() - 1 {
                    Span::styled(" → ", Style::default().fg(Color::DarkGray))
                } else {
                    Span::raw("")
                },
            ]
        })
        .collect();

    let progress = Paragraph::new(Line::from(progress_text))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
    frame.render_widget(progress, chunks[0]);

    // Step-specific content
    match step {
        GrantStep::Grantee => render_grantee_step(frame, chunks[1], app),
        GrantStep::Resources => render_resources_step(frame, chunks[1], app),
        GrantStep::Network => render_network_step(frame, chunks[1], app),
        GrantStep::Confirm => render_confirm_step(frame, chunks[1], app),
    }
}

fn render_grantee_step(frame: &mut Frame, area: Rect, app: &App) {
    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from("Enter the realm identifier of the entity you want to grant access to:"),
        Line::from(""),
        Line::from(vec![
            Span::raw("Grantee Realm: "),
            Span::styled(
                if app.grant_form.grantee_realm.is_empty() {
                    "<enter realm ID or domain>"
                } else {
                    &app.grant_form.grantee_realm
                },
                Style::default().fg(if app.grant_form.grantee_realm.is_empty() {
                    Color::DarkGray
                } else {
                    Color::White
                }),
            ),
            Span::styled("█", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "Examples: alice-home.ts.net, bob.headscale.example.com",
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .block(
        Block::default()
            .title(" Step 1: Select Grantee ")
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

fn render_resources_step(frame: &mut Frame, area: Rect, app: &App) {
    let fields = [
        ("CPU Requests", &app.grant_form.requests_cpu, "e.g., 2"),
        ("Memory Requests", &app.grant_form.requests_memory, "e.g., 4Gi"),
        ("CPU Limits", &app.grant_form.limits_cpu, "e.g., 4"),
        ("Memory Limits", &app.grant_form.limits_memory, "e.g., 8Gi"),
        ("Storage", &app.grant_form.requests_storage, "e.g., 100Gi"),
    ];

    let lines: Vec<Line> = fields
        .iter()
        .enumerate()
        .flat_map(|(i, (label, value, hint))| {
            let is_active = i == app.form_field;
            vec![
                Line::from(vec![
                    Span::styled(
                        format!("{}: ", label),
                        Style::default().fg(if is_active { Color::Cyan } else { Color::White }),
                    ),
                    Span::styled(
                        if value.is_empty() { hint.to_string() } else { value.to_string() },
                        Style::default().fg(if value.is_empty() {
                            Color::DarkGray
                        } else {
                            Color::White
                        }),
                    ),
                    if is_active {
                        Span::styled("█", Style::default().fg(Color::Cyan))
                    } else {
                        Span::raw("")
                    },
                ]),
                Line::from(""),
            ]
        })
        .collect();

    let content = Paragraph::new(lines)
        .block(
            Block::default()
                .title(" Step 2: Resource Limits ")
                .borders(Borders::ALL),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

fn render_network_step(frame: &mut Frame, area: Rect, app: &App) {
    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from("Configure network policy for granted workloads:"),
        Line::from(""),
        Line::from(vec![
            Span::raw("Allow Egress: "),
            Span::styled(
                if app.grant_form.egress_allowed { "[X] Yes" } else { "[ ] No" },
                Style::default().fg(if app.form_field == 0 {
                    Color::Cyan
                } else {
                    Color::White
                }),
            ),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "Note: If egress is disabled, workloads can only communicate back to the requesting realm",
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .block(
        Block::default()
            .title(" Step 3: Network Policy ")
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

fn render_confirm_step(frame: &mut Frame, area: Rect, app: &App) {
    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled("Review Grant Configuration:", Style::default().add_modifier(Modifier::BOLD))),
        Line::from(""),
        Line::from(format!("Grantee: {}", app.grant_form.grantee_realm)),
        Line::from(""),
        Line::from("Resources:"),
        Line::from(format!("  CPU: {} / {}", app.grant_form.requests_cpu, app.grant_form.limits_cpu)),
        Line::from(format!("  Memory: {} / {}", app.grant_form.requests_memory, app.grant_form.limits_memory)),
        Line::from(format!("  Storage: {}", app.grant_form.requests_storage)),
        Line::from(""),
        Line::from(format!("Egress Allowed: {}", if app.grant_form.egress_allowed { "Yes" } else { "No" })),
        Line::from(""),
        Line::from(Span::styled("Press Enter to create grant, Esc to cancel", Style::default().fg(Color::Yellow))),
    ])
    .block(
        Block::default()
            .title(" Step 4: Confirm ")
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

/// Render grant detail screen
pub fn render_detail(frame: &mut Frame, area: Rect, app: &App, id: &str) {
    let grant = app.grants.iter().find(|g| g.name() == id);

    let content = if let Some(g) = grant {
        let status = g.status.as_ref();
        Paragraph::new(vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("Grant: ", Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(g.name()),
            ]),
            Line::from(""),
            Line::from(format!("Grantor: {}", g.spec.grantor_realm)),
            Line::from(format!("Grantee: {}", g.spec.grantee_realm)),
            Line::from(""),
            Line::from(Span::styled("Resources:", Style::default().add_modifier(Modifier::BOLD))),
            Line::from(format!("  {}", g.resource_summary())),
            Line::from(""),
            Line::from(format!(
                "Egress Allowed: {}",
                if g.spec.network_policy.egress_allowed { "Yes" } else { "No" }
            )),
            Line::from(""),
            Line::from(vec![
                Span::raw("Status: "),
                Span::styled(
                    status.map(|s| s.phase.to_string()).unwrap_or_else(|| "Unknown".to_string()),
                    Style::default().fg(match status.map(|s| &s.phase) {
                        Some(crate::types::GrantPhase::Active) => Color::Green,
                        Some(crate::types::GrantPhase::Pending) => Color::Yellow,
                        _ => Color::Gray,
                    }),
                ),
            ]),
            Line::from(""),
            Line::from(Span::styled("Press 'r' to revoke, Esc to go back", Style::default().fg(Color::DarkGray))),
        ])
    } else {
        Paragraph::new("Grant not found")
    };

    let widget = content
        .block(
            Block::default()
                .title(" Grant Details ")
                .borders(Borders::ALL),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}
