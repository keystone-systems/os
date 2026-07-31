# CLI Coding Agent MCP Configuration
#
# Generates MCP server configs at each AI coding tool's expected path
# (~/.claude.json, ~/.gemini/settings.json, ~/.codex/config.toml,
# ~/.config/opencode/opencode.json).
#
# See conventions/tool.cli-coding-agents.md
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.keystone.terminal.cliCodingAgents;
  terminalCfg = config.keystone.terminal;
  deepworkEnabled = terminalCfg.ai.enable && terminalCfg.deepwork.enable;
  deepworkAdditionalJobsFolders =
    config.home.sessionVariables.DEEPWORK_ADDITIONAL_JOBS_FOLDERS or null;

  mkDeepworkServer =
    platform:
    {
      command = "${pkgs.keystone.deepwork}/bin/deepwork";
      args = [
        "serve"
        "--path"
        "."
        "--platform"
        platform
      ];
    }
    // optionalAttrs (deepworkAdditionalJobsFolders != null && deepworkAdditionalJobsFolders != "") {
      env = {
        DEEPWORK_ADDITIONAL_JOBS_FOLDERS = deepworkAdditionalJobsFolders;
      };
    };

  claudeMcpServers =
    cfg.mcpServers
    // optionalAttrs deepworkEnabled {
      deepwork = mkDeepworkServer "claude";
    };

  geminiMcpServers =
    cfg.mcpServers
    // optionalAttrs deepworkEnabled {
      deepwork = mkDeepworkServer "gemini";
    };

  codexMcpServers =
    cfg.mcpServers
    // optionalAttrs deepworkEnabled {
      deepwork = mkDeepworkServer "codex";
    };

  opencodeMcpServers =
    cfg.mcpServers
    // optionalAttrs deepworkEnabled {
      deepwork = mkDeepworkServer "opencode";
    };

  # Nix-managed MCP servers as a JSON file in the store, used by the
  # activation script to merge into the runtime ~/.claude.json.
  claudeJsonMcpServers = pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON claudeMcpServers);

  # Nix-managed settings for Gemini CLI
  geminiJsonSettings = pkgs.writeText "gemini-settings.json" (
    builtins.toJSON {
      mcpServers = geminiMcpServers;
      context = {
        fileFiltering = {
          inherit (cfg) respectGitIgnore;
        };
      };
    }
  );

  codexJsonMcpServers = pkgs.writeText "codex-mcp-servers.json" (builtins.toJSON codexMcpServers);

  # Nix-managed settings for OpenCode
  opencodeJsonSettings = pkgs.writeText "opencode-settings.json" (
    builtins.toJSON {
      mcp = mapAttrs (
        _: srv:
        {
          type = "local";
          command = [ srv.command ] ++ srv.args;
          enabled = true;
        }
        // optionalAttrs (srv ? env && srv.env != { }) {
          inherit (srv) env;
        }
      ) opencodeMcpServers;
    }
  );
