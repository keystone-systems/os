use kube::CustomResource;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Resource limits following Kubernetes ResourceQuota pattern
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ResourceLimits {
    #[serde(rename = "requests.cpu", skip_serializing_if = "Option::is_none")]
    pub requests_cpu: Option<String>,

    #[serde(rename = "requests.memory", skip_serializing_if = "Option::is_none")]
    pub requests_memory: Option<String>,

    #[serde(rename = "limits.cpu", skip_serializing_if = "Option::is_none")]
    pub limits_cpu: Option<String>,

    #[serde(rename = "limits.memory", skip_serializing_if = "Option::is_none")]
    pub limits_memory: Option<String>,

    #[serde(rename = "requests.storage", skip_serializing_if = "Option::is_none")]
    pub requests_storage: Option<String>,

    #[serde(
        rename = "requests.nvidia.com/gpu",
        skip_serializing_if = "Option::is_none"
    )]
    pub requests_gpu: Option<i32>,
}

/// Network policy for granted workloads
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NetworkPolicy {
    #[serde(default)]
    pub egress_allowed: bool,

    #[serde(default)]
    pub allowed_destinations: Vec<String>,
}

/// Validity period for a grant
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Validity {
    pub valid_from: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub valid_until: Option<String>,
}

/// Grant specification
#[derive(CustomResource, Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
#[kube(group = "keystone.io", version = "v1alpha1", kind = "Grant", namespaced)]
#[kube(status = "GrantStatus")]
#[serde(rename_all = "camelCase")]
pub struct GrantSpec {
    pub grantor_realm: String,
    pub grantee_realm: String,
    pub hard: ResourceLimits,
    pub network_policy: NetworkPolicy,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub validity: Option<Validity>,
}

/// Grant status
#[derive(Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GrantStatus {
    #[serde(default)]
    pub phase: GrantPhase,
    
    #[serde(skip_serializing_if = "Option::is_none")]
    pub used: Option<ResourceLimits>,
    
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_updated: Option<String>,
}

/// Grant lifecycle phases
#[derive(Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
pub enum GrantPhase {
    #[default]
    Pending,
    Active,
    Revoked,
    Expired,
}

impl std::fmt::Display for GrantPhase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GrantPhase::Pending => write!(f, "Pending"),
            GrantPhase::Active => write!(f, "Active"),
            GrantPhase::Revoked => write!(f, "Revoked"),
            GrantPhase::Expired => write!(f, "Expired"),
        }
    }
}

impl Grant {
    /// Get the grant name from metadata
    pub fn name(&self) -> String {
        self.metadata.name.clone().unwrap_or_default()
    }

    /// Get display-friendly resource summary
    pub fn resource_summary(&self) -> String {
        let mut parts = Vec::new();
        if let Some(cpu) = &self.spec.hard.requests_cpu {
            parts.push(format!("CPU: {}", cpu));
        }
        if let Some(mem) = &self.spec.hard.requests_memory {
            parts.push(format!("Mem: {}", mem));
        }
        if let Some(storage) = &self.spec.hard.requests_storage {
            parts.push(format!("Storage: {}", storage));
        }
        if parts.is_empty() {
            "No limits specified".to_string()
        } else {
            parts.join(", ")
        }
    }
}