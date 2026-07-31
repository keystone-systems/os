//! Application state and screen management
//!
//! This module contains the core application state machine, including
//! the Screen enum for navigation and the App struct for global state.

use kube::api::ObjectMeta;
use crate::types::{
    Backup, BackupPhase, BackupType, Grant, GrantPhase, GrantSpec, GrantStatus, NetworkPolicy,
    Realm, RealmResourceLimits, RealmResourceUsage, SuperEntity, SuperEntitySpec, SuperEntityStatus,
    Workload, WorkloadPhase, WorkloadResources, EnvVar, PortMapping, Validity,
};
use crate::types::ConnectionType;

/// Steps in the grant creation wizard
#[derive(Debug, Clone, PartialEq)]
pub enum GrantStep {
    Grantee,
    Resources,
    Network,
    Confirm,
}

/// Steps in the workload deployment wizard
#[derive(Debug, Clone, PartialEq)]
pub enum DeployStep {
    SelectRealm,
    Configure,
    Review,
}

/// Methods for connecting to a realm
#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionMethod {
    Tailscale,
    Headscale,
    Token,
}

/// All possible screens in the application
#[derive(Debug, Clone, PartialEq)]
pub enum Screen {
    /// Main menu / home screen
    Home,

    // Grant Management
    GrantList,
    GrantCreate { step: GrantStep },
    GrantDetail { id: String },

    // Realm Connections
    RealmList,
    RealmConnect { method: Option<ConnectionMethod> },
    RealmDetail { id: String },

    // Workloads
    WorkloadList,
    WorkloadDeploy { step: DeployStep },
    WorkloadDetail { id: String },

    // Super Entities
    SuperEntityList,
    SuperEntityCreate,
    SuperEntityDetail { id: String },

    // Backups
    BackupList,
    BackupVerify { id: String },
}

impl Default for Screen {
    fn default() -> Self {
        Screen::Home
    }
}

/// Main application state
pub struct App {
    /// Current screen
    pub screen: Screen,

    /// Navigation history for back functionality
    pub screen_history: Vec<Screen>,

    /// Whether we're connected to Kubernetes
    pub connected: bool,

    /// Current realm identifier
    pub current_realm: Option<String>,

    // UI state
    /// Selected index in lists
    pub list_index: usize,

    /// Text input buffer for forms
    pub input_buffer: String,

    /// Current form field index
    pub form_field: usize,

    /// Whether an async operation is loading
    pub loading: bool,

    /// Error message to display
    pub error: Option<String>,

    /// Whether to show help overlay
    pub show_help: bool,

    // Data from Kubernetes
    /// Grants (resources shared with others)
    pub grants: Vec<Grant>,

    /// Connected realms
    pub realms: Vec<Realm>,

    /// Running workloads
    pub workloads: Vec<Workload>,

    /// Super entities (shared ownership structures)
    pub super_entities: Vec<SuperEntity>,

    /// Backup status
    pub backups: Vec<Backup>,

    // Grant creation form state
    pub grant_form: GrantForm,

    /// Flag to quit the application
    pub should_quit: bool,
}

/// Form state for grant creation
#[derive(Debug, Clone, Default)]
pub struct GrantForm {
    pub grantee_realm: String,
    pub requests_cpu: String,
    pub requests_memory: String,
    pub limits_cpu: String,
    pub limits_memory: String,
    pub requests_storage: String,
    pub egress_allowed: bool,
    pub allowed_destinations: Vec<String>,
}

impl Default for App {
    fn default() -> Self {
        Self::new()
    }
}

impl App {
    /// Create a new application instance
    pub fn new() -> Self {
        let mut app = Self {
            screen: Screen::Home,
            screen_history: Vec::new(),
            connected: false,
            current_realm: None,
            list_index: 0,
            input_buffer: String::new(),
            form_field: 0,
            loading: false,
            error: None,
            show_help: false,
            grants: Vec::new(),
            realms: Vec::new(),
            workloads: Vec::new(),
            super_entities: Vec::new(),
            backups: Vec::new(),
            grant_form: GrantForm::default(),
            should_quit: false,
        };

        app.load_mock_data();
        app
    }

    /// Try to connect to the Kubernetes cluster
    pub async fn connect_k8s(&mut self) {
        // Kubernetes connectivity disabled in mock/offline mode
        self.connected = false;
        self.error = Some("Kubernetes integration disabled in mock mode".to_string());
    }

