use kube::CustomResource;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

#[derive(CustomResource, Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
#[kube(group = "keystone.io", version = "v1alpha1", kind = "SuperEntity", namespaced)]
#[kube(status = "SuperEntityStatus")]
#[serde(rename_all = "camelCase")]
pub struct SuperEntitySpec {
    pub name: String,
    pub purpose: String,
    pub member_realms: Vec<String>,
    pub storage_contributed: String,
}

#[derive(Deserialize, Serialize, Clone, Debug, Default, JsonSchema, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SuperEntityStatus {
    #[serde(default)]
    pub phase: SuperEntityPhase,
    pub message: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema, PartialEq)]
pub enum SuperEntityPhase {
    #[default]
    Pending,
    Active,
    Incomplete,
}

impl std::fmt::Display for SuperEntityPhase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SuperEntityPhase::Pending => write!(f, "Pending"),
            SuperEntityPhase::Active => write!(f, "Active"),
            SuperEntityPhase::Incomplete => write!(f, "Incomplete"),
        }
    }
}

impl SuperEntity {
    pub fn name(&self) -> String {
        self.metadata.name.clone().unwrap_or_default()
    }
}