//! `ks print` command — render markdown to a print-ready PDF.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};

use super::util;

const PRINT_CSS: &str = include_str!("../../print.css");

#[derive(Debug, Clone, PartialEq, Eq)]
struct PrintOptions {
    input_file: PathBuf,
    output_file: PathBuf,
    open_after: bool,
    no_print: bool,
}

fn default_output_path(input_file: &Path) -> PathBuf {
    match input_file.extension().and_then(|ext| ext.to_str()) {
        Some("md") => input_file.with_extension("pdf"),
        _ => PathBuf::from(format!("{}.pdf", input_file.display())),
    }
}

fn select_pdf_engine() -> Result<&'static str> {
    for candidate in ["weasyprint", "wkhtmltopdf", "pdflatex", "xelatex"] {
        if util::find_executable(candidate).is_some() {
            return Ok(candidate);
        }
    }

    anyhow::bail!("No PDF engine found. Install weasyprint, wkhtmltopdf, or a LaTeX distribution.")
}

fn parse_args(args: &[String]) -> Result<PrintOptions> {
    let mut input_file = None;
    let mut output_file = None;
    let mut open_after = false;
    let mut no_print = false;

    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "-o" | "--output" => {
                index += 1;
                let Some(value) = args.get(index) else {
                    anyhow::bail!("--output requires a path")
                };
                output_file = Some(PathBuf::from(value));
            }
            "--open" => {
                open_after = true;
            }
            "--preview" => {
                open_after = true;
                no_print = true;
            }
            "--no-print" => {
                no_print = true;
            }
            "-h" | "--help" => {
                println!(
                    "Usage: ks print <file.md> [-o output.pdf] [--open] [--preview] [--no-print]"
                );
                std::process::exit(0);
            }
            flag if flag.starts_with('-') => anyhow::bail!("Unknown option '{}'", flag),
            value => {
                if input_file.is_some() {
                    anyhow::bail!("Unexpected argument '{}'", value);
                }
                input_file = Some(PathBuf::from(value));
            }
        }
        index += 1;
    }

    let Some(input_file) = input_file else {
        anyhow::bail!("No input file specified.")
    };
    if !input_file.is_file() {
        anyhow::bail!("File not found: {}", input_file.display())
    }

    let output_file = output_file.unwrap_or_else(|| default_output_path(&input_file));
    Ok(PrintOptions {
        input_file,
        output_file,
        open_after,
        no_print,
    })
}

fn temp_css_path() -> PathBuf {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    env::temp_dir().join(format!("ks-print-{}-{timestamp}.css", std::process::id()))
}

pub fn execute(args: &[String]) -> Result<()> {
    let options = parse_args(args)?;
    let engine = select_pdf_engine()?;

    util::require_executable("pandoc", "pandoc is not available in PATH.")?;

    let css_path = temp_css_path();
    fs::write(&css_path, PRINT_CSS)
        .with_context(|| format!("Failed to write {}", css_path.display()))?;

    let status = Command::new("pandoc")
        .arg(&options.input_file)
        .args([
            "--standalone",
            &format!("--pdf-engine={engine}"),
            &format!("--css={}", css_path.display()),
            "-V",
            "colorlinks=false",
            "-o",
        ])
        .arg(&options.output_file)
        .status()
        .context("Failed to run pandoc")?;

    let _ = fs::remove_file(&css_path);
    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    println!("PDF written: {}", options.output_file.display());

    if options.open_after {
        if let Some(opener) = util::find_executable("xdg-open") {
            let _ = Command::new(opener).arg(&options.output_file).spawn();
        }
    }

    if !options.no_print && util::find_executable("lpstat").is_some() {
        let output = Command::new("lpstat")
            .arg("-d")
            .output()
            .context("Failed to query default printer with lpstat")?;
        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if let Some(default_printer) = stdout.split_whitespace().last() {
                let print_status = Command::new("lp")
                    .arg(&options.output_file)
                    .status()
                    .context("Failed to send PDF to printer")?;
                if print_status.success() {
                    println!("Sent to printer: {}", default_printer);
                }
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_output_to_pdf_extension() {
        assert_eq!(
            default_output_path(Path::new("notes.md")),
            PathBuf::from("notes.pdf")
        );
        assert_eq!(
            default_output_path(Path::new("notes")),
            PathBuf::from("notes.pdf")
        );
    }
}
