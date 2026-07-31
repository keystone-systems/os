//! Realm type definition
//!
//! A realm represents a distinct identity boundary - a person, household,
//! organization, or community that owns and controls their own Keystone infrastructure.

use serde::{Deserialize, Serialize};
pub use keystone_ha_defs::realm::{ConnectionType, RealmResourceUsage};

pub type RealmResourceLimits = RealmResourceUsage;

/// Connected realm information
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Realm {
    /// Unique realm identifier
    pub id: String,

    /// Human-readable realm name
    pub name: String,

    /// Connection method used
    pub connection_type: ConnectionType,

    /// Address used to connect (domain or IP)
    pub address: String,

    /// Whether the realm is currently reachable
    pub connected: bool,

    /// Grantor identity (who granted us access)
    pub grantor: Option<String>,

    /// Resource limits from grant
    pub resource_limits: Option<RealmResourceLimits>,

    /// Current resource usage
    pub current_usage: Option<RealmResourceUsage>,

    /// Network policy (egress status)
    pub egress_allowed: bool,

    /// When we connected to this realm
    pub connected_at: Option<String>,
}

impl Realm {
    /// Get display status
    pub fn status_display(&self) -> &str {
        if self.connected {
            "Connected"
        } else {
            "Disconnected"
        }
    }

    /// Get resource summary
    pub fn resource_summary(&self) -> String {
        if let Some(limits) = &self.resource_limits {
            let mut parts = Vec::new();
            if let Some(cpu) = &limits.cpu {
                parts.push(format!("CPU: {}", cpu));
            }
            if let Some(mem) = &limits.memory {
                parts.push(format!("Mem: {}", mem));
            }
            if parts.is_empty() {
                "No limits".to_string()
            } else {
                parts.join(", ")
            }
        } else {
            "No limits".to_string()
        }
    }
}