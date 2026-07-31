# Home-manager terminal integration for agents.
#
# See conventions/tool.cli-coding-agents.md
# Implements REQ-007 (OS Agents)
# Implements REQ-017 (Conventions and Grafana MCP)
#
# NOTE: This must be a separate mkMerge entry, not merged with // into the
# mkIf block above. Using // on a mkIf value silently drops the merged keys
# because the module system only reads the mkIf's `content` attribute.
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
  inherit (agentsLib)
    osCfg
    cfg
    localAgents
    topDomain
    agentPublicKey
    allKeysForAgent
    ;
  inherit (agentsLib) globalAgentChromeDebugPort;
in
{
  config = optionalAttrs (options ? home-manager) {
    home-manager =
      mkIf (osCfg.enable && localAgents != { } && any (a: a.terminal.enable) (attrValues localAgents))
        {
          users = mapAttrs' (
            name: agentCfg:
            let
              username = "agent-${name}";
              ollamaHostMeta = config.keystone.hosts.${config.networking.hostName} or { };
              ollamaHostAddress =
                if (ollamaHostMeta.tailscaleIP or null) != null then
                  ollamaHostMeta.tailscaleIP
                else
                  config.networking.hostName;
              # Capture NixOS system pkgs before they're shadowed by home-manager's pkgs
              # argument. The keystone overlay is applied at the system level, so we use
              # this to resolve keystone package store paths for MCP server commands.
              sysPkgs = pkgs;
            in
            nameValuePair username (
              { pkgs, osConfig, ... }:
              {
                # notes and terminal are provided as sharedModules by
                # nixosModules.operating-system. keystoneInputs is set by
                # homeModules.terminal — do not redeclare either here.

                # NOTE: Do NOT wrap in mkIf — see users.nix for explanation.
                keystone.terminal = {
                  enable = mkDefault agentCfg.terminal.enable;
                  conventions.archetype = mkDefault agentCfg.archetype;
                  aiExtensions.enable = mkDefault (agentCfg.capabilities != [ ]);
                  aiExtensions.capabilities = mkDefault agentCfg.capabilities;

                  # development and repos are no longer bridged here;
                  # they are inherited globally from keystone.development
                  # and keystone.repos which are now shared options.

                  git =
                    let
                      pubKey = agentPublicKey name;
                    in
                    {
                      userName = mkDefault agentCfg.fullName;
                      userEmail = mkDefault (
                        if agentCfg.email != null then
                          agentCfg.email
                        else
                          "${username}@${if topDomain != null then topDomain else "localhost"}"
                      );
                      # Bridge SSH keys from keystone.keys for allowed_signers + signing
                      sshPublicKeys = mkDefault (allKeysForAgent name);
                      signingKey = mkDefault (if pubKey != null then "key::${pubKey}" else "~/.ssh/id_ed25519");
                      forgejo = {
                        enable = mkDefault (config.keystone.services.git.host != null);
                        domain = mkDefault config.keystone.services.git.domain;
                        sshPort = mkDefault config.keystone.services.git.sshPort;
                        # Use agent's Forgejo username, not the system username
                        username = mkDefault agentCfg.git.username;
                      };
                    };
                  mail = {
                    enable = mkDefault true;
                    accountName = mkDefault name;
                    email = mkDefault (
                      if agentCfg.mail.address != null then
                        agentCfg.mail.address
                      else
                        "${username}@${if topDomain != null then topDomain else "localhost"}"
                    );
                    displayName = mkDefault agentCfg.fullName;
                    login = mkDefault username;
                    host = mkDefault (if topDomain != null then "mail.${topDomain}" else "");
                    # CRITICAL: agenix secrets and most editors add a trailing newline.
                    # Stalwart rejects passwords with trailing whitespace, so we must
                    # strip it. Without this, IMAP/SMTP auth fails.
                    # tr is available via the agent's home-manager profile PATH (coreutils).
                    passwordCommand = mkDefault "tr -d '\\n' < /run/agenix/agent-${name}-mail-password";
                    imap.port = mkDefault agentCfg.mail.imap.port;
                    smtp.port = mkDefault agentCfg.mail.smtp.port;
                  };
                  calendar = {
                    enable = mkDefault true;
                    # All credentials auto-derived from mail config above
                  };
                  contacts = {
                    enable = mkDefault true;
                    # All credentials auto-derived from mail config above
                  };
                  ssh.authSock = mkDefault "/run/agent-${name}-ssh-agent/agent.sock";
                  ai.ollama =
                    let
                      hostOllamaCfg = config.keystone.os.services.ollama;
                      defaultModel = if hostOllamaCfg.models == [ ] then null else head hostOllamaCfg.models;
                    in
                    {
                      enable = mkDefault hostOllamaCfg.enable;
                      host = mkDefault "http://${ollamaHostAddress}:${toString hostOllamaCfg.port}";
                      defaultModel = mkDefault defaultModel;
                    };
                  secrets = {
                    enable = mkDefault true;
                    email = mkDefault (
                      if agentCfg.email != null then
                        agentCfg.email
                      else
                        "${username}@${if topDomain != null then topDomain else "localhost"}"
                    );
                    baseUrl = mkDefault (if topDomain != null then "https://vaultwarden.${topDomain}" else "");
                    # Agents are unattended — use a custom pinentry that reads the master
                    # password from the agenix secret instead of prompting interactively.
                    pinentry = pkgs.writeShellScriptBin "rbw-pinentry-agenix" ''
                      echo "OK Pleased to meet you"
                      while IFS= read -r line; do
                        case "$line" in
                          GETPIN)
                            printf "D %s\n" "$(tr -d '\n' < /run/agenix/agent-${name}-bitwarden-password)"
                            echo "OK"
                            ;;
                          BYE)
                            echo "OK closing connection"
                            exit 0
                            ;;
                          *)
                            echo "OK"
                            ;;
                        esac
                      done
                    '';
                  };
                  cliCodingAgents = {
                    enable = mkDefault true;
                    # Agents need to see ignored files (e.g. .agents submodule)
                    respectGitIgnore = mkDefault false;
                    mcpServers = {
                      deepwork = {
                        command = "${sysPkgs.keystone.deepwork}/bin/deepwork";
                        args = [
                          "serve"
                          "--path"
                          "."
                          "--platform"
                          "claude"
                        ];
                      };
                    }
                    // optionalAttrs (agentCfg.chrome.enable && agentCfg.chrome.mcp.enable) {
                      chrome-devtools = {
                        command = "${sysPkgs.keystone.chrome-devtools-mcp}/bin/chrome-devtools-mcp";
                        args = [
                          "--browserUrl"
                          "http://127.0.0.1:${toString (globalAgentChromeDebugPort name agentCfg)}"
                        ];
                      };
                    }
                    // mapAttrs (
                      _: srv:
                      {
                        inherit (srv) command args;
                      }
                      // optionalAttrs (srv.env != { }) {
                        inherit (srv) env;
                      }
                    ) agentCfg.mcp.servers;
                  };
                };

                # Bridge agent notes config to the home-manager notes module.
                # Agents get both zk scaffolding and repo-sync via this module.
                keystone.notes = mkIf agentCfg.terminal.enable {
                  enable = mkDefault true;
                  repo = mkDefault agentCfg.notes.repo;
                  path = mkDefault agentCfg.notes.path;
                  zk.enable = mkDefault true;
                };

                # Delegate Grafana MCP to the terminal module (REQ-017.10, REQ-017.11).
                keystone.terminal.grafana.mcp = mkIf agentCfg.grafana.mcp.enable {
                  enable = true;
                  url = agentCfg.grafana.mcp.url;
                };

                # Add chrome-devtools-mcp to PATH when chrome MCP is enabled.
                # The MCP server command in cliCodingAgents uses an absolute Nix store
                # path, but agents may also invoke the binary directly (e.g. diagnostics,
                # `which chrome-devtools-mcp`). Adding it to home.packages satisfies both.
                home.packages = [
                  sysPkgs.keystone.slidev
                ]
                ++ optionals (agentCfg.chrome.enable && agentCfg.chrome.mcp.enable) [
                  sysPkgs.keystone.chrome-devtools-mcp
                ];

                home.stateVersion = config.system.stateVersion;
              }
            )
          ) (filterAttrs (_: a: a.terminal.enable) localAgents);
        };
  };
}
