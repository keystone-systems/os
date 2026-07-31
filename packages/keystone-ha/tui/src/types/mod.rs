//! Type definitions for Keystone cross-realm resources
//!
//! This module defines the types used by the TUI, importing shared definitions
//! from the keystone-ha-defs crate.

mod realm;

// Re-export shared types
pub use keystone_ha_defs::grant::{
    Grant, GrantPhase, GrantSpec, GrantStatus, NetworkPolicy, ResourceLimits, Validity,
};
pub use keystone_ha_defs::backup::{
    Backup, BackupPhase, BackupSpec, BackupStatus, BackupType,
};
pub use keystone_ha_defs::workload::{
    EnvVar, PortMapping, Workload, WorkloadPhase, WorkloadResources, WorkloadSpec, WorkloadStatus,
};
pub use keystone_ha_defs::super_entity::{
    SuperEntity, SuperEntitySpec, SuperEntityStatus, SuperEntityPhase,
};

// Re-export local View Models (that might use shared types)
pub use realm::{Realm, RealmResourceLimits, RealmResourceUsage};

// Re-export shared enums used in Realm View Model
pub use keystone_ha_defs::realm::{ConnectionType, RealmPhase};