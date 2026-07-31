//! Centralized theme — semantic color palette for the TUI.
//!
//! Uses ANSI named colors which inherit the terminal's 16-color palette.
//! On Keystone desktop, Ghostty's theme (e.g., royal-green) maps these
//! to the correct hex values automatically. Theme switches via
//! `keystone-theme-switch` reload Ghostty and the TUI colors update
//! instantly with zero code changes.

use ratatui::style::{Color, Modifier, Style};

/// Semantic color palette for the TUI.
pub struct Theme {
    /// Selected items, success states, positive diffs.
    pub active: Color,
    /// Muted text, borders, disabled items, help text.
    pub inactive: Color,
    /// Normal body text.
    pub text: Color,
    /// Focused input, attention-drawing elements.
    pub accent: Color,
    /// Error states, negative diffs, failure messages.
    pub error: Color,
    /// Warning banners, caution messages.
    pub warning: Color,
    /// Warning banner background.
    pub warning_bg: Color,
    /// File paths, URLs, data values.
    pub path: Color,
    /// Roles, categories, metadata badges.
    pub metadata: Color,
}

impl Theme {
    /// Active/selected style (bold).
    pub fn active_style(&self) -> Style {
        Style::default()
            .fg(self.active)
            .add_modifier(Modifier::BOLD)
    }

    /// Inactive/muted style.
    pub fn inactive_style(&self) -> Style {
        Style::default().fg(self.inactive)
    }

    /// Title style (bold + accent).
    pub fn title_style(&self) -> Style {
        Style::default()
            .fg(self.accent)
            .add_modifier(Modifier::BOLD)
    }

    /// Error style.
    pub fn error_style(&self) -> Style {
        Style::default().fg(self.error)
    }

    /// Warning banner style (foreground).
    pub fn warning_style(&self) -> Style {
        Style::default().fg(self.warning)
    }

    /// Warning banner label style (inverted).
    pub fn warning_label_style(&self) -> Style {
        Style::default().fg(self.warning_bg).bg(self.warning)
    }
}

/// Default theme using ANSI named colors.
///
/// These map to the terminal's 16-color palette. On Keystone desktop,
/// Ghostty renders them through the active theme (royal-green, tokyo-night,
/// etc.). On plain terminals, they use the terminal's built-in palette.
pub fn default() -> Theme {
    Theme {
        active: Color::Green,
        inactive: Color::DarkGray,
        text: Color::Reset,
        accent: Color::Yellow,
        error: Color::Red,
        warning: Color::Yellow,
        warning_bg: Color::Black,
        path: Color::Cyan,
        metadata: Color::Magenta,
    }
}
