//! `ks photos` command — Immich-backed photo search and preview.

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use reqwest::multipart::Form;
use serde::Serialize;
use serde_json::{json, Map, Value};
use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use super::util;

#[derive(Parser)]
#[command(name = "ks photos", disable_version_flag = true)]
struct PhotosCli {
    #[command(subcommand)]
    command: PhotosCommand,
}

#[derive(Subcommand)]
pub enum PhotosCommand {
    /// Search Immich assets via metadata and smart search.
    Search(Box<SearchArgs>),
    /// List known Immich people.
    People(PeopleArgs),
    /// Download an Immich asset to the local cache or a path.
    Download(DownloadArgs),
    /// Download an Immich asset and open a desktop preview.
    Preview(PreviewArgs),
}

#[derive(Args, Default)]
pub struct SearchArgs {
    #[arg(long)]
    text: Option<String>,
    #[arg(long)]
    context: Option<String>,
    #[arg(long)]
    ocr: Option<String>,
    #[arg(long)]
    person: Vec<String>,
    #[arg(long)]
    album: Vec<String>,
    #[arg(long)]
    tag: Vec<String>,
    #[arg(long)]
    country: Option<String>,
    #[arg(long)]
    state: Option<String>,
    #[arg(long)]
    city: Option<String>,
    #[arg(long = "camera-make", visible_alias = "make")]
    camera_make: Option<String>,
    #[arg(long = "camera-model", visible_alias = "model")]
    camera_model: Option<String>,
    #[arg(long = "lens-model")]
    lens_model: Option<String>,
    #[arg(long)]
    filename: Option<String>,
    #[arg(long)]
    description: Option<String>,
    #[arg(long = "type")]
    asset_type: Option<String>,
    #[arg(long)]
    kind: Option<String>,
    #[arg(long = "from", visible_alias = "start-date")]
    from_date: Option<String>,
    #[arg(long = "to", visible_alias = "end-date")]
    to_date: Option<String>,
    #[arg(long, default_value_t = 20)]
    limit: u32,
    #[arg(long)]
    json: bool,
}

#[derive(Args, Default)]
pub struct PeopleArgs {
    #[arg(long = "name", visible_alias = "search")]
    name_filter: Option<String>,
    #[arg(long)]
    json: bool,
}

#[derive(Args)]
pub struct DownloadArgs {
    asset_id: String,
    #[arg(long)]
    output: Option<PathBuf>,
    #[arg(long = "print-path")]
    print_path: bool,
}

#[derive(Args)]
pub struct PreviewArgs {
    asset_id: String,
}

#[derive(Clone)]
pub(crate) struct ImmichClient {
    base_url: String,
    api_key: String,
    http: reqwest::Client,
}

#[derive(Debug, Serialize)]
struct SearchLocation {
    country: String,
    state: String,
    city: String,
}

#[derive(Debug, Serialize)]
struct SearchCamera {
    make: String,
    model: String,
    lens_model: String,
}

#[derive(Debug, Serialize)]
struct SearchMatch {
    query: String,
    context: String,
    ocr: String,
    people: Vec<String>,
    albums: Vec<String>,
    tags: Vec<String>,
    kind: String,
    #[serde(rename = "type")]
    asset_type: String,
}

#[derive(Debug, Serialize)]
struct SearchResult {
    id: String,
    filename: String,
    datetime: String,
    #[serde(rename = "assetType")]
    asset_type: String,
    #[serde(rename = "originalPath")]
    original_path: String,
    description: String,
    location: SearchLocation,
    camera: SearchCamera,
    people: Vec<String>,
    tags: Vec<String>,
    #[serde(rename = "thumbnailUrl")]
    thumbnail_url: String,
    #[serde(rename = "originalUrl")]
    original_url: String,
    #[serde(rename = "match")]
    match_info: SearchMatch,
}

#[derive(Debug, Serialize)]
struct PersonEntry {
    id: String,
    name: String,
    #[serde(rename = "isFavorite")]
    is_favorite: bool,
    #[serde(rename = "faceCount")]
    face_count: u64,
}

fn trim_trailing_slash(value: &str) -> String {
    value.trim_end_matches('/').to_string()
}

