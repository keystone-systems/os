# agentctl: unified CLI for managing agent services and mail.
# Dispatches to the per-agent Nix store helper via sudo (no SETENV needed).
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg cfg topDomain;
  inherit (agentsLib) globalAgentVncPort agentSvcHelper;
  devScripts = import ../../shared/dev-script-link.nix { inherit lib; };
  inherit (devScripts) mkHomeScriptCommand mkSystemScriptPackage;
  projectIndexHelper = pkgs.writeShellScriptBin "keystone-project-index" (
    builtins.readFile ./scripts/project-index.sh
  );
  agentOllamaConfig =
    name:
    let
      username = "agent-${name}";
      userCfg =
        if config ? home-manager && builtins.hasAttr username config.home-manager.users then
          config.home-manager.users.${username}.keystone.terminal.ai.ollama
        else
          {
            enable = false;
            host = "http://localhost:11434";
            defaultModel = null;
          };
    in
    userCfg;
  agentHelperCases = concatStringsSep "\n" (
    mapAttrsToList (name: _: "    ${name}) HELPER=\"${agentSvcHelper name}\" ;;") cfg
  );
  agentNotesCases = concatStringsSep "\n" (
    mapAttrsToList (name: agentCfg: "    ${name}) NOTES_DIR=\"${agentCfg.notes.path}\" ;;") cfg
  );
  agentVncCases = concatStringsSep "\n" (
    mapAttrsToList (
      name: agentCfg: "    ${name}) VNC_PORT=\"${toString (globalAgentVncPort name agentCfg)}\" ;;"
    ) cfg
  );
  agentHostCases = concatStringsSep "\n" (
    mapAttrsToList (name: agentCfg: "    ${name}) AGENT_HOST=\"${toString agentCfg.host}\" ;;") cfg
  );
  agentOllamaCases = concatStringsSep "\n" (
    mapAttrsToList (
      name: _:
      let
        ollamaCfg = agentOllamaConfig name;
        defaultModel = if ollamaCfg.defaultModel != null then ollamaCfg.defaultModel else "";
      in
      ''
        ${name}) OLLAMA_ENABLED="${boolToString ollamaCfg.enable}"; OLLAMA_HOST="${ollamaCfg.host}"; OLLAMA_DEFAULT_MODEL="${defaultModel}" ;;
      ''
    ) cfg
  );
  mailHost =
    if config.keystone.services.mail.host != null then config.keystone.services.mail.host else "";
  agentProvisionCases = concatStringsSep "\n" (
    mapAttrsToList (
      name: agentCfg:
      "    ${name}) PROVISION_AGENT_HOST=\"${toString agentCfg.host}\"; MAIL_PROVISION=${boolToString agentCfg.mail.provision} ;;"
    ) cfg
  );
  knownAgents = concatStringsSep ", " (attrNames cfg);
  tasksFormatter = ./scripts/tasks-formatter.py;
  agentctlEnv = pkgs.writeText "agentctl-env.sh" ''
        PYTHON3="${pkgs.python3}/bin/python3"
        TASKS_FORMATTER="${tasksFormatter}"
        OPENSSH="${pkgs.openssh}"
        VIRT_VIEWER="${pkgs.virt-viewer}"
        YQ_BIN="${pkgs.yq-go}/bin/yq"
        TOP_DOMAIN="${topDomain}"
        MAIL_HOST="${mailHost}"
        OPENSSL="${pkgs.openssl}"
        COREUTILS="${pkgs.coreutils}"
        GNUGREP="${pkgs.gnugrep}"
        GNUSED="${pkgs.gnused}"
        NIX="${pkgs.nix}"
        PROJECT_PREFS="${pkgs.coreutils}/bin/false"
        ZELLIJ="${pkgs.zellij}/bin/zellij"
        PODMAN_AGENT="${pkgs.keystone.podman-agent}/bin/podman-agent"
        PROJECT_INDEX_HELPER="${projectIndexHelper}/bin/keystone-project-index"
        KNOWN_AGENTS="${knownAgents}"

        set_agent_helper() {
          case "$1" in
    ${agentHelperCases}
            *)
              echo "Error: unknown agent '$1'" >&2
              echo "Known agents: $KNOWN_AGENTS" >&2
              return 1
              ;;
          esac
        }

        set_agent_notes_dir() {
          case "$1" in
    ${agentNotesCases}
          esac
        }

        set_agent_vnc_port() {
          case "$1" in
    ${agentVncCases}
          esac
        }

        set_agent_host() {
          case "$1" in
    ${agentHostCases}
          esac
        }

        set_agent_ollama() {
          case "$1" in
    ${agentOllamaCases}
          esac
        }

        set_agent_provision() {
          case "$1" in
    ${agentProvisionCases}
          esac
        }
  '';
  agentctlPackage = mkSystemScriptPackage {
    inherit config pkgs;
    commandName = "agentctl";
    relativePath = "modules/os/agents/scripts/agentctl.sh";
    nixStorePath = ./scripts/agentctl.sh;
    extraEnvSetup = ''export AGENTCTL_ENV_FILE="${agentctlEnv}"'';
  };
in
{
  config = mkIf (osCfg.enable && cfg != { }) (
    {
      environment.systemPackages =
        let
          # Per-agent wrapper scripts: `drago claude` = `agentctl drago claude`
          agentAliases = mapAttrsToList (
            name: _:
            pkgs.writeShellScriptBin name ''
              exec agentctl "${name}" "$@"
            ''
          ) cfg;
        in
        [ agentctlPackage ] ++ agentAliases;

    }
    // optionalAttrs (options ? home-manager) {
      home-manager.sharedModules = [
        (
          {
            config,
            lib,
            pkgs,
            ...
          }:
          {
            config = lib.mkIf config.keystone.terminal.enable (
              (mkHomeScriptCommand {
                inherit config pkgs;
                commandName = "agentctl";
                relativePath = "modules/os/agents/scripts/agentctl.sh";
                package = agentctlPackage;
                extraEnvSetup = ''export AGENTCTL_ENV_FILE="${agentctlEnv}"'';
              })
              // {
                home.file.".config/keystone/agentctl.env".source = agentctlEnv;
              }
            );
          }
        )
      ];
    }
  );
}
