//! UI rendering module
//!
//! This module dispatches rendering to screen-specific functions
//! and provides shared UI utilities like headers and status bars.

use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Clear, Paragraph, Wrap},
};

use crate::app::{App, Screen};
use crate::screens;

/// Main render function - dispatches to screen-specific renderers
pub fn render(frame: &mut Frame, app: &App) {
    // Create main layout with header and content
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Header
            Constraint::Min(1),    // Content
            Constraint::Length(3), // Status bar
        ])
        .split(frame.area());

    // Render header
    render_header(frame, chunks[0], app);

    // Render screen content
    match &app.screen {
        Screen::Home => screens::home::render(frame, chunks[1], app),
        Screen::GrantList => screens::grants::render_list(frame, chunks[1], app),
        Screen::GrantCreate { step } => screens::grants::render_create(frame, chunks[1], app, step),
        Screen::GrantDetail { id } => screens::grants::render_detail(frame, chunks[1], app, id),
        Screen::RealmList => screens::realms::render_list(frame, chunks[1], app),
        Screen::RealmConnect { method } => {
            screens::realms::render_connect(frame, chunks[1], app, method)
        }
        Screen::RealmDetail { id } => screens::realms::render_detail(frame, chunks[1], app, id),
        Screen::WorkloadList => screens::workloads::render_list(frame, chunks[1], app),
        Screen::WorkloadDeploy { step } => {
            screens::workloads::render_deploy(frame, chunks[1], app, step)
        }
        Screen::WorkloadDetail { id } => {
            screens::workloads::render_detail(frame, chunks[1], app, id)
        }
        Screen::SuperEntityList => screens::super_entities::render_list(frame, chunks[1], app),
        Screen::SuperEntityCreate => screens::super_entities::render_create(frame, chunks[1], app),
        Screen::SuperEntityDetail { id } => {
            screens::super_entities::render_detail(frame, chunks[1], app, id)
        }
        Screen::BackupList => screens::backups::render_list(frame, chunks[1], app),
        Screen::BackupVerify { id } => screens::backups::render_verify(frame, chunks[1], app, id),
    }

    // Render status bar
    render_status_bar(frame, chunks[2], app);

    // Render help overlay if active
    if app.show_help {
        render_help_overlay(frame);
    }

    // Render error overlay if present
    if let Some(error) = &app.error {
        render_error_overlay(frame, error);
    }
}

/// Render the application header
fn render_header(frame: &mut Frame, area: Rect, app: &App) {
    let title = match &app.screen {
        Screen::Home => "Keystone Cross-Realm Manager",
        Screen::GrantList => "Grant Management",
        Screen::GrantCreate { .. } => "Create Grant",
        Screen::GrantDetail { .. } => "Grant Details",
        Screen::RealmList => "Connected Realms",
        Screen::RealmConnect { .. } => "Connect to Realm",
        Screen::RealmDetail { .. } => "Realm Details",
        Screen::WorkloadList => "Workloads",
        Screen::WorkloadDeploy { .. } => "Deploy Workload",
        Screen::WorkloadDetail { .. } => "Workload Details",
        Screen::SuperEntityList => "Super Entities",
        Screen::SuperEntityCreate => "Create Super Entity",
        Screen::SuperEntityDetail { .. } => "Super Entity Details",
        Screen::BackupList => "Backup Status",
        Screen::BackupVerify { .. } => "Verify Backup",
    };

    let connection_status = if app.connected {
        " [K8s: Connected]"
    } else {
        " [K8s: Disconnected]"
    };

    let header_text = format!("{}{}", title, connection_status);

    let header = Paragraph::new(header_text)
        .style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        )
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan)),
        )
        .alignment(Alignment::Center);

    frame.render_widget(header, area);
}

/// Render the status bar with keyboard hints
fn render_status_bar(frame: &mut Frame, area: Rect, app: &App) {
    let hints = match &app.screen {
        Screen::Home => "↑↓/jk: Navigate | Enter: Select | q: Quit | ?: Help",
        Screen::GrantCreate { .. } | Screen::WorkloadDeploy { .. } => {
            "Tab: Next field | Esc: Cancel | Enter: Confirm"
        }
        Screen::RealmConnect { .. } | Screen::SuperEntityCreate => {
            "Tab: Next field | Esc: Cancel | Enter: Submit"
        }
        _ => "↑↓/jk: Navigate | Enter: Select | Esc: Back | q: Quit | ?: Help",
    };

    let loading_indicator = if app.loading { " [Loading...]" } else { "" };

    let status = Paragraph::new(format!("{}{}", hints, loading_indicator))
        .style(Style::default().fg(Color::DarkGray))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        )
        .alignment(Alignment::Center);

    frame.render_widget(status, area);
}

/// Render help overlay
fn render_help_overlay(frame: &mut Frame) {
    let area = centered_rect(60, 70, frame.area());

    let help_text = r#"
    Keyboard Shortcuts
    ──────────────────

    Navigation
    ↑ / k      Move up
    ↓ / j      Move down
    Enter      Select / Confirm
    Esc        Go back / Cancel
    1-5        Quick jump (from home)

    Forms
    Tab        Next field
    Shift+Tab  Previous field
    Enter      Submit

    General
    ?          Toggle help
    q          Quit

    Press any key to close
    "#;

    let help = Paragraph::new(help_text)
        .style(Style::default().fg(Color::White))
        .block(
            Block::default()
                .title(" Help ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .style(Style::default().bg(Color::Black)),
        )
        .wrap(Wrap { trim: false });

    frame.render_widget(Clear, area);
    frame.render_widget(help, area);
}

/// Render error overlay
fn render_error_overlay(frame: &mut Frame, error: &str) {
    let area = centered_rect(50, 30, frame.area());

    let error_text = format!("\n{}\n\nPress Enter to dismiss", error);

    let error_widget = Paragraph::new(error_text)
        .style(Style::default().fg(Color::White))
        .block(
            Block::default()
                .title(" Error ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Red))
                .style(Style::default().bg(Color::Black)),
        )
        .wrap(Wrap { trim: true })
        .alignment(Alignment::Center);

    frame.render_widget(Clear, area);
    frame.render_widget(error_widget, area);
}

/// Create a centered rectangle with percentage width and height
pub fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}
