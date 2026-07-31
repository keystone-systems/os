//! Input handling module
//!
//! Handles keyboard input and dispatches actions based on the current screen.

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::app::{App, ConnectionMethod, DeployStep, GrantStep, Screen};

/// Handle a keyboard event
pub async fn handle_key(app: &mut App, key: KeyEvent) {
    // If help is shown, any key closes it
    if app.show_help {
        app.show_help = false;
        return;
    }

    // If error is shown, Enter dismisses it
    if app.error.is_some() {
        if key.code == KeyCode::Enter {
            app.clear_error();
        }
        return;
    }

    // Global keys that work on any screen
    match key.code {
        KeyCode::Char('q') if !is_form_screen(&app.screen) => {
            app.should_quit = true;
            return;
        }
        KeyCode::Char('?') => {
            app.toggle_help();
            return;
        }
        _ => {}
    }

    // Screen-specific input handling
    match &app.screen {
        Screen::Home => handle_home_input(app, key),
        Screen::GrantList => handle_list_input(app, key, ListContext::Grants),
        Screen::GrantCreate { step } => handle_grant_create_input(app, key, step.clone()),
        Screen::GrantDetail { .. } => handle_detail_input(app, key),
        Screen::RealmList => handle_list_input(app, key, ListContext::Realms),
        Screen::RealmConnect { method } => handle_realm_connect_input(app, key, method.clone()),
        Screen::RealmDetail { .. } => handle_detail_input(app, key),
        Screen::WorkloadList => handle_list_input(app, key, ListContext::Workloads),
        Screen::WorkloadDeploy { step } => handle_workload_deploy_input(app, key, step.clone()),
        Screen::WorkloadDetail { .. } => handle_detail_input(app, key),
        Screen::SuperEntityList => handle_list_input(app, key, ListContext::SuperEntities),
        Screen::SuperEntityCreate => handle_form_input(app, key, 3), // name, purpose, members
        Screen::SuperEntityDetail { .. } => handle_detail_input(app, key),
        Screen::BackupList => handle_list_input(app, key, ListContext::Backups),
        Screen::BackupVerify { .. } => handle_detail_input(app, key),
    }
}

/// Check if current screen is a form that needs text input
fn is_form_screen(screen: &Screen) -> bool {
    matches!(
        screen,
        Screen::GrantCreate { .. }
            | Screen::RealmConnect { .. }
            | Screen::WorkloadDeploy { .. }
            | Screen::SuperEntityCreate
    )
}

/// Context for list navigation
enum ListContext {
    Grants,
    Realms,
    Workloads,
    SuperEntities,
    Backups,
}

/// Handle input on the home screen
fn handle_home_input(app: &mut App, key: KeyEvent) {
    let max = app.current_list_len();

    match key.code {
        KeyCode::Up | KeyCode::Char('k') => app.select_prev(max),
        KeyCode::Down | KeyCode::Char('j') => app.select_next(max),
        KeyCode::Char('1') => app.navigate_to(Screen::GrantList),
        KeyCode::Char('2') => app.navigate_to(Screen::RealmList),
        KeyCode::Char('3') => app.navigate_to(Screen::WorkloadList),
        KeyCode::Char('4') => app.navigate_to(Screen::SuperEntityList),
        KeyCode::Char('5') => app.navigate_to(Screen::BackupList),
        KeyCode::Enter => match app.list_index {
            0 => app.navigate_to(Screen::GrantList),
            1 => app.navigate_to(Screen::RealmList),
            2 => app.navigate_to(Screen::WorkloadList),
            3 => app.navigate_to(Screen::SuperEntityList),
            4 => app.navigate_to(Screen::BackupList),
            _ => {}
        },
        _ => {}
    }
}

