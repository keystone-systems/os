//! `ks screenshots` command — local screenshot ingestion and sync.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use reqwest::multipart::{Form, Part};
use serde_json::{json, Value};

use super::photos::{get_or_create_album_id, resolve_client, tag_asset};

#[derive(Subcommand)]
pub enum ScreenshotsCommand {
    /// Upload local screenshots into Immich.
    Sync(SyncArgs),
}

#[derive(Args)]
pub struct SyncArgs {
    #[arg(long)]
    directory: Option<PathBuf>,
    #[arg(long = "album-name")]
    album_name: Option<String>,
    #[arg(long = "host-name")]
    host_name: Option<String>,
    #[arg(long = "account-name")]
    account_name: Option<String>,
    #[arg(long = "state-file")]
    state_file: Option<PathBuf>,
    #[arg(long = "api-key-file")]
    api_key_file: Option<PathBuf>,
    #[arg(long = "url")]
    url: Option<String>,
}

fn state_has_hash(state_file: &Path, sha256: &str) -> bool {
    fs::read_to_string(state_file)
        .ok()
        .map(|contents| {
            contents
                .lines()
                .any(|line| line.split('\t').next() == Some(sha256))
        })
        .unwrap_or(false)
}

fn record_state(state_file: &Path, sha256: &str, asset_id: &str, path: &Path) -> Result<()> {
    use std::io::Write;

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(state_file)
        .with_context(|| format!("Failed to open {}", state_file.display()))?;
    writeln!(file, "{sha256}\t{asset_id}\t{}", path.display())
        .with_context(|| format!("Failed to append {}", state_file.display()))
}

fn file_hash(program: &str, path: &Path) -> Result<String> {
    let output = Command::new(program)
        .arg(path)
        .output()
        .with_context(|| format!("Failed to run {} for {}", program, path.display()))?;
    if !output.status.success() {
        anyhow::bail!("{} failed for {}", program, path.display())
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_string())
}

