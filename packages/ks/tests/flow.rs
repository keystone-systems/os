//! Multi-screen flow integration tests.
//!
//! These tests exercise screen transitions using the Component trait's
//! handle_events(), verifying that the TUI navigates correctly between
//! components via the global Action enum.

use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyEventState, KeyModifiers};

use ks::action::{Action, Screen};
use ks::app::{App, AppScreen};
use ks::components::hosts::HostsScreen;
use ks::nix::HostInfo;

/// Helper to create a key press Event.
fn key_event(code: KeyCode) -> Event {
    Event::Key(KeyEvent {
        code,
        modifiers: KeyModifiers::NONE,
        kind: KeyEventKind::Press,
        state: KeyEventState::NONE,
    })
}

#[test]
fn test_welcome_to_hosts_flow() {
    let mut app = App::new_for_test();
    assert!(matches!(app.current_screen, AppScreen::Welcome(_)));

    // Simulate the welcome flow completing (set_success + confirm)
    if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
        welcome.set_success("Repo imported!".to_string());
    }

    // Press Enter to acknowledge success — should navigate to Hosts
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Enter))
        .unwrap();
    assert!(matches!(action, Some(Action::NavigateTo(Screen::Hosts))));
}

#[test]
fn test_hosts_to_detail_and_back() {
    let hosts = vec![
        HostInfo {
            name: "laptop".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        },
        HostInfo {
            name: "server".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        },
    ];

    let mut app = App::new_for_test();
    app.current_screen = AppScreen::Hosts(HostsScreen::new("test-repo".to_string(), hosts));

    // Press Enter to go to host detail
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Enter))
        .unwrap();
    match action {
        Some(Action::NavigateTo(Screen::HostDetail(host))) => {
            assert_eq!(host.name, "laptop");
            // Manually transition
            app.current_screen =
                AppScreen::HostDetail(ks::components::host_detail::HostDetailScreen::new(*host));
        }
        other => panic!("Expected NavigateTo(HostDetail), got {:?}", other),
    }

    assert!(matches!(app.current_screen, AppScreen::HostDetail(_)));

    // Press Esc to go back
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Esc))
        .unwrap();
    assert!(matches!(action, Some(Action::GoBack)));
}

#[test]
fn test_navigate_hosts_then_select_second() {
    let hosts = vec![
        HostInfo {
            name: "alpha".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        },
        HostInfo {
            name: "beta".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        },
    ];

    let mut app = App::new_for_test();
    app.current_screen = AppScreen::Hosts(HostsScreen::new("repo".to_string(), hosts));

    // Navigate down — internal action, returns None
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Down))
        .unwrap();
    assert!(action.is_none());

    // Press Enter on second host
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Enter))
        .unwrap();
    match action {
        Some(Action::NavigateTo(Screen::HostDetail(host))) => {
            assert_eq!(host.name, "beta");
        }
        other => panic!("Expected NavigateTo(HostDetail(beta)), got {:?}", other),
    }
}

#[test]
fn test_quit_from_any_screen() {
    // Quit from Welcome
    let mut app = App::new_for_test();
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Char('q')))
        .unwrap();
    assert!(matches!(action, Some(Action::Quit)));

    // Quit from Hosts
    let mut app = App::new_for_test();
    app.current_screen = AppScreen::Hosts(HostsScreen::new("repo".to_string(), vec![]));
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Char('q')))
        .unwrap();
    assert!(matches!(action, Some(Action::Quit)));

    // Quit from HostDetail
    let mut app = App::new_for_test();
    app.current_screen = AppScreen::HostDetail(ks::components::host_detail::HostDetailScreen::new(
        HostInfo {
            name: "host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
            metadata: None,
        },
    ));
    let action = app
        .current_screen
        .as_component_mut()
        .unwrap()
        .handle_events(&key_event(KeyCode::Char('q')))
        .unwrap();
    assert!(matches!(action, Some(Action::Quit)));
}

#[tokio::test]
async fn test_navigate_to_host_detail() {
    let mut app = App::new_for_test();
    let host = HostInfo {
        name: "target-host".to_string(),
        system: Some("aarch64-linux".to_string()),
        keystone_modules: vec!["operating-system".to_string()],
        config_files: vec![],
        metadata: None,
    };

    app.navigate_to(Screen::HostDetail(Box::new(host))).await;
    assert!(matches!(app.current_screen, AppScreen::HostDetail(_)));

    if let AppScreen::HostDetail(ref detail) = app.current_screen {
        assert_eq!(detail.host().name, "target-host");
    }
}

#[tokio::test]
async fn test_navigate_to_sets_quit() {
    let app = App::new_for_test();
    assert!(!app.should_quit);
}