fn immich_config_dir() -> Result<PathBuf> {
    let base = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| home::home_dir().map(|home| home.join(".config")))
        .context("Failed to determine config directory")?;
    Ok(base.join("immich"))
}

fn load_json_config_value(file: &Path, key: &str) -> Option<String> {
    let contents = fs::read_to_string(file).ok()?;
    let json: Value = serde_json::from_str(&contents).ok()?;
    json.get(key).and_then(Value::as_str).map(str::to_string)
}

fn load_env_config_value(file: &Path, key: &str) -> Option<String> {
    let contents = fs::read_to_string(file).ok()?;
    contents.lines().find_map(|line| {
        let (candidate_key, value) = line.split_once('=')?;
        if candidate_key.trim() != key {
            return None;
        }

        let trimmed = value
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .trim()
            .to_string();
        (!trimmed.is_empty()).then_some(trimmed)
    })
}

fn resolve_immich_url() -> Result<String> {
    if let Ok(url) = env::var("IMMICH_URL") {
        if !url.trim().is_empty() {
            return Ok(trim_trailing_slash(&url));
        }
    }

    let config_dir = immich_config_dir()?;
    let config_json = config_dir.join("config.json");
    for key in ["url", "IMMICH_URL"] {
        if let Some(value) = load_json_config_value(&config_json, key) {
            return Ok(trim_trailing_slash(&value));
        }
    }

    for file in [config_dir.join("env"), config_dir.join(".env")] {
        if let Some(value) = load_env_config_value(&file, "IMMICH_URL") {
            return Ok(trim_trailing_slash(&value));
        }
    }

    anyhow::bail!(
        "missing Immich URL. Set IMMICH_URL or configure ~/.config/immich/config.json or ~/.config/immich/env."
    )
}

fn resolve_immich_api_key() -> Result<String> {
    if let Ok(api_key) = env::var("IMMICH_API_KEY") {
        if !api_key.trim().is_empty() {
            return Ok(api_key);
        }
    }

    let config_dir = immich_config_dir()?;
    let config_json = config_dir.join("config.json");
    for key in ["apiKey", "IMMICH_API_KEY"] {
        if let Some(value) = load_json_config_value(&config_json, key) {
            return Ok(value);
        }
    }

    for file in [config_dir.join("env"), config_dir.join(".env")] {
        if let Some(value) = load_env_config_value(&file, "IMMICH_API_KEY") {
            return Ok(value);
        }
    }

    anyhow::bail!(
        "missing Immich API key. Set IMMICH_API_KEY or configure ~/.config/immich/config.json or ~/.config/immich/env."
    )
}

pub(crate) fn resolve_client(
    url_override: Option<&str>,
    api_key_override: Option<&str>,
) -> Result<ImmichClient> {
    let base_url = url_override
        .map(trim_trailing_slash)
        .filter(|value| !value.is_empty())
        .unwrap_or(resolve_immich_url()?);
    let api_key = api_key_override
        .map(str::to_string)
        .filter(|value| !value.is_empty())
        .unwrap_or(resolve_immich_api_key()?);

    Ok(ImmichClient {
        base_url,
        api_key,
        http: reqwest::Client::new(),
    })
}

impl ImmichClient {
    pub(crate) async fn get_json(&self, path: &str) -> Result<Value> {
        let response = self
            .http
            .get(format!("{}{}", self.base_url, path))
            .header("x-api-key", &self.api_key)
            .header(reqwest::header::ACCEPT, "application/json")
            .send()
            .await
            .with_context(|| format!("Failed to GET {}", path))?
            .error_for_status()
            .with_context(|| format!("Immich GET {} failed", path))?;

        response
            .json()
            .await
            .context("Failed to parse Immich JSON response")
    }

    pub(crate) async fn post_json(&self, path: &str, body: &Value) -> Result<Value> {
        let response = self
            .http
            .post(format!("{}{}", self.base_url, path))
            .header("x-api-key", &self.api_key)
            .header(reqwest::header::ACCEPT, "application/json")
            .json(body)
            .send()
            .await
            .with_context(|| format!("Failed to POST {}", path))?
            .error_for_status()
            .with_context(|| format!("Immich POST {} failed", path))?;

        response
            .json()
            .await
            .context("Failed to parse Immich JSON response")
    }

