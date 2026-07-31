//! `ks menu ...` — Walker menu provider backend dispatcher.
//!
//! Thin routing layer that forwards each `MenuCommand` variant to its
//! provider module. Kept minimal so future providers (audio, package, main,
//! agent, …) can be added by converting this to a directory module without
//! churning the call sites in `main.rs`.

use std::path::Path;

use anyhow::Result;

use crate::cli::MenuCommand;
use crate::cmd::update_menu;

pub async fn execute(cmd: MenuCommand, flake: Option<&Path>) -> Result<()> {
    match cmd {
        MenuCommand::Update { action } => update_menu::execute(action, flake).await,
    }
}
