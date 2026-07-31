use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Backup information
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct Backup {
    pub id: String,
    pub name: String,
    pub backup_type: BackupType,
    pub copy_count: u32,
    pub locations: Vec<String>,
    pub last_verified: Option<String>,
    pub status: BackupPhase,
    pub size: Option<String>,
    pub created_at: Option<String>,
}

/// Type of backup
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub enum BackupType {
    #[default]
    Local,
    SuperEntity,
    Remote,
}

impl std::fmt::Display for BackupType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BackupType::Local => write!(f, "Local"),
            BackupType::SuperEntity => write!(f, "Super Entity"),
            BackupType::Remote => write!(f, "Remote"),
        }
    }
}

/// Backup verification status
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub enum BackupPhase {
    #[default]
    Unknown,
    Healthy,
    Degraded,
    Verifying,
    Failed,
}

impl std::fmt::Display for BackupPhase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BackupPhase::Unknown => write!(f, "Unknown"),
            BackupPhase::Healthy => write!(f, "Healthy"),
            BackupPhase::Degraded => write!(f, "Degraded"),
            BackupPhase::Verifying => write!(f, "Verifying"),
            BackupPhase::Failed => write!(f, "Failed"),
        }
    }
}

/// Backup specification
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct BackupSpec {
    pub name: String,
    pub source_path: String,
    pub target_realms: Vec<String>,
    pub replication_factor: u32,
}

/// Backup status
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct BackupStatus {
    pub phase: BackupPhase,
    pub copy_count: u32,
    pub locations: Vec<String>,
    pub last_verified: Option<String>,
    pub message: Option<String>,
}
