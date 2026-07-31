//! Workload management screens
//!
//! Screens for deploying and viewing workloads.

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

use crate::app::{App, DeployStep};
use crate::types::WorkloadPhase;

/// Render the workload list screen
pub fn render_list(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Instructions
            Constraint::Min(5),    // List
        ])
        .split(area);

    // Instructions
    let instructions = Paragraph::new("Press 'c' or 'n' to deploy a new workload")
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    frame.render_widget(instructions, chunks[0]);

    if app.workloads.is_empty() {
        // Empty state
        let empty = Paragraph::new(vec![
            Line::from(""),
            Line::from("No workloads deployed"),
            Line::from(""),
            Line::from("Deploy a workload to a local or remote realm"),
        ])
        .style(Style::default().fg(Color::Gray))
        .block(
            Block::default()
                .title(" Workloads ")
                .borders(Borders::ALL),
        )
        .alignment(Alignment::Center);
        frame.render_widget(empty, chunks[1]);
    } else {
        // Workload list
        let items: Vec<ListItem> = app
            .workloads
            .iter()
            .map(|w| {
                let status_color = match w.status {
                    WorkloadPhase::Running => Color::Green,
                    WorkloadPhase::Pending | WorkloadPhase::Creating => Color::Yellow,
                    WorkloadPhase::Failed => Color::Red,
                    _ => Color::Gray,
                };

                ListItem::new(Line::from(vec![
                    Span::raw(format!("{} ", w.name)),
                    Span::styled(
                        format!("@ {}", w.target_realm),
                        Style::default().fg(Color::DarkGray),
                    ),
                    Span::raw(" "),
                    Span::styled(
                        format!("[{}]", w.status),
                        Style::default().fg(status_color),
                    ),
                ]))
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .title(format!(" Workloads ({}) ", app.workloads.len()))
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

/// Render the workload deployment wizard
pub fn render_deploy(frame: &mut Frame, area: Rect, app: &App, step: &DeployStep) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Progress
            Constraint::Min(10),   // Form
        ])
        .split(area);

    // Progress indicator
    let steps = ["Select Realm", "Configure", "Review"];
    let current_step = match step {
        DeployStep::SelectRealm => 0,
        DeployStep::Configure => 1,
        DeployStep::Review => 2,
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
        DeployStep::SelectRealm => render_select_realm(frame, chunks[1], app),
        DeployStep::Configure => render_configure(frame, chunks[1], app),
        DeployStep::Review => render_review(frame, chunks[1], app),
    }
}

fn render_select_realm(frame: &mut Frame, area: Rect, app: &App) {
    if app.realms.is_empty() {
        let content = Paragraph::new(vec![
            Line::from(""),
            Line::from("No realms available for deployment"),
            Line::from(""),
            Line::from("Connect to a realm first to deploy workloads there"),
        ])
        .style(Style::default().fg(Color::Gray))
        .block(
            Block::default()
                .title(" Step 1: Select Target Realm ")
                .borders(Borders::ALL),
        )
        .alignment(Alignment::Center);
        frame.render_widget(content, area);
    } else {
        let items: Vec<ListItem> = app
            .realms
            .iter()
            .map(|r| {
                ListItem::new(Line::from(vec![
                    Span::raw(&r.name),
                    Span::raw(" "),
                    Span::styled(
                        format!("({})", r.resource_summary()),
                        Style::default().fg(Color::DarkGray),
                    ),
                ]))
            })
            .collect();

        let list = List::new(items)
            .block(
                Block::default()
                    .title(" Step 1: Select Target Realm ")
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
}

fn render_configure(frame: &mut Frame, area: Rect, app: &App) {
    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from(vec![
            Span::styled("Image: ", Style::default().fg(if app.form_field == 0 { Color::Cyan } else { Color::White })),
            Span::raw(if app.input_buffer.is_empty() { "<container image>" } else { &app.input_buffer }),
            if app.form_field == 0 { Span::styled("█", Style::default().fg(Color::Cyan)) } else { Span::raw("") },
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("CPU: ", Style::default().fg(if app.form_field == 1 { Color::Cyan } else { Color::White })),
            Span::raw("1"),
        ]),
        Line::from(vec![
            Span::styled("Memory: ", Style::default().fg(if app.form_field == 2 { Color::Cyan } else { Color::White })),
            Span::raw("512Mi"),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "Tab to switch fields, Enter to continue",
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .block(
        Block::default()
            .title(" Step 2: Configure Workload ")
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

fn render_review(frame: &mut Frame, area: Rect, _app: &App) {
    let content = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled("Review Deployment:", Style::default().add_modifier(Modifier::BOLD))),
        Line::from(""),
        Line::from("Target Realm: (selected realm)"),
        Line::from("Image: (configured image)"),
        Line::from("Resources: CPU 1, Memory 512Mi"),
        Line::from(""),
        Line::from(Span::styled(
            "Press Enter to deploy, Esc to cancel",
            Style::default().fg(Color::Yellow),
        )),
    ])
    .block(
        Block::default()
            .title(" Step 3: Review & Deploy ")
            .borders(Borders::ALL),
    )
    .wrap(Wrap { trim: true });

    frame.render_widget(content, area);
}

/// Render workload detail screen
pub fn render_detail(frame: &mut Frame, area: Rect, app: &App, id: &str) {
    let workload = app.workloads.iter().find(|w| w.id == id);

    let content = if let Some(w) = workload {
        let status_color = match w.status {
            WorkloadPhase::Running => Color::Green,
            WorkloadPhase::Pending | WorkloadPhase::Creating => Color::Yellow,
            WorkloadPhase::Failed => Color::Red,
            _ => Color::Gray,
        };

        Paragraph::new(vec![
            Line::from(""),
            Line::from(vec![
                Span::styled("Workload: ", Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(&w.name),
            ]),
            Line::from(""),
            Line::from(format!("ID: {}", w.id)),
            Line::from(format!("Image: {}", w.image)),
            Line::from(format!("Target Realm: {}", w.target_realm)),
            Line::from(""),
            Line::from(vec![
                Span::raw("Status: "),
                Span::styled(w.status.to_string(), Style::default().fg(status_color)),
            ]),
            Line::from(""),
            Line::from(Span::styled("Resources:", Style::default().add_modifier(Modifier::BOLD))),
            Line::from(format!("  {}", w.resource_summary())),
            Line::from(""),
            Line::from(Span::styled(
                "Press 's' to stop, 'd' to delete, Esc to go back",
                Style::default().fg(Color::DarkGray),
            )),
        ])
    } else {
        Paragraph::new("Workload not found")
    };

    let widget = content
        .block(
            Block::default()
                .title(" Workload Details ")
                .borders(Borders::ALL),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(widget, area);
}
