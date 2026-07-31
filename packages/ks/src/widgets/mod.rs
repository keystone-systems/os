//! Common UI components for the ks.
//!
//! This module provides reusable widgets and rendering utilities
//! used across different screens.

mod input;
mod menu;
pub mod shell;
pub mod sidebar;

pub use input::TextInput;
#[allow(unused_imports)]
pub use menu::SelectMenu;