    /// Seed the app with mocked data so UI screens are populated offline
    fn load_mock_data(&mut self) {
        self.grants = vec![
            Grant {
                metadata: ObjectMeta {
                    name: Some("family-compute".into()),
                    ..Default::default()
                },
                spec: GrantSpec {
                    grantor_realm: "home-lab".into(),
                    grantee_realm: "alice-cloud".into(),
                    hard: crate::types::ResourceLimits {
                        requests_cpu: Some("4".into()),
                        requests_memory: Some("8Gi".into()),
                        limits_cpu: Some("6".into()),
                        limits_memory: Some("12Gi".into()),
                        requests_storage: Some("250Gi".into()),
                        requests_gpu: None,
                    },
                    network_policy: NetworkPolicy {
                        egress_allowed: true,
                        allowed_destinations: vec!["10.42.0.0/16".into(), "home-lab".into()],
                    },
                    validity: Some(Validity {
                        valid_from: "2024-11-01T00:00:00Z".into(),
                        valid_until: None,
                    }),
                },
                status: Some(GrantStatus {
                    phase: GrantPhase::Active,
                    used: None,
                    message: Some("Ready for workloads".into()),
                    last_updated: None,
                }),
            },
            Grant {
                metadata: ObjectMeta {
                    name: Some("shared-gpu".into()),
                    ..Default::default()
                },
                spec: GrantSpec {
                    grantor_realm: "research-lab".into(),
                    grantee_realm: "home-lab".into(),
                    hard: crate::types::ResourceLimits {
                        requests_cpu: Some("2".into()),
                        requests_memory: Some("16Gi".into()),
                        limits_cpu: Some("4".into()),
                        limits_memory: Some("32Gi".into()),
                        requests_storage: Some("100Gi".into()),
                        requests_gpu: Some(1),
                    },
                    network_policy: NetworkPolicy {
                        egress_allowed: false,
                        allowed_destinations: vec![],
                    },
                    validity: None,
                },
                status: Some(GrantStatus {
                    phase: GrantPhase::Pending,
                    used: None,
                    message: Some("Awaiting approval from research-lab".into()),
                    last_updated: None,
                }),
            },
        ];

        self.realms = vec![
            Realm {
                id: "home-lab".into(),
                name: "Home Lab".into(),
                connection_type: ConnectionType::Tailscale,
                address: "home.ts.net".into(),
                connected: true,
                grantor: Some("self".into()),
                resource_limits: Some(RealmResourceLimits {
                    cpu: Some("12".into()),
                    memory: Some("64Gi".into()),
                    storage: Some("8Ti".into()),
                }),
                current_usage: Some(RealmResourceUsage {
                    cpu: Some("4.2".into()),
                    memory: Some("18Gi".into()),
                    storage: Some("1.4Ti".into()),
                }),
                egress_allowed: true,
                connected_at: Some("2024-10-15T08:00:00Z".into()),
            },
            Realm {
                id: "research-lab".into(),
                name: "Research Lab".into(),
                connection_type: ConnectionType::Headscale,
                address: "research.headscale.example.com".into(),
                connected: true,
                grantor: Some("research-admin".into()),
                resource_limits: Some(RealmResourceLimits {
                    cpu: Some("32".into()),
                    memory: Some("256Gi".into()),
                    storage: Some("20Ti".into()),
                }),
                current_usage: Some(RealmResourceUsage {
                    cpu: Some("12.5".into()),
                    memory: Some("110Gi".into()),
                    storage: Some("4.0Ti".into()),
                }),
                egress_allowed: false,
                connected_at: Some("2024-10-20T13:00:00Z".into()),
            },
        ];

        self.workloads = vec![
            Workload {
                id: "ml-api".into(),
                name: "Edge ML API".into(),
                image: "ghcr.io/keystone/edge-ml:main".into(),
                target_realm: "home-lab".into(),
                status: WorkloadPhase::Running,
                resources: WorkloadResources {
                    cpu: Some("2".into()),
                    memory: Some("4Gi".into()),
                    storage: None,
                },
                ports: vec![PortMapping {
                    container_port: 8080,
                    host_port: Some(30080),
                    protocol: "TCP".into(),
                }],
                env: vec![EnvVar {
                    name: "ENV".into(),
                    value: "prod".into(),
                }],
                created_at: Some("2024-11-05T12:00:00Z".into()),
                started_at: Some("2024-11-05T12:05:00Z".into()),
            },
            Workload {
                id: "video-pipeline".into(),
                name: "Video Pipeline".into(),
                image: "ghcr.io/keystone/video-pipeline:latest".into(),
                target_realm: "research-lab".into(),
                status: WorkloadPhase::Creating,
                resources: WorkloadResources {
                    cpu: Some("6".into()),
                    memory: Some("24Gi".into()),
                    storage: Some("500Gi".into()),
                },
                ports: vec![PortMapping {
                    container_port: 9000,
                    host_port: None,
                    protocol: "UDP".into(),
                }],
                env: vec![EnvVar {
                    name: "STAGE".into(),
                    value: "testing".into(),
                }],
                created_at: Some("2024-11-07T09:00:00Z".into()),
                started_at: None,
            },
        ];

        self.super_entities = vec![
            SuperEntity {
                metadata: ObjectMeta {
                    name: Some("family-fabric".into()),
                    ..Default::default()
                },
                spec: SuperEntitySpec {
                    name: "Family Fabric".into(),
                    purpose: "Shared backups across households".into(),
                    member_realms: vec!["home-lab".into(), "alice-cloud".into(), "bob-hub".into()],
                    storage_contributed: "12Ti".into(),
                },
                status: Some(SuperEntityStatus {
                    phase: crate::types::SuperEntityPhase::Active,
                    message: None,
                }),
            },
            SuperEntity {
                metadata: ObjectMeta {
                    name: Some("friends-gaming".into()),
                    ..Default::default()
                },
                spec: SuperEntitySpec {
                    name: "Friends Gaming Pool".into(),
                    purpose: "Low-latency game server hosting".into(),
                    member_realms: vec!["home-lab".into(), "carl-hub".into()],
                    storage_contributed: "2Ti".into(),
                },
                status: Some(SuperEntityStatus {
                    phase: crate::types::SuperEntityPhase::Pending,
                    message: None,
                }),
            },
        ];

        self.backups = vec![
            Backup {
                id: "photos-2024".into(),
                name: "Family Photos 2024".into(),
                backup_type: BackupType::SuperEntity,
                copy_count: 3,
                locations: vec!["home-lab".into(), "alice-cloud".into(), "bob-hub".into()],
                last_verified: Some("2024-11-06T18:30:00Z".into()),
                status: BackupPhase::Healthy,
                size: Some("1.2Ti".into()),
                created_at: Some("2024-01-01T00:00:00Z".into()),
            },
            Backup {
                id: "db-snapshots".into(),
                name: "DB Snapshots".into(),
                backup_type: BackupType::Local,
                copy_count: 1,
                locations: vec!["home-lab".into()],
                last_verified: Some("2024-11-02T07:10:00Z".into()),
                status: BackupPhase::Degraded,
                size: Some("220Gi".into()),
                created_at: Some("2024-06-15T00:00:00Z".into()),
            },
            Backup {
                id: "research-datasets".into(),
                name: "Research Datasets".into(),
                backup_type: BackupType::Remote,
                copy_count: 2,
                locations: vec!["research-lab".into(), "cold-storage".into()],
                last_verified: None,
                status: BackupPhase::Verifying,
                size: Some("4.5Ti".into()),
                created_at: Some("2024-08-20T00:00:00Z".into()),
            },
        ];
    }
    