    pub(crate) async fn post_form(
        &self,
        path: &str,
        checksum: Option<&str>,
        form: Form,
    ) -> Result<Value> {
        let mut request = self
            .http
            .post(format!("{}{}", self.base_url, path))
            .header("x-api-key", &self.api_key)
            .header(reqwest::header::ACCEPT, "application/json");
        if let Some(checksum) = checksum {
            request = request.header("x-immich-checksum", checksum);
        }

        let response = request
            .multipart(form)
            .send()
            .await
            .with_context(|| format!("Failed to POST multipart {}", path))?
            .error_for_status()
            .with_context(|| format!("Immich multipart POST {} failed", path))?;

        response
            .json()
            .await
            .context("Failed to parse Immich JSON response")
    }

    pub(crate) async fn download(&self, path: &str, output_path: &Path) -> Result<()> {
        let response = self
            .http
            .get(format!("{}{}", self.base_url, path))
            .header("x-api-key", &self.api_key)
            .header(reqwest::header::ACCEPT, "application/octet-stream")
            .send()
            .await
            .with_context(|| format!("Failed to download {}", path))?
            .error_for_status()
            .with_context(|| format!("Immich download {} failed", path))?;

        let bytes = response
            .bytes()
            .await
            .context("Failed to read downloaded asset")?;
        fs::write(output_path, &bytes)
            .with_context(|| format!("Failed to write {}", output_path.display()))?;
        Ok(())
    }
}

fn source_items<'a>(value: &'a Value, key: &str) -> Vec<&'a Value> {
    if let Some(array) = value.as_array() {
        return array.iter().collect();
    }
    if let Some(array) = value.get(key).and_then(Value::as_array) {
        return array.iter().collect();
    }
    if let Some(array) = value.get("items").and_then(Value::as_array) {
        return array.iter().collect();
    }
    Vec::new()
}

fn collect_strings_from_field(
    item: &Value,
    array_field: &str,
    value_fields: &[&str],
) -> Vec<String> {
    let mut values = BTreeSet::new();
    for entry in item
        .get(array_field)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        for field in value_fields {
            if let Some(value) = entry.get(*field).and_then(Value::as_str) {
                if !value.is_empty() {
                    values.insert(value.to_string());
                    break;
                }
            }
        }
    }
    values.into_iter().collect()
}

fn match_name(candidate: &str, desired: &[String]) -> bool {
    let candidate = candidate.to_ascii_lowercase();
    desired
        .iter()
        .map(|name| name.to_ascii_lowercase())
        .any(|wanted| candidate == wanted || candidate.contains(&wanted))
}

async fn resolve_named_ids(
    client: &ImmichClient,
    path: &str,
    key: &str,
    names: &[String],
) -> Result<Vec<String>> {
    if names.is_empty() {
        return Ok(Vec::new());
    }

    let json = client.get_json(path).await?;
    let mut ids = BTreeSet::new();
    for item in source_items(&json, key) {
        let candidate = match key {
            "people" => item.get("name").and_then(Value::as_str).unwrap_or_default(),
            "albums" => item
                .get("albumName")
                .and_then(Value::as_str)
                .unwrap_or_default(),
            "tags" => item
                .get("value")
                .and_then(Value::as_str)
                .or_else(|| item.get("name").and_then(Value::as_str))
                .unwrap_or_default(),
            _ => "",
        };
        if candidate.is_empty() || !match_name(candidate, names) {
            continue;
        }
        if let Some(id) = item.get("id").and_then(Value::as_str) {
            ids.insert(id.to_string());
        }
    }

    Ok(ids.into_iter().collect())
}

fn map_type(value: Option<&str>) -> Result<Option<String>> {
    match value.unwrap_or_default() {
        "" => Ok(None),
        "photo" | "image" | "screenshot" => Ok(Some("IMAGE".to_string())),
        "video" => Ok(Some("VIDEO".to_string())),
        other => anyhow::bail!(
            "unsupported --type '{}'. Use photo, screenshot, image, or video.",
            other
        ),
    }
}

