# Keystone Terminal Grafana MCP Integration
#
# Provides Grafana MCP server configuration for AI coding tools.
# When enabled, adds the `grafana` MCP server to all configured CLI coding
# agents (Claude Code, Gemini CLI, Codex, OpenCode) and exports the
# GRAFANA_API_KEY environment variable from the agenix runtime secret.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.grafana = {
#   mcp.enable = true;
#   mcp.url = "https://grafana.example.com";
# };
# ```
#
# Implements: https://github.com/ncrmro/keystone/issues/249
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.grafana;
in
{
  options.keystone.terminal.grafana = {
    mcp = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Grafana MCP server for AI coding tools, providing access to Prometheus metrics and Loki logs.";
      };

      url = mkOption {
        type = types.str;
        default = "";
        example = "https://grafana.example.com";
        description = "Grafana URL for the MCP server connection.";
      };
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.mcp.enable) {
    keystone.terminal.cliCodingAgents.mcpServers.grafana = {
      command = "${pkgs.keystone.grafana-mcp}/bin/mcp-grafana";
      args = [ ];
      env = {
        GRAFANA_URL = cfg.mcp.url;
      };
    };

    # Export GRAFANA_API_KEY from agenix secret at shell login.
    # Cannot use home.sessionVariables — the secret is a runtime file, not a Nix store path.
    programs.zsh.initContent = ''
      if [ -f /run/agenix/grafana-api-token ]; then
        export GRAFANA_API_KEY="$(tr -d '\n' < /run/agenix/grafana-api-token)"
      fi
    '';
  };
}
