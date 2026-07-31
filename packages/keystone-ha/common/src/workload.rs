use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// A deployed workload
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct Workload {
    pub id: String,
    pub name: String,
    pub image: String,
    pub target_realm: String,
    pub status: WorkloadPhase,
    pub resources: WorkloadResources,
    pub ports: Vec<PortMapping>,
    pub env: Vec<EnvVar>,
    pub created_at: Option<String>,
    pub started_at: Option<String>,
}

impl Workload {
    /// Get resource summary
    pub fn resource_summary(&self) -> String {
        let mut parts = Vec::new();
        if let Some(cpu) = &self.resources.cpu {
            parts.push(format!("CPU: {}", cpu));
        }
        if let Some(mem) = &self.resources.memory {
            parts.push(format!("Mem: {}", mem));
        }
        if parts.is_empty() {
            "Default resources".to_string()
        } else {
            parts.join(", ")
        }
    }
}

/// Workload lifecycle phases
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub enum WorkloadPhase {
    #[default]
    Pending,
    Creating,
    Running,
    Stopped,
    Failed,
    Terminating,
}

impl std::fmt::Display for WorkloadPhase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WorkloadPhase::Pending => write!(f, "Pending"),
            WorkloadPhase::Creating => write!(f, "Creating"),
            WorkloadPhase::Running => write!(f, "Running"),
            WorkloadPhase::Stopped => write!(f, "Stopped"),
            WorkloadPhase::Failed => write!(f, "Failed"),
            WorkloadPhase::Terminating => write!(f, "Terminating"),
        }
    }
}

/// Resource requests for a workload
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct WorkloadResources {
    pub cpu: Option<String>,
    pub memory: Option<String>,
    pub storage: Option<String>,
}

/// Port mapping for a workload
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct PortMapping {
    pub container_port: u16,
    pub host_port: Option<u16>,
    pub protocol: String,
}

/// Environment variable
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct EnvVar {
    pub name: String,
    pub value: String,
}

/// Workload specification (for CRD)
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct WorkloadSpec {
    pub name: String,
    pub image: String,
    pub target_realm: String,
    pub resources: WorkloadResources,
    pub ports: Vec<PortMapping>,
    pub env: Vec<EnvVar>,
}

/// Workload status
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub struct WorkloadStatus {
    pub phase: WorkloadPhase,
    pub message: Option<String>,
    pub started_at: Option<String>,
}