fn date_to_start(value: &str) -> String {
    format!("{value}T00:00:00.000Z")
}

fn date_to_end(value: &str) -> String {
    format!("{value}T23:59:59.999Z")
}

fn build_search_query(text: &str, kind: Option<&str>) -> Result<String> {
    match kind.unwrap_or_default() {
        "" => Ok(text.to_string()),
        "business-card" => Ok(format!(
            "{text} business card contact card company email phone title website"
        )),
        other => anyhow::bail!(
            "unsupported --kind '{}'. Supported values: business-card.",
            other
        ),
    }
}

fn screenshot_like(filename: &str, original_path: &str) -> bool {
    let haystack = format!("{} {}", filename, original_path).to_ascii_lowercase();
    [
        "screenshot",
        "screen shot",
        "screen-shot",
        "screen_shot",
        "capture",
    ]
    .iter()
    .any(|needle| haystack.contains(needle))
}

fn normalize_search_results(
    client: &ImmichClient,
    raw_response: &Value,
    args: &SearchArgs,
    query_text: &str,
) -> Vec<SearchResult> {
    let source_assets = if let Some(array) = raw_response
        .get("assets")
        .and_then(|assets| assets.get("items"))
        .and_then(Value::as_array)
    {
        array.iter().collect::<Vec<_>>()
    } else if let Some(array) = raw_response.get("assets").and_then(Value::as_array) {
        array.iter().collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    let mut results = Vec::new();
    for item in source_assets {
        let id = item
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        if id.is_empty() {
            continue;
        }

        let filename = item
            .get("originalFileName")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let original_path = item
            .get("originalPath")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        if args.asset_type.as_deref() == Some("screenshot")
            && !screenshot_like(&filename, &original_path)
        {
            continue;
        }

        let description = item
            .get("exifInfo")
            .and_then(|value| value.get("description"))
            .and_then(Value::as_str)
            .or_else(|| item.get("description").and_then(Value::as_str))
            .unwrap_or_default()
            .to_string();

        let filename_ok = args.filename.as_deref().is_none_or(|filter| {
            filename
                .to_ascii_lowercase()
                .contains(&filter.to_ascii_lowercase())
        });
        let description_ok = args.description.as_deref().is_none_or(|filter| {
            description
                .to_ascii_lowercase()
                .contains(&filter.to_ascii_lowercase())
        });
        if !filename_ok || !description_ok {
            continue;
        }

        let exif = item.get("exifInfo").unwrap_or(&Value::Null);
        results.push(SearchResult {
            id: id.clone(),
            filename,
            datetime: exif
                .get("dateTimeOriginal")
                .and_then(Value::as_str)
                .or_else(|| item.get("fileCreatedAt").and_then(Value::as_str))
                .or_else(|| item.get("createdAt").and_then(Value::as_str))
                .or_else(|| item.get("updatedAt").and_then(Value::as_str))
                .unwrap_or_default()
                .to_string(),
            asset_type: item
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            original_path: original_path.clone(),
            description,
            location: SearchLocation {
                country: exif
                    .get("country")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                state: exif
                    .get("state")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                city: exif
                    .get("city")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
            },
            camera: SearchCamera {
                make: exif
                    .get("make")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                model: exif
                    .get("model")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                lens_model: exif
                    .get("lensModel")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
            },
            people: collect_strings_from_field(item, "people", &["name"]),
            tags: collect_strings_from_field(item, "tags", &["value", "name"]),
            thumbnail_url: format!("{}/api/assets/{id}/thumbnail", client.base_url),
            original_url: format!("{}/api/assets/{id}/original", client.base_url),
            match_info: SearchMatch {
                query: query_text.to_string(),
                context: args.context.clone().unwrap_or_default(),
                ocr: args.ocr.clone().unwrap_or_default(),
                people: args.person.clone(),
                albums: args.album.clone(),
                tags: args.tag.clone(),
                kind: args.kind.clone().unwrap_or_default(),
                asset_type: args.asset_type.clone().unwrap_or_default(),
            },
        });
    }

    results
}

fn print_search_results_table(results: &[SearchResult]) {
    if results.is_empty() {
        println!("No results.");
        return;
    }

    println!("ID\tDATE\tTYPE\tFILENAME\tMATCH");
    for result in results {
        let mut match_bits = Vec::new();
        if !result.match_info.query.is_empty() {
            match_bits.push(format!("text={}", result.match_info.query));
        }
        if !result.match_info.context.is_empty() {
            match_bits.push(format!("context={}", result.match_info.context));
        }
        if !result.match_info.ocr.is_empty() {
            match_bits.push(format!("ocr={}", result.match_info.ocr));
        }
        for value in &result.match_info.people {
            match_bits.push(format!("person={value}"));
        }
        for value in &result.match_info.albums {
            match_bits.push(format!("album={value}"));
        }
        for value in &result.match_info.tags {
            match_bits.push(format!("tag={value}"));
        }
        if !result.match_info.kind.is_empty() {
            match_bits.push(format!("kind={}", result.match_info.kind));
        }
        if !result.match_info.asset_type.is_empty() {
            match_bits.push(format!("type={}", result.match_info.asset_type));
        }
        println!(
            "{}\t{}\t{}\t{}\t{}",
            result.id,
            result.datetime,
            result.asset_type,
            result.filename,
            match_bits.join(", ")
        );
    }
}

#[allow(clippy::cognitive_complexity)]
async fn run_search(args: SearchArgs) -> Result<()> {
    let has_filter = args.text.as_deref().is_some_and(|value| !value.is_empty())
        || args
            .context
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args.ocr.as_deref().is_some_and(|value| !value.is_empty())
        || !args.person.is_empty()
        || !args.album.is_empty()
        || !args.tag.is_empty()
        || args
            .country
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args.state.as_deref().is_some_and(|value| !value.is_empty())
        || args.city.as_deref().is_some_and(|value| !value.is_empty())
        || args
            .camera_make
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .camera_model
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .lens_model
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .filename
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .description
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .asset_type
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .from_date
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || args
            .to_date
            .as_deref()
            .is_some_and(|value| !value.is_empty());
    if !has_filter {
        anyhow::bail!("search requires at least one filter.")
    }
    if args.limit == 0 {
        anyhow::bail!("--limit must be at least 1.")
    }
    if args.kind.as_deref() == Some("business-card")
        && args.text.as_deref().unwrap_or_default().is_empty()
        && args.context.as_deref().unwrap_or_default().is_empty()
        && args.ocr.as_deref().unwrap_or_default().is_empty()
    {
        anyhow::bail!("--kind business-card requires --text.")
    }

    let client = resolve_client(None, None)?;
    let person_ids = resolve_named_ids(&client, "/api/people", "people", &args.person).await?;
    let album_ids = resolve_named_ids(&client, "/api/albums", "albums", &args.album).await?;
    let tag_ids = resolve_named_ids(&client, "/api/tags", "tags", &args.tag).await?;

    let mut query_text = args.text.clone().unwrap_or_default();
    if let Some(context) = args.context.as_deref().filter(|value| !value.is_empty()) {
        if !query_text.is_empty() {
            query_text.push(' ');
        }
        query_text.push_str(context);
    }
    if let Some(ocr) = args.ocr.as_deref().filter(|value| !value.is_empty()) {
        if !query_text.is_empty() {
            query_text.push(' ');
        }
        query_text.push_str(ocr);
    }
    query_text = build_search_query(&query_text, args.kind.as_deref())?;

    let mut request = Map::new();
    request.insert("size".to_string(), json!(args.limit));
    request.insert("withExif".to_string(), json!(true));
    if !query_text.is_empty() {
        request.insert("query".to_string(), json!(query_text));
    }
    if let Some(asset_type) = map_type(args.asset_type.as_deref())? {
        request.insert("type".to_string(), json!(asset_type));
    } else if args.kind.as_deref() == Some("business-card") {
        request.insert("type".to_string(), json!("IMAGE"));
    }
    for (key, value) in [
        ("country", args.country.as_deref()),
        ("state", args.state.as_deref()),
        ("city", args.city.as_deref()),
        ("make", args.camera_make.as_deref()),
        ("model", args.camera_model.as_deref()),
        ("lensModel", args.lens_model.as_deref()),
        ("originalFileName", args.filename.as_deref()),
        ("description", args.description.as_deref()),
    ] {
        if let Some(value) = value.filter(|value| !value.is_empty()) {
            request.insert(key.to_string(), json!(value));
        }
    }
    if !person_ids.is_empty() {
        request.insert("personIds".to_string(), json!(person_ids));
    }
    if !album_ids.is_empty() {
        request.insert("albumIds".to_string(), json!(album_ids));
    }
    if !tag_ids.is_empty() {
        request.insert("tagIds".to_string(), json!(tag_ids));
    }
    if let Some(from_date) = args.from_date.as_deref().filter(|value| !value.is_empty()) {
        request.insert("takenAfter".to_string(), json!(date_to_start(from_date)));
    }
    if let Some(to_date) = args.to_date.as_deref().filter(|value| !value.is_empty()) {
        request.insert("takenBefore".to_string(), json!(date_to_end(to_date)));
    }

    let raw_response = if !query_text.is_empty() {
        client
            .post_json("/api/search/smart", &Value::Object(request))
            .await?
    } else {
        client
            .post_json("/api/search/metadata", &Value::Object(request))
            .await?
    };

    let results = normalize_search_results(&client, &raw_response, &args, &query_text);
    if args.json {
        println!("{}", serde_json::to_string_pretty(&results)?);
    } else {
        print_search_results_table(&results);
    }
    Ok(())
}

async fn run_people(args: PeopleArgs) -> Result<()> {
    let client = resolve_client(None, None)?;
    let json = client.get_json("/api/people").await?;
    let mut people = source_items(&json, "people")
        .into_iter()
        .filter_map(|item| {
            let name = item.get("name").and_then(Value::as_str).unwrap_or_default();
            if name.is_empty() {
                return None;
            }
            Some(PersonEntry {
                id: item
                    .get("id")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                name: name.to_string(),
                is_favorite: item
                    .get("isFavorite")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                face_count: if let Some(faces) = item.get("faces").and_then(Value::as_array) {
                    faces.len() as u64
                } else {
                    item.get("faceCount").and_then(Value::as_u64).unwrap_or(0)
                },
            })
        })
        .filter(|person| {
            args.name_filter.as_deref().is_none_or(|filter| {
                person
                    .name
                    .to_ascii_lowercase()
                    .contains(&filter.to_ascii_lowercase())
            })
        })
        .collect::<Vec<_>>();

    people.sort_by_key(|person| person.name.to_ascii_lowercase());

    if args.json {
        println!("{}", serde_json::to_string_pretty(&people)?);
        return Ok(());
    }

    if people.is_empty() {
        println!("No people found.");
        return Ok(());
    }

    println!("ID\tNAME\tFAVORITE\tFACES");
    for person in people {
        println!(
            "{}\t{}\t{}\t{}",
            person.id, person.name, person.is_favorite, person.face_count
        );
    }
    Ok(())
}

fn asset_cache_dir() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| home::home_dir().map(|home| home.join(".cache")))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("keystone-photos/assets")
}

