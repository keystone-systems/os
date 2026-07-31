//! Kubernetes client module
//!
//! Provides client setup and CRUD operations for Keystone CRDs.

mod client;
mod operations;

pub use client::KubeClient;
pub use operations::*;
