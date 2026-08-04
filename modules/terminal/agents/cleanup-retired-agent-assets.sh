#!/usr/bin/env bash
set -euo pipefail

agents_root="${1:?usage: cleanup-retired-agent-assets AGENTS_ROOT USER_HOME}"
user_home="${2:?usage: cleanup-retired-agent-assets AGENTS_ROOT USER_HOME}"

remove_legacy_skill() {
  local skill_name="$1"
  local expected_heading="$2"
  local skill_dir="$agents_root/skills/$skill_name"
  local skill_file="$skill_dir/SKILL.md"

  if [[ -f "$skill_file" ]] \
    && [[ "$(head -n 1 "$skill_file")" == "---" ]] \
    && grep -Fxq "name: $skill_name" "$skill_file" \
    && grep -Fxq "$expected_heading" "$skill_file"; then
    rm -rf "$skill_dir"
  fi
}

remove_legacy_skill deepwork "# DeepWork workflow manager"
remove_legacy_skill deepplan "# DeepPlan"
remove_legacy_skill deepreviews "# DeepWork Reviews — How It Works"
remove_legacy_skill deepschema "# DeepSchema"
remove_legacy_skill review "# DeepWork Review"
remove_legacy_skill configure-reviews "# Configure DeepWork Reviews"

gemini_command="$user_home/.gemini/commands/deepwork.toml"
if [[ -f "$gemini_command" ]] \
  && grep -Fxq 'description = "Start or continue DeepWork workflows using MCP tools"' "$gemini_command" \
  && grep -Fq "# DeepWork" "$gemini_command"; then
  rm -f "$gemini_command"
fi