fn asset_filename_from_metadata(metadata: &Value, asset_id: &str) -> String {
    if let Some(name) = metadata.get("originalFileName").and_then(Value::as_str) {
        return name.to_string();
    }
    if let Some(path) = metadata.get("originalPath").and_then(Value::as_str) {
        if let Some(name) = Path::new(path).file_name().and_then(|name| name.to_str()) {
            return name.to_string();
        }
    }
    format!("{asset_id}.bin")
}

fn asset_cache_path(asset_id: &str, metadata: &Value) -> PathBuf {
    let filename = asset_filename_from_metadata(metadata, asset_id)
        .replace('/', "-")
        .replace('\n', "");
    asset_cache_dir().join(format!("{asset_id}-{filename}"))
}

async fn download_asset(
    client: &ImmichClient,
    asset_id: &str,
    output_path: Option<&Path>,
) -> Result<PathBuf> {
    let metadata = client.get_json(&format!("/api/assets/{asset_id}")).await?;
    let final_path = output_path
        .map(PathBuf::from)
        .unwrap_or_else(|| asset_cache_path(asset_id, &metadata));

    if let Some(parent) = final_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create {}", parent.display()))?;
    }

    let needs_download = fs::metadata(&final_path)
        .map(|metadata| metadata.len() == 0)
        .unwrap_or(true);
    if needs_download {
        let temp_output = final_path.with_extension("tmp");
        client
            .download(&format!("/api/assets/{asset_id}/original"), &temp_output)
            .await?;
        fs::rename(&temp_output, &final_path).with_context(|| {
            format!(
                "Failed to move downloaded asset into place: {}",
                final_path.display()
            )
        })?;
    }

    Ok(final_path)
}