in
{
  options.keystone.terminal.cliCodingAgents = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "global configurations for AI coding agent CLIs";
    };

    mcpServers = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            command = mkOption {
              type = types.str;
              description = "The command to run the MCP server.";
            };
            args = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Arguments to pass to the MCP server command.";
            };
            env = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Environment variables for the MCP server.
                WARNING: These values are stored in the Nix store in plain text and are world-readable.
                DO NOT put secrets (API keys, tokens) here. Use agent-specific environment variables
                or credential managers instead.
              '';
            };
          };
        }
      );
      default = { };
      description = "MCP servers to configure globally across supported AI CLIs.";
    };

    generatedMcpServers = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      internal = true;
      description = "Resolved MCP server definitions emitted by the shared generator for each CLI.";
    };

    respectGitIgnore = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether Gemini CLI should respect .gitignore files.
        Setting this to false may leak ignored secrets into the AI context.
      '';
    };
  };

  config = mkIf (terminalCfg.enable && cfg.enable) {
    keystone.terminal.cliCodingAgents.generatedMcpServers = {
      claude = claudeMcpServers;
      gemini = geminiMcpServers;
      codex = codexMcpServers;
      opencode = opencodeMcpServers;
    };

    # Claude Code / Claude Desktop
    # CRITICAL: ~/.claude.json must be a writable regular file, not a Nix store
    # symlink. Claude Code writes runtime state to this file (feature flags,
    # subscription cache, OAuth account, MCP sync). A read-only symlink causes
    # an infinite retry loop that hangs Claude Code forever.
    # Strategy: merge only the mcpServers key from Nix config into the existing
    # file, preserving all Claude Code runtime state.
    home.activation.claudeJsonConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      claudeJson="$HOME/.claude.json"

      # Remove stale Nix store symlink from previous home-manager generations
      if [ -L "$claudeJson" ]; then
        rm -f "$claudeJson"
      fi

      if [ -f "$claudeJson" ]; then
        # Merge: replace only .mcpServers, preserve all other runtime state
        ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' \
          "$claudeJson" ${claudeJsonMcpServers} > "$claudeJson.tmp" \
          && mv "$claudeJson.tmp" "$claudeJson"
      else
        # First run: create with just MCP servers, Claude Code populates the rest
        ${pkgs.jq}/bin/jq -n --slurpfile s ${claudeJsonMcpServers} '{mcpServers: $s[0]}' \
          > "$claudeJson"
      fi
    '';

    # Gemini CLI
    # CRITICAL: ~/.gemini/settings.json must be a writable regular file.
    # Strategy: merge mcpServers and context settings from Nix config.
    home.activation.geminiSettingsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      geminiSettings="$HOME/.gemini/settings.json"
      mkdir -p "$(dirname "$geminiSettings")"

      # Remove stale Nix store symlink from previous home-manager generations
      if [ -L "$geminiSettings" ]; then
        rm -f "$geminiSettings"
      fi

      if [ -f "$geminiSettings" ]; then
        # Merge: replace mcpServers and context, preserve all other state
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
          "$geminiSettings" ${geminiJsonSettings} > "$geminiSettings.tmp" \
          && mv "$geminiSettings.tmp" "$geminiSettings"
      else
        # First run: create from scratch
        cp ${geminiJsonSettings} "$geminiSettings"
        chmod 644 "$geminiSettings"
      fi
    '';

    # OpenCode
    # CRITICAL: ~/.config/opencode/opencode.json must be a writable regular file.
    # Strategy: merge mcp configuration from Nix config.
    home.activation.opencodeSettingsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      opencodeSettings="$HOME/.config/opencode/opencode.json"
      mkdir -p "$(dirname "$opencodeSettings")"

      # Remove stale Nix store symlink from previous home-manager generations
      if [ -L "$opencodeSettings" ]; then
        rm -f "$opencodeSettings"
      fi

      if [ -f "$opencodeSettings" ]; then
        # Merge: replace .mcp, preserve all other runtime state
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
          "$opencodeSettings" ${opencodeJsonSettings} > "$opencodeSettings.tmp" \
          && mv "$opencodeSettings.tmp" "$opencodeSettings"
      else
        # First run: create from scratch
        cp ${opencodeJsonSettings} "$opencodeSettings"
        chmod 644 "$opencodeSettings"
      fi
    '';

    # Codex
    # CRITICAL: ~/.codex/config.toml must be a writable regular file.
    # Strategy: replace only [mcp_servers], preserve all other runtime state.
    home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            codexConfig="$HOME/.codex/config.toml"
            mkdir -p "$(dirname "$codexConfig")"

            # Remove stale Nix store symlink from previous home-manager generations
            if [ -L "$codexConfig" ]; then
              rm -f "$codexConfig"
            fi

            if [ -f "$codexConfig" ]; then
              CODEX_CONFIG="$codexConfig" MANAGED_MCP="${codexJsonMcpServers}" ${pkgs.python3}/bin/python - <<'PY'
      import json
      import os
      import tomllib
      from pathlib import Path

      config_path = Path(os.environ["CODEX_CONFIG"]).expanduser()
      managed_path = Path(os.environ["MANAGED_MCP"])

      with managed_path.open("r", encoding="utf-8") as fh:
          managed_mcp = json.load(fh)

      with config_path.open("rb") as fh:
          data = tomllib.load(fh)

      data["mcp_servers"] = managed_mcp

      def format_key(key):
          if key.replace("_", "").replace("-", "").isalnum():
              return key
          escaped = key.replace("\\", "\\\\").replace("\"", "\\\"")
          return f'"{escaped}"'

      def format_scalar(value):
          if isinstance(value, bool):
              return "true" if value else "false"
          if isinstance(value, (int, float)):
              return str(value)
          escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
          return f'"{escaped}"'

      def format_inline(value):
          if isinstance(value, list):
            return "[{}]".format(", ".join(format_inline(item) for item in value))
          if isinstance(value, dict):
            items = ", ".join(
              f"{format_key(k)} = {format_inline(v)}" for k, v in value.items()
            )
            return "{ " + items + " }"
          return format_scalar(value)

      def write_table(lines, path, table):
          scalars = []
          child_tables = []
          array_tables = []
          for key, value in table.items():
              if isinstance(value, dict):
                  child_tables.append((key, value))
              elif isinstance(value, list) and value and all(isinstance(item, dict) for item in value):
                  array_tables.append((key, value))
              else:
                  scalars.append((key, value))

          if path:
              lines.append(f"[{'.'.join(format_key(part) for part in path)}]")
          for key, value in scalars:
              lines.append(f"{format_key(key)} = {format_inline(value)}")
          if scalars and (child_tables or array_tables):
              lines.append("")

          for index, (key, value) in enumerate(child_tables):
              write_table(lines, path + [key], value)
              if index != len(child_tables) - 1 or array_tables:
                  lines.append("")

          for table_index, (key, entries) in enumerate(array_tables):
              for entry_index, entry in enumerate(entries):
                  lines.append(f"[[{'.'.join(format_key(part) for part in path + [key])}]]")
                  nested_lines = []
                  write_table(nested_lines, [], entry)
                  lines.extend(nested_lines)
                  if entry_index != len(entries) - 1:
                      lines.append("")
              if table_index != len(array_tables) - 1:
                  lines.append("")

      lines = []
      write_table(lines, [], data)
      output = "\n".join(line for line in lines if line is not None).strip() + "\n"
      tmp_path = config_path.with_suffix(".tmp")
      tmp_path.write_text(output, encoding="utf-8")
      tmp_path.replace(config_path)
      PY
            else
              cat > "$codexConfig" <<'EOF'
      [mcp_servers]
      EOF
              CODEX_CONFIG="$codexConfig" MANAGED_MCP="${codexJsonMcpServers}" ${pkgs.python3}/bin/python - <<'PY'
      import json
      import os
      from pathlib import Path

      config_path = Path(os.environ["CODEX_CONFIG"]).expanduser()
      managed_path = Path(os.environ["MANAGED_MCP"])

      with managed_path.open("r", encoding="utf-8") as fh:
          managed_mcp = json.load(fh)

      def format_key(key):
          if key.replace("_", "").replace("-", "").isalnum():
              return key
          escaped = key.replace("\\", "\\\\").replace("\"", "\\\"")
          return f'"{escaped}"'

      def format_scalar(value):
          if isinstance(value, bool):
              return "true" if value else "false"
          if isinstance(value, (int, float)):
              return str(value)
          escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
          return f'"{escaped}"'

      def format_inline(value):
          if isinstance(value, list):
              return "[{}]".format(", ".join(format_inline(item) for item in value))
          if isinstance(value, dict):
              items = ", ".join(
                  f"{format_key(k)} = {format_inline(v)}" for k, v in value.items()
              )
              return "{ " + items + " }"
          return format_scalar(value)

      lines = []
      for name, server in managed_mcp.items():
          lines.append(f"[mcp_servers.{format_key(name)}]")
          for key, value in server.items():
              lines.append(f"{format_key(key)} = {format_inline(value)}")
          lines.append("")

      config_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
      PY
              chmod 644 "$codexConfig"
            fi
    '';
  };
}
