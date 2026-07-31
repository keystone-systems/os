# Podman-based sandboxing for AI coding agents.
#
# See conventions/process.sandbox-agent.md
# See conventions/tool.cli-coding-agents.md
#
# Exports pre-resolved Nix store paths as session variables so that
# podman-agent can mount them directly into containers, skipping the
# GitHub flake-resolution round-trip on every launch.  The env vars
# are optional — podman-agent falls back to `nix build` when unset.
{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.sandbox;
  ksSystemsCache =
    if osConfig != null then
      attrByPath [ "keystone" "os" "binaryCaches" "ksSystems" ] null osConfig
    else
      null;
in
{
  options.keystone.terminal.sandbox = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Podman-based sandboxing for AI coding agents (podman-agent) by default";
    };

    memory = mkOption {
      type = types.str;
      default = "4g";
      description = "Container memory limit (e.g., '4g', '8g')";
    };

    cpus = mkOption {
      type = types.str;
      default = "4";
      description = "Container CPU limit";
    };

    volumeName = mkOption {
      type = types.str;
      default = "nix-agent-store";
      description = "Podman named volume for persistent /nix store";
    };

    # TODO: Add push support so containers can populate the cache after builds
    extraSubstituters = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "https://cache.example.com" ];
      description = "Additional Nix substituters (binary caches) available inside the container.";
    };

    extraTrustedPublicKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "cache.example.com-1:AAAA...=" ];
      description = "Public keys for verifying store path signatures from extra substituters.";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) (mkMerge [
    (mkIf (ksSystemsCache != null && ksSystemsCache.enable) {
      # Keep sandboxed agent builds aligned with the system-level shared cache.
      keystone.terminal.sandbox.extraSubstituters = mkBefore [ ksSystemsCache.url ];
      keystone.terminal.sandbox.extraTrustedPublicKeys = mkBefore [ ksSystemsCache.publicKey ];
    })
    {
      home.packages = [
        pkgs.keystone.podman-agent
      ];

      home.sessionVariables = {
        PODMAN_AGENT_MEMORY = cfg.memory;
        PODMAN_AGENT_CPUS = cfg.cpus;
        PODMAN_AGENT_VOLUME = cfg.volumeName;

        # Pre-resolved store paths — lets podman-agent skip GitHub
        # flake resolution and use these paths directly.
        PODMAN_AGENT_CLAUDE_CODE_PATH = "${pkgs.keystone.claude-code}";
        PODMAN_AGENT_GEMINI_CLI_PATH = "${pkgs.keystone.gemini-cli}";
        PODMAN_AGENT_CODEX_PATH = "${pkgs.keystone.codex}";
        PODMAN_AGENT_OPENCODE_PATH = "${pkgs.keystone.opencode}";
        PODMAN_AGENT_GH_PATH = "${pkgs.gh}";
        PODMAN_AGENT_RIPGREP_PATH = "${pkgs.ripgrep}";
        PODMAN_AGENT_PROCPS_PATH = "${pkgs.procps}";

        # MCP server store paths — lets podman-agent mount these into containers
        PODMAN_AGENT_DEEPWORK_PATH = "${pkgs.keystone.deepwork}";
        PODMAN_AGENT_CHROME_MCP_PATH = "${pkgs.keystone.chrome-devtools-mcp}";
      }
      // optionalAttrs (cfg.extraSubstituters != [ ]) {
        PODMAN_AGENT_EXTRA_SUBSTITUTERS = concatStringsSep " " cfg.extraSubstituters;
      }
      // optionalAttrs (cfg.extraTrustedPublicKeys != [ ]) {
        PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS = concatStringsSep " " cfg.extraTrustedPublicKeys;
      };
    }
  ]);
}