fn open_preview_file(path: &Path) -> Result<()> {
    for opener in ["sushi", "loupe", "xdg-open"] {
        if let Some(program) = util::find_executable(opener) {
            let _ = Command::new(program).arg(path).spawn();
            return Ok(());
        }
    }

    anyhow::bail!("no preview-capable opener found. Install sushi, loupe, or xdg-open.")
}

async fn run_download(args: DownloadArgs) -> Result<()> {
    let client = resolve_client(None, None)?;
    let final_path = download_asset(&client, &args.asset_id, args.output.as_deref()).await?;
    if args.print_path || args.output.is_none() {
        println!("{}", final_path.display());
    }
    Ok(())
}

async fn run_preview(args: PreviewArgs) -> Result<()> {
    let client = resolve_client(None, None)?;
    let final_path = download_asset(&client, &args.asset_id, None).await?;
    open_preview_file(&final_path)
}

pub(crate) async fn get_or_create_album_id(
    client: &ImmichClient,
    album_name: &str,
) -> Result<String> {
    let albums = client.get_json("/api/albums").await?;
    for album in source_items(&albums, "albums") {
        if album.get("albumName").and_then(Value::as_str) == Some(album_name) {
            if let Some(id) = album.get("id").and_then(Value::as_str) {
                return Ok(id.to_string());
            }
        }
    }

    let created = client
        .post_json("/api/albums", &json!({ "albumName": album_name }))
        .await?;
    created
        .get("id")
        .and_then(Value::as_str)
        .map(str::to_string)
        .context("Album creation response was missing an id")
}

