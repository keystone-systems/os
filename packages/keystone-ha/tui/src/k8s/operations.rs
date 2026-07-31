//! Kubernetes CRUD operations for Keystone CRDs
//!
//! Provides typed operations for Grant and other CRDs.

use anyhow::Result;
use kube::api::ObjectMeta;
use crate::k8s::client::KubeClient;
use crate::types::{Grant, GrantPhase, GrantSpec, GrantStatus};

/// Default namespace for Keystone resources
const KEYSTONE_NAMESPACE: &str = "keystone-system";

/// List all grants in the keystone namespace
pub async fn list_grants(_client: &KubeClient) -> Result<Vec<Grant>> {
    // Offline stub: return empty list
    Ok(Vec::new())
}

/// Get a specific grant by name
pub async fn get_grant(_client: &KubeClient, name: &str) -> Result<Grant> {
    // Offline stub: return a placeholder grant so detail screens can render
    Ok(Grant {
        metadata: ObjectMeta {
            name: Some(name.to_string()),
            ..Default::default()
        },
        spec: GrantSpec {
            grantor_realm: "offline".into(),
            grantee_realm: "unknown".into(),
            hard: Default::default(),
            network_policy: Default::default(),
            validity: None,
        },
        status: Some(GrantStatus {
            phase: GrantPhase::Pending,
            used: None,
            message: Some("Mock data".into()),
            last_updated: None,
        }),
    })
}

/// Create a new grant
pub async fn create_grant(_client: &KubeClient, name: &str, spec: GrantSpec) -> Result<Grant> {
    Ok(Grant {
        metadata: ObjectMeta {
            name: Some(name.to_string()),
            ..Default::default()
        },
        spec,
        status: Some(GrantStatus {
            phase: GrantPhase::Pending,
            used: None,
            message: Some("Created in mock mode".into()),
            last_updated: None,
        }),
    })
}

/// Delete (revoke) a grant
pub async fn delete_grant(_client: &KubeClient, _name: &str) -> Result<()> {
    // Offline stub: nothing to delete
    Ok(())
}

/// Update grant status
pub async fn update_grant_status(
    _client: &KubeClient,
    name: &str,
    status: GrantStatus,
) -> Result<Grant> {
    Ok(Grant {
        metadata: ObjectMeta {
            name: Some(name.to_string()),
            ..Default::default()
        },
        spec: GrantSpec {
            grantor_realm: "offline".into(),
            grantee_realm: "unknown".into(),
            hard: Default::default(),
            network_policy: Default::default(),
            validity: None,
        },
        status: Some(status),
    })
}

/// Check if the Grant CRD is installed in the cluster
pub async fn check_crd_installed(_client: &KubeClient) -> Result<bool> {
    // Offline stub: CRDs unavailable
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_list_grants() {
        let client = KubeClient::try_default().await.unwrap();
        let grants = list_grants(&client).await.unwrap();
        assert!(grants.is_empty());
    }
}