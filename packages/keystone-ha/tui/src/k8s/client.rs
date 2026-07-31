//! Kubernetes client wrapper
//!
//! Provides a high-level wrapper around Kubernetes interactions.
//! In mock/offline mode this is a lightweight placeholder.

use anyhow::Result;

/// Default namespace for Keystone resources
pub const KEYSTONE_NAMESPACE: &str = "keystone-system";

/// Lightweight mock client used during offline development
pub struct KubeClient {
    namespace: String,
}

impl KubeClient {
    /// Create a new KubeClient using default kubeconfig
    pub async fn try_default() -> Result<Self> {
        Ok(Self {
            namespace: KEYSTONE_NAMESPACE.to_string(),
        })
    }

    /// Create a new KubeClient with a specific namespace
    pub async fn with_namespace(namespace: impl Into<String>) -> Result<Self> {
        Ok(Self {
            namespace: namespace.into(),
        })
    }

    /// Get the current namespace
    pub fn namespace(&self) -> &str {
        &self.namespace
    }

    /// Set the namespace for operations
    pub fn set_namespace(&mut self, namespace: impl Into<String>) {
        self.namespace = namespace.into();
    }

    /// Check if the client can connect to the cluster
    pub async fn health_check(&self) -> Result<bool> {
        // Offline stub: report unhealthy to indicate mock mode
        Ok(false)
    }
}
