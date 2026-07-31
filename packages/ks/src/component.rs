//! Component trait — the canonical ratatui component architecture.
//!
//! Each component owns its state and colocates event handling, state
//! updates, and rendering. Components communicate by returning `Action`
//! values from `update()`.

use anyhow::Result;
use crossterm::event::Event;
use ratatui::layout::Rect;
use ratatui::Frame;

use crate::action::Action;

/// A self-contained UI component with state, input handling, and rendering.
///
/// Follows the ratatui Component Architecture:
/// ```text
/// Event → handle_events() → Action → update() → state change → draw()
/// ```
pub trait Component {
    /// Initialize the component (called once after construction).
    fn init(&mut self) -> Result<()> {
        Ok(())
    }

    /// Handle a terminal event and optionally produce an action.
    fn handle_events(&mut self, event: &Event) -> Result<Option<Action>> {
        let _ = event;
        Ok(None)
    }

    /// Process an action and optionally produce a follow-up action.
    ///
    /// Return `Some(Action::NavigateTo(...))` for screen transitions.
    /// Return `Some(Action::Quit)` to exit.
    /// Return `None` to stay on the current screen.
    fn update(&mut self, action: &Action) -> Result<Option<Action>> {
        let _ = action;
        Ok(None)
    }

    /// Render the component to the frame.
    fn draw(&mut self, frame: &mut Frame, area: Rect) -> Result<()>;
}