/// Handle input on list screens
fn handle_list_input(app: &mut App, key: KeyEvent, context: ListContext) {
    let max = app.current_list_len();

    match key.code {
        KeyCode::Up | KeyCode::Char('k') => app.select_prev(max),
        KeyCode::Down | KeyCode::Char('j') => app.select_next(max),
        KeyCode::Esc => app.go_back(),
        KeyCode::Char('c') | KeyCode::Char('n') => {
            // Create new item
            match context {
                ListContext::Grants => app.navigate_to(Screen::GrantCreate {
                    step: GrantStep::Grantee,
                }),
                ListContext::Realms => app.navigate_to(Screen::RealmConnect { method: None }),
                ListContext::Workloads => app.navigate_to(Screen::WorkloadDeploy {
                    step: DeployStep::SelectRealm,
                }),
                ListContext::SuperEntities => app.navigate_to(Screen::SuperEntityCreate),
                ListContext::Backups => {} // No create for backups
            }
        }
        KeyCode::Enter => {
            if max > 0 {
                match context {
                    ListContext::Grants => {
                        if let Some(grant) = app.grants.get(app.list_index) {
                            app.navigate_to(Screen::GrantDetail {
                                id: grant.name(),
                            });
                        }
                    }
                    ListContext::Realms => {
                        if let Some(realm) = app.realms.get(app.list_index) {
                            app.navigate_to(Screen::RealmDetail {
                                id: realm.id.clone(),
                            });
                        }
                    }
                    ListContext::Workloads => {
                        if let Some(workload) = app.workloads.get(app.list_index) {
                            app.navigate_to(Screen::WorkloadDetail {
                                id: workload.id.clone(),
                            });
                        }
                    }
                    ListContext::SuperEntities => {
                        if let Some(entity) = app.super_entities.get(app.list_index) {
                            app.navigate_to(Screen::SuperEntityDetail {
                                id: entity.name(),
                            });
                        }
                    }
                    ListContext::Backups => {
                        if let Some(backup) = app.backups.get(app.list_index) {
                            app.navigate_to(Screen::BackupVerify {
                                id: backup.id.clone(),
                            });
                        }
                    }
                }
            }
        }
        _ => {}
    }
}

/// Handle input on detail screens
fn handle_detail_input(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc | KeyCode::Char('b') => app.go_back(),
        _ => {}
    }
}

/// Handle input during grant creation
fn handle_grant_create_input(app: &mut App, key: KeyEvent, step: GrantStep) {
    match key.code {
        KeyCode::Esc => app.go_back(),
        KeyCode::Tab => {
            // Advance form field or step
            let max_fields = match step {
                GrantStep::Grantee => 1,
                GrantStep::Resources => 5,
                GrantStep::Network => 2,
                GrantStep::Confirm => 0,
            };
            if app.form_field < max_fields - 1 {
                app.next_field(max_fields);
            }
        }
        KeyCode::BackTab => app.prev_field(),
        KeyCode::Enter => {
            // Move to next step or submit
            let next = match step {
                GrantStep::Grantee => Some(Screen::GrantCreate {
                    step: GrantStep::Resources,
                }),
                GrantStep::Resources => Some(Screen::GrantCreate {
                    step: GrantStep::Network,
                }),
                GrantStep::Network => Some(Screen::GrantCreate {
                    step: GrantStep::Confirm,
                }),
                GrantStep::Confirm => {
                    // TODO: Submit grant creation
                    app.go_back();
                    None
                }
            };
            if let Some(screen) = next {
                app.screen = screen;
                app.form_field = 0;
            }
        }
        KeyCode::Char(c) => {
            app.input_buffer.push(c);
            // Update form field based on current step and field
            update_grant_form(app, &step);
        }
        KeyCode::Backspace => {
            app.input_buffer.pop();
            update_grant_form(app, &step);
        }
        _ => {}
    }
}

