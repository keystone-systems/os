#![allow(dead_code)]
// Clippy lint groups
#![warn(clippy::correctness)]
#![warn(clippy::suspicious)]
#![warn(clippy::complexity)]
#![warn(clippy::perf)]
#![warn(clippy::style)]
// clippy::cargo omitted — flags transitive duplicate deps we don't control
// cognitive_complexity configured via clippy.toml (threshold = 15)
#![warn(clippy::cognitive_complexity)]

pub mod action;
pub mod app;
pub mod cli;
pub mod cmd;
pub mod component;
pub mod components;
pub mod config;
pub mod disk;
pub mod github;
pub mod nix;
pub mod platform;
pub mod repo;
pub mod ssh_keys;
pub mod system;
pub mod template;
pub mod theme;
pub mod time;
pub mod tui;
pub mod widgets;
