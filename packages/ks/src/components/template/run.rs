//! Template command execution — shared by JSON, CLI, and TUI modes.

use std::path::PathBuf;

use super::types::{TemplateParams, TemplateResult};

/// Execute the template command: generate config files to the output directory.
pub async fn execute(mut params: TemplateParams) -> anyhow::Result<TemplateResult> {
    // Fetch GitHub info if username provided
    let mut authorized_keys = Vec::new();
    if let Some(ref gh) = params.github_username {
        if params.owner_name.is_none() {
            params.owner_name = Some(crate::github::fetch_user_name(gh).await);
        }
        authorized_keys = crate::github::fetch_ssh_keys(gh).await.unwrap_or_default();
    }

    // Also detect local SSH keys
    authorized_keys.extend(crate::ssh_keys::detect_local_ssh_keys());

    let mut config = params.to_generate_config();
    config.user.authorized_keys = authorized_keys.clone();
    if config.remote_unlock.enable {
        config.remote_unlock.authorized_keys = authorized_keys;
    }

    // Determine output directory
    let output_dir = PathBuf::from(params.output.as_deref().unwrap_or(&params.hostname));

    tokio::fs::create_dir_all(&output_dir).await?;
    let host_dir = output_dir.join("hosts").join(&params.hostname);
    tokio::fs::create_dir_all(&host_dir).await?;

    // Generate and write files
    let flake_nix = crate::template::generate_flake_nix(&config);
    let configuration_nix = crate::template::generate_configuration_nix(&config);
    let hardware_nix = crate::template::generate_hardware_nix(&config);

    tokio::fs::write(output_dir.join("flake.nix"), &flake_nix).await?;
    tokio::fs::write(host_dir.join("configuration.nix"), &configuration_nix).await?;
    tokio::fs::write(host_dir.join("hardware.nix"), &hardware_nix).await?;

    let files = vec![
        "flake.nix".to_string(),
        format!("hosts/{}/configuration.nix", params.hostname),
        format!("hosts/{}/hardware.nix", params.hostname),
    ];

    Ok(TemplateResult {
        config_version: "1.0.0",
        output_dir: std::fs::canonicalize(&output_dir).unwrap_or(output_dir),
        files,
    })
}
