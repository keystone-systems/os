use std::path::{Path, PathBuf};

use crate::components::build::BuildScreen;
use crate::components::deploy::DeployScreen;
use crate::components::first_boot::FirstBootScreen;
use crate::components::host_detail::HostDetailScreen;
use crate::components::hosts::HostsScreen;
use crate::components::install::InstallScreen;
use crate::components::installer::InstallerScreen;
use crate::components::iso::IsoScreen;
use crate::components::secrets::SecretsScreen;
use crate::components::security::SecurityScreen;
use crate::components::services::ServicesScreen;
use crate::components::template::CreateConfigScreen;
use crate::components::welcome::WelcomeScreen;
use crate::config::{AppConfig, KeystoneRepo};
use crate::nix;
use crate::repo;
use crate::system;

/// Represents the different screens/views in the TUI.
pub enum AppScreen {
    Welcome(WelcomeScreen),
    CreateConfig(CreateConfigScreen),
    Hosts(HostsScreen),
    HostDetail(HostDetailScreen),
    Build(BuildScreen),
    Iso(IsoScreen),
    Deploy(DeployScreen),
    Install(InstallScreen),
    Installer(InstallerScreen),
    FirstBoot(FirstBootScreen),
    Secrets(SecretsScreen),
    Security(SecurityScreen),
    Services(ServicesScreen),
}

impl AppScreen {
    /// Get a mutable reference to the Component trait object for this screen.
    pub fn as_component_mut(&mut self) -> Option<&mut dyn crate::component::Component> {
        match self {
            AppScreen::Welcome(s) => Some(s),
            AppScreen::CreateConfig(s) => Some(s),
            AppScreen::Hosts(s) => Some(s),
            AppScreen::HostDetail(s) => Some(s),
            AppScreen::Build(s) => Some(s),
            AppScreen::Iso(s) => Some(s),
            AppScreen::Deploy(s) => Some(s),
            AppScreen::Install(s) => Some(s),
            AppScreen::Installer(s) => Some(s),
            AppScreen::Secrets(s) => Some(s),
            AppScreen::Security(s) => Some(s),
            AppScreen::Services(s) => Some(s),
            AppScreen::FirstBoot(s) => Some(s),
        }
    }
}

/// Application state for the ks.
pub struct App {
    pub should_quit: bool,
    pub config: AppConfig,
    pub current_screen: AppScreen,
    /// Index of the currently active repo in config.repos
    pub active_repo_index: Option<usize>,
}

impl App {
    pub async fn new() -> Self {
        let mut config = AppConfig::load().await.unwrap_or_else(|e| {
            eprintln!("Failed to load config: {:?}", e);
            AppConfig::default()
        });

        // Discover repos on disk and merge any that aren't in config
        if let Ok(discovered) = repo::discover_repos().await {
            for repo in discovered {
                if !config.repos.iter().any(|r| r.path == repo.path) {
                    config.repos.push(repo);
                }
            }
        }

        let current_system_flake = current_system_flake_path();
        let (active_repo_index, config_changed) =
            reconcile_current_system_repo(&mut config, current_system_flake.as_deref());

        if config_changed {
            let _ = config.save().await;
        }

        let (current_screen, active_repo_index) = if config.repos.is_empty() {
            (AppScreen::Welcome(WelcomeScreen::new()), None)
        } else {
            let repo_index = active_repo_index.unwrap_or(0);
            let repo = &config.repos[repo_index];
            match Self::load_hosts_screen(repo, current_system_flake.as_deref()).await {
                Ok(screen) => (AppScreen::Hosts(screen), Some(repo_index)),
                Err(_e) => {
                    // Failed to parse flake, show hosts screen with empty hosts
                    let screen = HostsScreen::new(repo.name.clone(), Vec::new());
                    (AppScreen::Hosts(screen), Some(repo_index))
                }
            }
        };

        Self {
            should_quit: false,
            config,
            current_screen,
            active_repo_index,
        }
    }

    /// Load the hosts screen for a given repo with live dashboard polling.
    pub async fn load_hosts_screen(
        repo: &KeystoneRepo,
        current_system_flake: Option<&Path>,
    ) -> anyhow::Result<HostsScreen> {
        let flake_info = nix::parse_flake(&repo.path).await?;

        // Build initial host statuses with local hostname detection
        let statuses = system::match_hosts_to_peers(&flake_info.hosts, None);
        let preferred_hostname = matches_current_system_repo(&repo.path, current_system_flake)
            .then(system::detect_local_hostname);
        let mut screen = HostsScreen::new_with_statuses_and_preferred_host(
            repo.name.clone(),
            statuses,
            preferred_hostname.as_deref(),
        );

        // Show warning for legacy config format
        if flake_info.version == nix::ConfigVersion::V0 {
            screen.set_warning(
                "This config uses legacy format (v0.0.0). \
                 Regenerate with `ks template` to upgrade to v1.0.0."
                    .to_string(),
            );
        }

        // Start background polling for metrics and tailscale
        let rx = system::spawn_dashboard_poller();
        screen.set_channel(rx);

        Ok(screen)
    }