fn file_timestamp_utc(path: &Path) -> Result<String> {
    let modified = fs::metadata(path)
        .with_context(|| format!("Failed to read metadata for {}", path.display()))?
        .modified()
        .with_context(|| format!("Failed to read modified time for {}", path.display()))?;
    let seconds = modified
        .duration_since(UNIX_EPOCH)
        .context("File modified time predates UNIX_EPOCH")?
        .as_secs();

    let output = Command::new("date")
        .args([
            "-u",
            "-d",
            &format!("@{seconds}"),
            "+%Y-%m-%dT%H:%M:%S.000Z",
        ])
        .output()
        .context("Failed to format timestamp with date")?;
    if !output.status.success() {
        anyhow::bail!("date failed while formatting {}", path.display())
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

#[allow(clippy::cognitive_complexity)]
async fn run_sync(args: SyncArgs) -> Result<()> {
    let api_key_override = match args.api_key_file.as_deref() {
        Some(path) => Some(
            fs::read_to_string(path)
                .with_context(|| format!("Immich API key file not found: {}", path.display()))?
                .trim()
                .to_string(),
        ),
        None => None,
    };
    let client = resolve_client(args.url.as_deref(), api_key_override.as_deref())?;

    let account_name = args
        .account_name
        .clone()
        .or_else(|| env::var("USER").ok())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "unknown".to_string());
    let directory = args.directory.unwrap_or_else(|| {
        env::var_os("KEYSTONE_SCREENSHOT_DIR")
            .map(PathBuf::from)
            .or_else(|| env::var_os("XDG_PICTURES_DIR").map(PathBuf::from))
            .or_else(|| home::home_dir().map(|home| home.join("Pictures")))
            .unwrap_or_else(|| PathBuf::from("Pictures"))
    });
    let album_name = args
        .album_name
        .unwrap_or_else(|| format!("Screenshots - {}", account_name));
    let host_name = args.host_name.unwrap_or_else(|| {
        hostname::get()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    });
    let state_file = args.state_file.unwrap_or_else(|| {
        env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .or_else(|| home::home_dir().map(|home| home.join(".local/state")))
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join("keystone-photos/screenshot-sync.tsv")
    });

    if !directory.is_dir() {
        eprintln!(
            "Screenshot directory does not exist, skipping: {}",
            directory.display()
        );
        return Ok(());
    }
    if let Some(parent) = state_file.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create {}", parent.display()))?;
    }
    if !state_file.exists() {
        fs::write(&state_file, "")
            .with_context(|| format!("Failed to initialize {}", state_file.display()))?;
    }

    let album_id = get_or_create_album_id(&client, &album_name).await?;
    let tags = vec![
        "source:screenshot".to_string(),
        format!("host:{host_name}"),
        format!("account:{account_name}"),
    ];

    let mut had_errors = false;
    let mut found_files = false;
    let mut screenshot_files = fs::read_dir(&directory)
        .with_context(|| format!("Failed to read {}", directory.display()))?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .filter(|path| {
            path.extension()
                .and_then(|ext| ext.to_str())
                .map(|ext| ext.eq_ignore_ascii_case("png"))
                .unwrap_or(false)
        })
        .collect::<Vec<_>>();
    screenshot_files.sort();

    for file in screenshot_files {
        found_files = true;
        let sha256 = file_hash("sha256sum", &file)?;
        if state_has_hash(&state_file, &sha256) {
            continue;
        }

        let sha1 = file_hash("sha1sum", &file)?;
        let created_at = file_timestamp_utc(&file)?;
        let filename = file
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("screenshot.png")
            .to_string();

        let bytes = tokio::fs::read(&file)
            .await
            .with_context(|| format!("Failed to read {}", file.display()))?;
        let part = Part::bytes(bytes)
            .file_name(filename)
            .mime_str("image/png")
            .context("Failed to create multipart upload part")?;
        let form = Form::new()
            .part("assetData", part)
            .text("deviceAssetId", sha256.clone())
            .text("deviceId", host_name.clone())
            .text("fileCreatedAt", created_at.clone())
            .text("fileModifiedAt", created_at);

        let upload_json = match client.post_form("/api/assets", Some(&sha1), form).await {
            Ok(json) => json,
            Err(error) => {
                eprintln!(
                    "Failed to upload screenshot: {} ({})",
                    file.display(),
                    error
                );
                had_errors = true;
                continue;
            }
        };

        let asset_id = upload_json
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let status = upload_json
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();

        if asset_id.is_empty() && status != "duplicate" {
            eprintln!("Upload response missing asset id for: {}", file.display());
            had_errors = true;
            continue;
        }

        if !asset_id.is_empty() {
            if let Err(error) = client
                .post_json(
                    &format!("/api/albums/{album_id}/assets"),
                    &json!({ "ids": [asset_id.clone()] }),
                )
                .await
            {
                eprintln!(
                    "Failed to add screenshot to album '{}': {} ({})",
                    album_name,
                    file.display(),
                    error
                );
                had_errors = true;
                continue;
            }

            if let Err(error) = tag_asset(&client, &asset_id, &tags).await {
                eprintln!(
                    "Warning: failed to tag screenshot asset {} ({})",
                    asset_id, error
                );
            }
        }

        record_state(
            &state_file,
            &sha256,
            if asset_id.is_empty() {
                "duplicate"
            } else {
                &asset_id
            },
            &file,
        )?;
    }

    if !found_files {
        eprintln!("No screenshots found in {}", directory.display());
    }
    if had_errors {
        anyhow::bail!("one or more screenshot uploads failed")
    }
    Ok(())
}

pub async fn execute_command(command: ScreenshotsCommand) -> Result<()> {
    match command {
        ScreenshotsCommand::Sync(args) => run_sync(args).await,
    }
}
