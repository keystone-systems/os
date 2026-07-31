use anyhow::{Context, Result};
use home::home_dir;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

const CONFIG_FILE_NAME: &str = "keystone.json";

/// Represents a managed Keystone repository.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeystoneRepo {
    pub name: String,
    pub path: PathBuf,
}

/// Application configuration, stored in ~/.keystone/keystone.json.
#[derive(Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppConfig {
    pub repos: Vec<KeystoneRepo>,
}

impl AppConfig {
    /// Returns the path to the configuration file.
    fn config_file_path() -> Result<PathBuf> {
        let home_dir = home_dir().context("Failed to get home directory")?;
        let keystone_dir = home_dir.join(".keystone");
        Ok(keystone_dir.join(CONFIG_FILE_NAME))
    }

    /// Loads the application configuration from ~/.keystone/keystone.json.
    pub async fn load() -> Result<Self> {
        let config_path = Self::config_file_path()?;
        if !config_path.exists() {
            return Ok(Self::default());
        }

        let config_content = fs::read_to_string(&config_path).await.context(format!(
            "Failed to read config file: {}",
            config_path.display()
        ))?;
        serde_json::from_str(&config_content).context("Failed to deserialize keystone.json")
    }

    /// Saves the application configuration to ~/.keystone/keystone.json.
    pub async fn save(&self) -> Result<()> {
        let config_path = Self::config_file_path()?;
        self.save_to_path(&config_path).await
    }

    /// Loads config from a specific path (useful for testing).
    pub async fn load_from_path(path: &std::path::Path) -> Result<Self> {
        if !path.exists() {
            return Ok(Self::default());
        }

        let config_content = fs::read_to_string(path)
            .await
            .context(format!("Failed to read config file: {}", path.display()))?;
        serde_json::from_str(&config_content).context("Failed to deserialize keystone.json")
    }

    /// Saves config to a specific path (useful for testing).
    pub async fn save_to_path(&self, path: &std::path::Path) -> Result<()> {
        let config_dir = path
            .parent()
            .context("Config path has no parent directory")?;

        fs::create_dir_all(config_dir).await.context(format!(
            "Failed to create config directory: {}",
            config_dir.display()
        ))?;

        let config_content =
            serde_json::to_string_pretty(self).context("Failed to serialize config to JSON")?;
        fs::write(path, config_content)
            .await
            .context(format!("Failed to write config file: {}", path.display()))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[tokio::test]
    async fn test_config_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let config_path = dir.path().join("keystone.json");

        let config = AppConfig {
            repos: vec![
                KeystoneRepo {
                    name: "test-repo".to_string(),
                    path: PathBuf::from("/tmp/test-repo"),
                },
                KeystoneRepo {
                    name: "another-repo".to_string(),
                    path: PathBuf::from("/home/user/another"),
                },
            ],
        };

        config.save_to_path(&config_path).await.unwrap();
        let loaded = AppConfig::load_from_path(&config_path).await.unwrap();
        assert_eq!(config, loaded);
    }

    #[tokio::test]
    async fn test_load_nonexistent_returns_default() {
        let dir = tempfile::tempdir().unwrap();
        let config_path = dir.path().join("nonexistent.json");

        let loaded = AppConfig::load_from_path(&config_path).await.unwrap();
        assert_eq!(loaded, AppConfig::default());
    }
}