    /// Transition to the hosts screen for a repo.
    pub async fn go_to_hosts(&mut self, repo_index: usize) {
        if let Some(repo) = self.config.repos.get(repo_index) {
            match Self::load_hosts_screen(repo, current_system_flake_path().as_deref()).await {
                Ok(screen) => {
                    self.current_screen = AppScreen::Hosts(screen);
                    self.active_repo_index = Some(repo_index);
                }
                Err(e) => {
                    eprintln!("Failed to load hosts: {:?}", e);
                }
            }
        }
    }

    /// Navigate to a screen by Action::NavigateTo.
    ///
    /// TODO: once all screens implement Component, this should be the sole
    /// navigation mechanism, replacing the per-action match in handle_action.
    pub async fn navigate_to(&mut self, screen: crate::action::Screen) {
        use crate::action::Screen;
        match screen {
            Screen::Welcome => {
                self.current_screen = AppScreen::Welcome(WelcomeScreen::new());
            }
            Screen::Template { repo_name } => {
                self.current_screen = AppScreen::CreateConfig(CreateConfigScreen::new(repo_name));
            }
            Screen::Hosts => {
                self.go_to_hosts(self.active_repo_index.unwrap_or(0)).await;
            }
            Screen::HostDetail(host) => {
                self.current_screen = AppScreen::HostDetail(HostDetailScreen::new(*host));
            }
            Screen::Build { host_name } => {
                if let Some(repo_path) = self.active_repo_path() {
                    self.current_screen = AppScreen::Build(BuildScreen::new(host_name, repo_path));
                }
            }
            Screen::Iso { host_name } => {
                if let Some(repo_path) = self.active_repo_path() {
                    self.current_screen =
                        AppScreen::Iso(IsoScreen::new_for_host(repo_path, host_name));
                }
            }
            Screen::Deploy { host_name } => {
                if let Some(repo_path) = self.active_repo_path() {
                    self.current_screen =
                        AppScreen::Deploy(DeployScreen::new(repo_path, host_name));
                }
            }
            Screen::Install => {
                // Install is only entered via ISO detection, not navigation
            }
            Screen::FirstBoot => {
                // FirstBoot is only entered via marker detection, not navigation
            }
            Screen::Installer => {
                let mut screen = InstallerScreen::new();
                if let Some(path) = self.active_repo_path() {
                    screen = screen.with_repo_path(path);
                }
                self.current_screen = AppScreen::Installer(screen);
            }
            Screen::Secrets => {
                self.current_screen = AppScreen::Secrets(SecretsScreen::new());
            }
            Screen::Security => {
                self.current_screen = AppScreen::Security(SecurityScreen::new());
            }
            Screen::Services => {
                self.current_screen = AppScreen::Services(ServicesScreen::new());
            }
            Screen::Update => {
                // TODO: implement update screen
            }
            Screen::Doctor => {
                // TODO: implement doctor screen
            }
        }
    }

    /// Get the path of the currently active repo.
    pub fn active_repo_path(&self) -> Option<PathBuf> {
        self.active_repo_index
            .and_then(|i| self.config.repos.get(i))
            .map(|r| r.path.clone())
    }

    /// Create an App with a given config, starting on the Welcome screen.
    /// Skips filesystem operations (no `discover_repos`, no `AppConfig::load`).
    pub fn new_with_config(config: AppConfig) -> Self {
        let has_repos = !config.repos.is_empty();
        let current_screen = if has_repos {
            // Start on hosts with empty hosts list (no flake parsing)
            let name = config.repos[0].name.clone();
            AppScreen::Hosts(HostsScreen::new(name, Vec::new()))
        } else {
            AppScreen::Welcome(WelcomeScreen::new())
        };

        Self {
            should_quit: false,
            config,
            current_screen,
            active_repo_index: if has_repos { Some(0) } else { None },
        }
    }

    /// Create an App in installer mode — starts on the InstallScreen with
    /// pre-baked config from an ISO. Skips repo discovery and Welcome flow.
    pub fn new_for_installer(
        installer_config: crate::components::install::InstallerConfig,
    ) -> Self {
        Self {
            should_quit: false,
            config: AppConfig::default(),
            current_screen: AppScreen::Install(InstallScreen::new(installer_config)),
            active_repo_index: None,
        }
    }

