# AI CLI commands and skills for the curated Keystone workflow surface.
#
# This module's sole responsibility is computing two manifest fields:
#   - `resolvedCapabilities` — capability set after merging base/archetype/explicit
#   - `publishedCommands`    — list of slash-command ids for this host
#
# Both are surfaced as internal options that `generated-agent-assets.nix`
# reads when writing `~/.config/keystone/agent-assets.json`. The actual
# rendering of skill content, instruction files, and Claude subagents is
# done by `modules/terminal/agents/keystone-sync-agent-assets.sh`, which
# reads the manifest plus the source templates under
# `modules/terminal/agents/templates/` and `conventions/`.
#
# See conventions/tool.cli-coding-agents.md
# See docs/research/agent-skills.md
{
  config,
  lib,
  ...
}:
with lib;
let
  terminalCfg = config.keystone.terminal;
  cfg = terminalCfg.aiExtensions;
  isDev = config.keystone.development;
  archetype = terminalCfg.conventions.archetype;

  capabilityType = types.enum [
    "ks"
    "ks-dev"
    "assistant"
    "notes"
    "project"
    "engineer"
    "product"
    "project-manager"
    "executive-assistant"
  ];

  baseCapabilities = [
    "ks"
    "assistant"
    "project"
  ];

  explicitCapabilities = filter (capability: capability != "ks-dev" || isDev) cfg.capabilities;

  archetypeCapabilities =
    optionals (archetype == "engineer") [ "engineer" ]
    ++ optionals (archetype == "product") [ "product" ];

  resolvedCapabilities = unique (
    baseCapabilities ++ archetypeCapabilities ++ explicitCapabilities ++ optionals isDev [ "ks-dev" ]
  );

  publishedCommandIds = [
    "ks-system"
  ]
  ++ optionals (elem "assistant" resolvedCapabilities) [ "ks-assistant" ]
  ++ optionals (elem "notes" resolvedCapabilities) [ "ks-notes" ]
  ++ optionals (elem "project" resolvedCapabilities) [ "ks-projects" ]
  ++ optionals (elem "ks-dev" resolvedCapabilities) [ "ks-dev" ]
  ++ optionals (elem "engineer" resolvedCapabilities) [ "ks-engineer" ]
  ++ optionals (elem "product" resolvedCapabilities) [ "ks-product" ]
  ++ optionals (elem "project-manager" resolvedCapabilities) [ "ks-project-manager" ]
  ++ optionals (elem "executive-assistant" resolvedCapabilities) [ "ks-ea" ];
in
{
  options.keystone.terminal.aiExtensions = {
    enable = mkOption {
      type = types.bool;
      default = config.keystone.experimental;
      defaultText = literalExpression "config.keystone.experimental";
      description = ''
        Generate curated Keystone commands and skills for supported AI CLIs
        (EXPERIMENTAL). Auto-enabled when `keystone.experimental = true`.

        Includes the curated skill composition surface (commands, skills,
        colocated conventions, README emission). API may break before the v1
        release stabilises.
      '';
    };

    capabilities = mkOption {
      type = types.listOf capabilityType;
      default = [ ];
      description = ''
        Extra Keystone AI workflow capabilities for this profile. The final
        capability set is merged with terminal defaults, archetype defaults,
        and dev-mode gating.
      '';
    };

    resolvedCapabilities = mkOption {
      type = types.listOf capabilityType;
      default = [ ];
      internal = true;
      description = "Resolved capability set used to generate `/ks` and `/ks-dev`.";
    };

    publishedCommands = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
      description = "Curated Keystone command ids published for this profile.";
    };
  };

  imports = [
    ../../shared/experimental.nix
    (mkAliasOptionModule
      [ "keystone" "terminal" "claudeCodeCommands" "enable" ]
      [ "keystone" "terminal" "aiExtensions" "enable" ]
    )
  ];

  config = mkIf (terminalCfg.enable && terminalCfg.ai.enable && cfg.enable) {
    keystone.terminal.aiExtensions.resolvedCapabilities = resolvedCapabilities;
    keystone.terminal.aiExtensions.publishedCommands = publishedCommandIds;
  };
}