pub(crate) async fn tag_asset(
    client: &ImmichClient,
    asset_id: &str,
    tags: &[String],
) -> Result<()> {
    if tags.is_empty() {
        return Ok(());
    }

    let upsert = client
        .post_json("/api/tags/upsert", &json!({ "tags": tags }))
        .await?;
    let Some(tag_array) = upsert.as_array() else {
        return Ok(());
    };

    for tag_id in tag_array
        .iter()
        .filter_map(|tag| tag.get("id").and_then(Value::as_str))
    {
        client
            .post_json(
                &format!("/api/tags/{tag_id}/assets"),
                &json!({ "ids": [asset_id] }),
            )
            .await?;
    }
    Ok(())
}

pub async fn execute_command(command: PhotosCommand) -> Result<()> {
    match command {
        PhotosCommand::Search(args) => run_search(*args).await,
        PhotosCommand::People(args) => run_people(args).await,
        PhotosCommand::Download(args) => run_download(args).await,
        PhotosCommand::Preview(args) => run_preview(args).await,
    }
}

pub async fn execute(args: &[String]) -> Result<()> {
    let cli = util::parse_or_exit(PhotosCli::try_parse_from(
        std::iter::once("ks photos".to_string()).chain(args.iter().cloned()),
    ))?;

    execute_command(cli.command).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trims_trailing_slash() {
        assert_eq!(
            trim_trailing_slash("http://immich.local///"),
            "http://immich.local"
        );
    }

    #[test]
    fn business_card_query_expands() {
        assert!(build_search_query("Nick Romero", Some("business-card"))
            .unwrap()
            .contains("business card"));
    }

    #[test]
    fn screenshot_detection_works() {
        assert!(screenshot_like("screenshot-1.png", "/tmp/screenshot-1.png"));
        assert!(!screenshot_like("photo.jpg", "/photos/photo.jpg"));
    }
}