/// Update grant form state from input buffer
fn update_grant_form(app: &mut App, step: &GrantStep) {
    match step {
        GrantStep::Grantee => {
            app.grant_form.grantee_realm = app.input_buffer.clone();
        }
        GrantStep::Resources => match app.form_field {
            0 => app.grant_form.requests_cpu = app.input_buffer.clone(),
            1 => app.grant_form.requests_memory = app.input_buffer.clone(),
            2 => app.grant_form.limits_cpu = app.input_buffer.clone(),
            3 => app.grant_form.limits_memory = app.input_buffer.clone(),
            4 => app.grant_form.requests_storage = app.input_buffer.clone(),
            _ => {}
        },
        GrantStep::Network => {
            if app.form_field == 0 {
                // Toggle egress
                app.grant_form.egress_allowed = !app.grant_form.egress_allowed;
            }
        }
        GrantStep::Confirm => {}
    }
}

/// Handle input during realm connection
fn handle_realm_connect_input(app: &mut App, key: KeyEvent, method: Option<ConnectionMethod>) {
    match key.code {
        KeyCode::Esc => {
            if method.is_some() {
                app.screen = Screen::RealmConnect { method: None };
            } else {
                app.go_back();
            }
        }
        KeyCode::Enter => {
            if method.is_none() {
                // Select connection method
                let selected_method = match app.list_index {
                    0 => ConnectionMethod::Tailscale,
                    1 => ConnectionMethod::Headscale,
                    2 => ConnectionMethod::Token,
                    _ => ConnectionMethod::Token,
                };
                app.screen = Screen::RealmConnect {
                    method: Some(selected_method),
                };
                app.list_index = 0;
            } else {
                // Submit connection
                // TODO: Actually connect
                app.go_back();
            }
        }
        KeyCode::Up | KeyCode::Char('k') if method.is_none() => app.select_prev(3),
        KeyCode::Down | KeyCode::Char('j') if method.is_none() => app.select_next(3),
        KeyCode::Char(c) if method.is_some() => {
            app.input_buffer.push(c);
        }
        KeyCode::Backspace if method.is_some() => {
            app.input_buffer.pop();
        }
        _ => {}
    }
}

/// Handle input during workload deployment
fn handle_workload_deploy_input(app: &mut App, key: KeyEvent, step: DeployStep) {
    match key.code {
        KeyCode::Esc => app.go_back(),
        KeyCode::Tab if key.modifiers.contains(KeyModifiers::SHIFT) => app.prev_field(),
        KeyCode::Tab => app.next_field(5),
        KeyCode::Enter => {
            let next = match step {
                DeployStep::SelectRealm => Some(Screen::WorkloadDeploy {
                    step: DeployStep::Configure,
                }),
                DeployStep::Configure => Some(Screen::WorkloadDeploy {
                    step: DeployStep::Review,
                }),
                DeployStep::Review => {
                    // TODO: Submit deployment
                    app.go_back();
                    None
                }
            };
            if let Some(screen) = next {
                app.screen = screen;
                app.form_field = 0;
            }
        }
        KeyCode::Up | KeyCode::Char('k') => app.select_prev(app.realms.len().max(1)),
        KeyCode::Down | KeyCode::Char('j') => app.select_next(app.realms.len().max(1)),
        KeyCode::Char(c) => app.input_buffer.push(c),
        KeyCode::Backspace => {
            app.input_buffer.pop();
        }
        _ => {}
    }
}

/// Generic form input handler
fn handle_form_input(app: &mut App, key: KeyEvent, max_fields: usize) {
    match key.code {
        KeyCode::Esc => app.go_back(),
        KeyCode::Tab if key.modifiers.contains(KeyModifiers::SHIFT) => app.prev_field(),
        KeyCode::Tab => app.next_field(max_fields),
        KeyCode::Enter => {
            // TODO: Submit form
            app.go_back();
        }
        KeyCode::Char(c) => app.input_buffer.push(c),
        KeyCode::Backspace => {
            app.input_buffer.pop();
        }
        _ => {}
    }
}
