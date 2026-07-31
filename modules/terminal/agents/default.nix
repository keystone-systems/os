# Aggregates the CLI-coding-agent infrastructure for `keystone.terminal`:
#
#   - ai.nix          — AI assistants (Claude/Gemini/Codex/OpenCode) + Ollama
#   - extensions.nix  — slash-command + skill capability options
#   - assets.nix      — manifest generator + home-manager symlink activation
#   - mcp-configs.nix — MCP server configs for each tool
#
# Source content for skills, commands, and the sync script live alongside
# these modules:
#
#   - templates/  — skill body templates (.template.md) consumed by the
#                   sync script
#   - commands/   — slash-command body markdown
#   - keystone-sync-agent-assets.sh — the manual sync entry point that
#                   reads the manifest and writes the consumer-flake
#                   agents/ tree
#
# Convention reference: conventions/tool.cli-coding-agents.md
# Spec reference: docs/research/agent-skills.md
{
  imports = [
    ./ai.nix
    ./extensions.nix
    ./assets.nix
    ./mcp-configs.nix
  ];
}