    /// Create an App in first-boot mode — starts on the FirstBootScreen.
    /// Runs after a fresh install when `.first-boot-pending` marker exists.
    pub fn new_for_first_boot(
        first_boot_config: crate::components::first_boot::FirstBootConfig,
    ) -> Self {
        Self {
            should_quit: false,
            config: AppConfig::default(),
            current_screen: AppScreen::FirstBoot(FirstBootScreen::new(first_boot_config)),
            active_repo_index: None,
        }
    }

    /// Create a minimal App for testing — starts on Welcome with empty config.
    pub fn new_for_test() -> Self {
        Self::new_with_config(AppConfig::default())
    }

    pub async fn save_config(&self) {
        if let Err(e) = self.config.save().await {
            eprintln!("Failed to save config: {:?}", e);
        }
    }
}

fn current_system_flake_path() -> Option<PathBuf> {
    // Read the authoritative pointer written at NixOS activation time.
    let content = std::fs::read_to_string("/run/current-system/keystone-system-flake").ok()?;
    let path = content.trim();
    if path.is_empty() {
        return None;
    }
    normalize_flake_repo_path(&PathBuf::from(path))
}

fn normalize_flake_repo_path(path: &Path) -> Option<PathBuf> {
    let flake_path = path.join("flake.nix");
    if !flake_path.is_file() {
        return None;
    }

    std::fs::canonicalize(path)
        .ok()
        .or_else(|| Some(path.to_path_buf()))
}

fn matches_current_system_repo(repo_path: &Path, current_system_flake: Option<&Path>) -> bool {
    let Some(current_system_flake) = current_system_flake else {
        return false;
    };

    normalize_flake_repo_path(repo_path)
        .map(|normalized| normalized == current_system_flake)
        .unwrap_or(false)
}

fn repo_name_from_path(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().to_string())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "keystone".to_string())
}

fn reconcile_current_system_repo(
    config: &mut AppConfig,
    current_system_flake: Option<&Path>,
) -> (Option<usize>, bool) {
    let Some(current_system_flake) = current_system_flake else {
        return (None, false);
    };

    if let Some(index) = config
        .repos
        .iter()
        .position(|repo| matches_current_system_repo(&repo.path, Some(current_system_flake)))
    {
        return (Some(index), false);
    }

    let repo_name = repo_name_from_path(current_system_flake);
    if let Some(index) = config.repos.iter().position(|repo| repo.name == repo_name) {
        config.repos[index].path = current_system_flake.to_path_buf();
        return (Some(index), true);
    }

    config.repos.push(KeystoneRepo {
        name: repo_name,
        path: current_system_flake.to_path_buf(),
    });
    (Some(config.repos.len() - 1), true)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use tempfile::tempdir;

    use super::{
        matches_current_system_repo, normalize_flake_repo_path, reconcile_current_system_repo,
    };
    use crate::config::{AppConfig, KeystoneRepo};

    #[test]
    fn normalize_flake_repo_path_requires_flake() {
        let dir = tempdir().unwrap();
        assert!(normalize_flake_repo_path(dir.path()).is_none());
    }

    #[test]
    fn reconcile_current_system_repo_updates_stale_path() {
        let dir = tempdir().unwrap();
        let detected = dir.path().join("nixos-config");
        std::fs::create_dir(&detected).unwrap();
        std::fs::write(detected.join("flake.nix"), "{ }").unwrap();

        let normalized = normalize_flake_repo_path(&detected).unwrap();
        let mut config = AppConfig {
            repos: vec![KeystoneRepo {
                name: "nixos-config".to_string(),
                path: PathBuf::from("/old/path/nixos-config"),
            }],
        };

        let (index, changed) = reconcile_current_system_repo(&mut config, Some(&normalized));
        let index = index.unwrap();
        assert_eq!(index, 0);
        assert!(changed);
        assert_eq!(config.repos[0].path, normalized);
    }

    #[test]
    fn reconcile_current_system_repo_adds_missing_repo() {
        let dir = tempdir().unwrap();
        let detected = dir.path().join("nixos-config");
        std::fs::create_dir(&detected).unwrap();
        std::fs::write(detected.join("flake.nix"), "{ }").unwrap();

        let normalized = normalize_flake_repo_path(&detected).unwrap();
        let mut config = AppConfig::default();

        let (index, changed) = reconcile_current_system_repo(&mut config, Some(&normalized));
        let index = index.unwrap();
        assert_eq!(index, 0);
        assert!(changed);
        assert_eq!(config.repos[0].name, "nixos-config");
        assert_eq!(config.repos[0].path, normalized);
    }

    #[test]
    fn matches_current_system_repo_compares_normalized_paths() {
        let dir = tempdir().unwrap();
        let detected = dir.path().join("nixos-config");
        std::fs::create_dir(&detected).unwrap();
        std::fs::write(detected.join("flake.nix"), "{ }").unwrap();

        let normalized = normalize_flake_repo_path(&detected).unwrap();
        assert!(matches_current_system_repo(&detected, Some(&normalized)));
    }
}
