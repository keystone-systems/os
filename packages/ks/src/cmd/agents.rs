//! `ks agents` command — manage agent pause state.

use anyhow::{anyhow, Context, Result};
use std::process::{Command, Stdio};

fn known_agents_list() -> Result<Vec<String>> {
    let output = Command::new("agentctl")
        .output()
        .context("agentctl is not available in PATH")?;

    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let Some(line) = combined
        .lines()
        .find_map(|line| line.strip_prefix("Known agents: "))
    else {
        return Err(anyhow!(
            "could not discover configured agents from agentctl"
        ));
    };

    let agents = line
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .collect::<Vec<_>>();

    if agents.is_empty() {
        return Err(anyhow!(
            "could not discover configured agents from agentctl"
        ));
    }

    Ok(agents)
}

fn resolve_targets(target: &str) -> Result<Vec<String>> {
    if target == "all" {
        return known_agents_list();
    }

    let agents = known_agents_list()?;
    if agents.iter().any(|agent| agent == target) {
        return Ok(vec![target.to_string()]);
    }

    Err(anyhow!(
        "unknown agent '{}'. Run 'agentctl' to see configured agents.",
        target
    ))
}

fn run_agentctl(agent: &str, args: &[&str]) -> Result<bool> {
    let status = Command::new("agentctl")
        .arg(agent)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("Failed to run agentctl for {}", agent))?;

    Ok(status.success())
}

pub fn execute(action: &str, target: &str, reason: Option<&str>) -> Result<()> {
    let targets = resolve_targets(target)?;
    let mut failed = false;

    for agent in targets {
        let ok = match action {
            "pause" => {
                let mut args = vec!["pause"];
                if let Some(reason) = reason.filter(|value| !value.is_empty()) {
                    args.push(reason);
                }
                run_agentctl(&agent, &args)?
            }
            "resume" => run_agentctl(&agent, &["resume"])?,
            "status" => run_agentctl(&agent, &["paused"])?,
            other => anyhow::bail!("unknown agents subcommand '{}'", other),
        };

        if !ok {
            failed = true;
        }
    }

    if failed {
        std::process::exit(1);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn parses_known_agents_line() {
        let agents = "Known agents: alpha, beta, gamma"
            .strip_prefix("Known agents: ")
            .unwrap()
            .split(',')
            .map(str::trim)
            .collect::<Vec<_>>();
        assert_eq!(agents, vec!["alpha", "beta", "gamma"]);
    }
}