    // ... rest of impl
    /// Navigate to a new screen, pushing current to history
    pub fn navigate_to(&mut self, screen: Screen) {
        self.screen_history.push(self.screen.clone());
        self.screen = screen;
        self.list_index = 0;
        self.input_buffer.clear();
        self.form_field = 0;
        self.error = None;
    }

    /// Go back to the previous screen
    pub fn go_back(&mut self) {
        if let Some(prev) = self.screen_history.pop() {
            self.screen = prev;
            self.list_index = 0;
            self.input_buffer.clear();
            self.form_field = 0;
        }
    }

    /// Move selection up in a list
    pub fn select_prev(&mut self, max: usize) {
        if self.list_index > 0 {
            self.list_index -= 1;
        } else if max > 0 {
            self.list_index = max - 1;
        }
    }

    /// Move selection down in a list
    pub fn select_next(&mut self, max: usize) {
        if max > 0 && self.list_index < max - 1 {
            self.list_index += 1;
        } else {
            self.list_index = 0;
        }
    }

    /// Move to next form field
    pub fn next_field(&mut self, max: usize) {
        if self.form_field < max - 1 {
            self.form_field += 1;
        }
    }

    /// Move to previous form field
    pub fn prev_field(&mut self) {
        if self.form_field > 0 {
            self.form_field -= 1;
        }
    }

    /// Toggle help overlay
    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    /// Clear any error message
    pub fn clear_error(&mut self) {
        self.error = None;
    }

    /// Get the number of items in the current list
    pub fn current_list_len(&self) -> usize {
        match &self.screen {
            Screen::Home => 5, // Main menu has 5 options
            Screen::GrantList => self.grants.len(),
            Screen::RealmList => self.realms.len(),
            Screen::WorkloadList => self.workloads.len(),
            Screen::SuperEntityList => self.super_entities.len(),
            Screen::BackupList => self.backups.len(),
            _ => 0,
        }
    }
}