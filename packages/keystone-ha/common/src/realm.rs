use kube::CustomResource;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Connection method used
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ConnectionType {
    /// Connected via Tailscale
    Tailscale,
    /// Connected via Headscale
    Headscale,
    /// Connected via direct token exchange
    #[default]
    Token,
}

impl std::fmt::Display for ConnectionType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConnectionType::Tailscale => write!(f, "Tailscale"),
            ConnectionType::Headscale => write!(f, "Headscale"),
            ConnectionType::Token => write!(f, "Token"),
        }
    }
}

/// Resource usage stats
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct RealmResourceUsage {
    pub cpu: Option<String>,
    pub memory: Option<String>,
    pub storage: Option<String>,
}

/// Realm specification
#[derive(CustomResource, Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
#[kube(group = "keystone.io", version = "v1alpha1", kind = "Realm", namespaced)]
#[kube(status = "RealmStatus")]
#[serde(rename_all = "camelCase")]
pub struct RealmSpec {
    pub identity: String,
    pub connection_type: ConnectionType,
    pub trust_level: Option<String>,
}

/// Realm status
#[derive(Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RealmStatus {
    #[serde(default)]
    pub phase: RealmPhase,
    
    pub message: Option<String>,
    pub last_seen: Option<String>,
    pub current_usage: Option<RealmResourceUsage>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub enum RealmPhase {
    #[default]
    Unknown,
    Connecting,
    Connected,
    Disconnected,
    Error,
}

impl std::fmt::Display for RealmPhase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RealmPhase::Unknown => write!(f, "Unknown"),
            RealmPhase::Connecting => write!(f, "Connecting"),
            RealmPhase::Connected => write!(f, "Connected"),
            RealmPhase::Disconnected => write!(f, "Disconnected"),
            RealmPhase::Error => write!(f, "Error"),
        }
    }
}
