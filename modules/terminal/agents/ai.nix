# AI coding assistants (Claude Code, Gemini CLI, Codex, OpenCode)
#
# Gated by keystone.terminal.ai.enable (default: true) so environments
# like the installer ISO can opt out of heavy AI tooling while still
# using the rest of keystone.terminal.
#
# Optional Ollama integration (keystone.terminal.ai.ollama) adds:
# - ollama CLI for model management
# - claude-local / opencode-local shell wrappers pointing at local Ollama
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  ollamaCfg = cfg.ai.ollama;
in
{
  options.keystone.terminal.ai = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI coding assistants (Claude Code, Gemini CLI, Codex, OpenCode)";
    };

    ollama = {
      enable = mkEnableOption "local Ollama integration for AI tools";

      host = mkOption {
        type = types.str;
        default = "http://localhost:11434";
        description = "Ollama API URL. Set to Tailscale hostname for cross-machine access.";
        example = "http://ncrmro-workstation:11434";
      };

      defaultModel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default model name for local AI wrappers.";
        example = "qwen3:32b";
      };
    };
  };

  config = mkIf (cfg.enable && cfg.ai.enable) {
    home.packages = [
      # Claude Code - AI-powered CLI assistant from Anthropic
      # https://claude.com/claude-code
      pkgs.keystone.claude-code

      # Gemini CLI - Google's AI assistant
      pkgs.keystone.gemini-cli

      # Codex - OpenAI's lightweight coding agent
      pkgs.keystone.codex

      # OpenCode - Open-source AI coding agent
      pkgs.keystone.opencode

    ]
    ++ optionals cfg.deepwork.enable [
      # DeepWork - workflow orchestration MCP server
      pkgs.keystone.deepwork
    ]
    ++ optionals ollamaCfg.enable [
      # Ollama CLI for model management (ollama pull, list, run)
      pkgs.ollama
    ];

    home.sessionVariables = mkIf ollamaCfg.enable {
      OLLAMA_HOST = ollamaCfg.host;
    };

    programs.zsh.initContent = mkIf ollamaCfg.enable (
      let
        modelFlag = if ollamaCfg.defaultModel != null then " --model ${ollamaCfg.defaultModel}" else "";
        defaultClaudeModel = if ollamaCfg.defaultModel != null then ollamaCfg.defaultModel else "";
        defaultOpenCodeModel = if ollamaCfg.defaultModel != null then ollamaCfg.defaultModel else "";
      in
      ''
        # Local Ollama wrappers mirror the first-class local launch behavior used
        # by ks and agentctl. Hosted commands (claude, opencode) remain unchanged.
        _keystone_has_model_arg() {
          local arg
          for arg in "$@"; do
            case "$arg" in
              --model|--model=*) return 0 ;;
            esac
          done
          return 1
        }

        claude-local() {
          if ! _keystone_has_model_arg "$@" && [[ -z "${defaultClaudeModel}" ]]; then
            echo "Error: no local model was provided and keystone.terminal.ai.ollama.defaultModel is not set." >&2
            return 1
          fi
          ANTHROPIC_BASE_URL="${ollamaCfg.host}" \
          ANTHROPIC_AUTH_TOKEN="ollama" \
            claude${modelFlag} "$@"
        }

        opencode-local() {
          local resolved_model="${defaultOpenCodeModel}"
          if [[ -z "$resolved_model" ]]; then
            echo "Error: keystone.terminal.ai.ollama.defaultModel is not set for opencode-local." >&2
            return 1
          fi
          OPENCODE_PROVIDER="ollama" \
          OPENCODE_MODEL="$resolved_model" \
          OLLAMA_HOST="${ollamaCfg.host}" \
            opencode "$@"
        }
      ''
    );
  };
}
