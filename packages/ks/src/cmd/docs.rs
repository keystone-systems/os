//! `ks docs` command — browse Keystone markdown documentation.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result};

use super::util;
use crate::repo;

const DEFAULT_BG: &str = "#00120c";
const DEFAULT_FG: &str = "#b6bfbc";
const DEFAULT_ACCENT: &str = "#b8a26c";

fn resolve_docs_target(docs_root: &Path, query: &str) -> Result<PathBuf> {
    let path = match query {
        "os" => docs_root.join("os/installation.md"),
        "terminal" => docs_root.join("terminal/terminal.md"),
        "desktop" => docs_root.join("desktop.md"),
        "agents" => docs_root.join("agents/agents.md"),
        other => {
            let direct = docs_root.join(other);
            if direct.is_file() {
                direct
            } else {
                let markdown = docs_root.join(format!("{other}.md"));
                if markdown.is_file() {
                    markdown
                } else {
                    anyhow::bail!("unknown docs topic or path '{other}'. Try: ks docs")
                }
            }
        }
    };

    if !path.is_file() {
        anyhow::bail!("unknown docs topic or path '{}'. Try: ks docs", query)
    }

    Ok(path)
}

fn collect_markdown_files(root: &Path, dir: &Path, files: &mut Vec<String>) -> Result<()> {
    for entry in fs::read_dir(dir).with_context(|| format!("Failed to read {}", dir.display()))? {
        let entry = entry?;
        let path = entry.path();
        let relative = path.strip_prefix(root).unwrap_or(&path);

        if path.is_dir() {
            if relative
                .components()
                .any(|component| component.as_os_str() == ".jekyll-cache")
            {
                continue;
            }
            collect_markdown_files(root, &path, files)?;
            continue;
        }

        if path.extension().and_then(|ext| ext.to_str()) != Some("md") {
            continue;
        }

        files.push(relative.to_string_lossy().replace('\\', "/"));
    }

    Ok(())
}

fn theme_colors() -> (String, String, String) {
    let mut bg = DEFAULT_BG.to_string();
    let mut fg = DEFAULT_FG.to_string();
    let mut accent = DEFAULT_ACCENT.to_string();

    let theme_dir = home::home_dir()
        .unwrap_or_default()
        .join(".config/keystone/current/theme/waybar.css");
    if let Ok(contents) = fs::read_to_string(theme_dir) {
        for line in contents.lines() {
            let line = line.trim();
            if let Some(value) = line.strip_prefix("@define-color background ") {
                bg = value.trim_end_matches(';').trim().to_string();
            } else if let Some(value) = line.strip_prefix("@define-color foreground ") {
                fg = value.trim_end_matches(';').trim().to_string();
            } else if let Some(value) = line.strip_prefix("@define-color gold ") {
                accent = value.trim_end_matches(';').trim().to_string();
            }
        }
    }

    if bg.is_empty() {
        bg = DEFAULT_BG.to_string();
    }
    if fg.is_empty() {
        fg = DEFAULT_FG.to_string();
    }
    if accent.is_empty() {
        accent = DEFAULT_ACCENT.to_string();
    }

    (bg, fg, accent)
}

fn run_glow(target: &Path) -> Result<()> {
    let glow = util::require_executable("glow", "glow is not available in PATH.")?;
    let status = util::run_inherited(
        Command::new(glow).arg(target),
        &format!("Failed to launch glow for {}", target.display()),
    )?;
    util::finish_status(status)
}

fn select_interactive_target(docs_root: &Path) -> Result<Option<PathBuf>> {
    if !util::interactive_terminal() {
        anyhow::bail!("ks docs without a topic requires an interactive terminal")
    }

    let fzf = util::require_executable("fzf", "fzf is not available in PATH.")?;
    let mut files = Vec::new();
    collect_markdown_files(docs_root, docs_root, &mut files)?;
    files.sort();

    let (bg, fg, accent) = theme_colors();
    let colors = format!(
        "bg:{bg},bg+:{bg},fg:{fg},fg+:{fg},hl:{accent},hl+:{accent},border:{accent},label:{accent},prompt:{accent},pointer:{accent},info:{fg},gutter:{bg},separator:{accent},scrollbar:{accent}"
    );

    let mut child = Command::new(fzf)
        .args([
            "--style=full",
            "--layout=reverse",
            "--border=rounded",
            "--border-label= Keystone docs ",
            "--input-label= Filter ",
            "--list-label= Files ",
            "--info=inline-right",
            "--prompt=Keystone docs > ",
            "--color",
            &colors,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .context("Failed to launch fzf")?;

    if let Some(mut stdin) = child.stdin.take() {
        use std::io::Write;
        for file in &files {
            writeln!(stdin, "{file}")?;
        }
    }

    let output = child
        .wait_with_output()
        .context("Failed to read fzf output")?;
    if !output.status.success() {
        if output.status.code() == Some(130) {
            return Ok(None);
        }
        anyhow::bail!("fzf exited with {}", output.status.code().unwrap_or(1))
    }

    let selected = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if selected.is_empty() {
        return Ok(None);
    }

    Ok(Some(docs_root.join(selected)))
}

pub fn execute(topic_or_path: Option<&str>) -> Result<()> {
    let keystone_root = repo::resolve_keystone_repo()?;
    let docs_root = keystone_root.join("docs");

    if let Some(query) = topic_or_path.filter(|value| !value.is_empty()) {
        let target = resolve_docs_target(&docs_root, query)?;
        return run_glow(&target);
    }

    let Some(target) = select_interactive_target(&docs_root)? else {
        return Ok(());
    };

    run_glow(&target)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn resolves_topic_aliases() {
        let tmp = tempdir().unwrap();
        let docs_root = tmp.path();
        fs::create_dir_all(docs_root.join("terminal")).unwrap();
        fs::create_dir_all(docs_root.join("os")).unwrap();
        fs::create_dir_all(docs_root.join("agents")).unwrap();
        fs::write(docs_root.join("terminal/terminal.md"), "").unwrap();
        fs::write(docs_root.join("os/installation.md"), "").unwrap();
        fs::write(docs_root.join("desktop.md"), "").unwrap();
        fs::write(docs_root.join("agents/agents.md"), "").unwrap();

        assert_eq!(
            resolve_docs_target(docs_root, "terminal").unwrap(),
            docs_root.join("terminal/terminal.md")
        );
    }
}
