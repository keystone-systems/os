# Shared helpers, constants, and filtered agent sets for the agents module.
# This is a plain function (not a NixOS module) — each sub-module imports it:
#   let agentsLib = import ./lib.nix { inherit lib config pkgs; };
{
  lib,
  config,
  pkgs,
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.agents;
  keysCfg = config.keystone.keys;
  topDomain = config.keystone.domain;

  # Get an agent's SSH public key from the keystone.keys registry.
  # Agents have exactly one host key — this returns it (or null if not in registry).
  agentPublicKey =
    name:
    let
      registryName = "agent-${name}";
      u = keysCfg.${registryName} or null;
      hostKeys = if u != null then mapAttrsToList (_: h: h.publicKey) u.hosts else [ ];
    in
    if hostKeys != [ ] then head hostKeys else null;

  # All public keys for an agent from the keystone.keys registry
  allKeysForAgent =
    name:
    let
      registryName = "agent-${name}";
    in
    if keysCfg ? ${registryName} then keysCfg.${registryName}.allKeys else [ ];

  # TODO: Re-evaluate agent ZFS home folders. Implementation needs to be reconciled with legacy setups.
  useZfs = osCfg.storage.type == "zfs" && osCfg.storage.enable;

  # Base UID for agent users
  agentUidBase = 4000;

  # Base VNC port for auto-assignment
  vncPortBase = 5900;

  # Base Chrome debug port for auto-assignment
  chromeDebugPortBase = 9222;

  # Base Chrome MCP port for auto-assignment
  chromeMcpPortBase = 3100;

  # Sorted agent names for deterministic UID assignment
  sortedAgentNames = sort lessThan (attrNames cfg);

  # Auto-assign UIDs to agents that don't have explicit ones
  agentWithUid =
    name: agentCfg:
    let
      idx =
        findFirst (i: elemAt sortedAgentNames i == name)
          (throw "agent '${name}' not found in sortedAgentNames")
          (genList (x: x) (length sortedAgentNames));
      autoUid = agentUidBase + 1 + idx;
    in
    agentCfg
    // {
      uid = if agentCfg.uid != null then agentCfg.uid else autoUid;
    };

  agentsWithUids = mapAttrs agentWithUid cfg;

  # SECURITY: Per-agent service helper — sole sudoers target for agent-admins.
  # Without this, SETENV on direct systemctl allows LD_PRELOAD injection as the
  # agent user, exposing SSH keys and mail credentials. The helper hardcodes
  # XDG_RUNTIME_DIR internally and allowlists safe systemctl verbs only.
  agentSvcHelper =
    name:
    let
      resolved = agentsWithUids.${name};
      uid = toString resolved.uid;
    in
    pkgs.runCommand "agent-svc-${name}" { } ''
      cp ${
        pkgs.replaceVars ./scripts/agent-svc.sh {
          agentName = name;
          uid = uid;
          pathPrefix = "/etc/profiles/per-user/agent-${name}/bin:${lib.makeBinPath [ pkgs.nix ]}:/run/current-system/sw/bin";
        }
      } $out
      chmod +x $out
    '';

  # All defined agents get OS users, home directories, services, etc.
  # Feature-specific agent sets (desktop, mail, SSH) are filtered to agents
  # whose `host` matches this machine. A null host means "use the current
  # host/default placement," which keeps the legacy single-host behavior and
  # allows tests and simple configs to omit an explicit host.
  localAgents = filterAttrs (
    _: agentCfg: agentCfg.host == null || agentCfg.host == config.networking.hostName
  ) cfg;

  desktopAgents = filterAttrs (_: agentCfg: agentCfg.desktop.enable) localAgents;
  hasDesktopAgents = desktopAgents != { };

  mailAgents = localAgents;
  hasMailAgents = mailAgents != { };

  sshAgents = localAgents;
  hasSshAgents = sshAgents != { };

  # Sorted desktop agent names for deterministic VNC port assignment
  sortedDesktopAgentNames = sort lessThan (attrNames desktopAgents);

  # Resolve VNC port for a desktop agent (local host perspective)
  agentVncPort =
    name: agentCfg:
    if agentCfg.desktop.vncPort != null then
      agentCfg.desktop.vncPort
    else
      let
        idx = findFirst (
          i: elemAt sortedDesktopAgentNames i == name
        ) (throw "desktop agent '${name}' not found") (genList (x: x) (length sortedDesktopAgentNames));
      in
      vncPortBase + 1 + idx;

  # Resolve VNC port for ANY agent by simulating per-host grouping.
  # agentctl needs this for remote VNC connections — the port depends on
  # how many agents share the same host, not on the local host's agent set.
  globalAgentVncPort =
    name: agentCfg:
    if agentCfg.desktop.vncPort != null then
      agentCfg.desktop.vncPort
    else
      let
        sameHostAgentNames = sort lessThan (filter (n: cfg.${n}.host == agentCfg.host) (attrNames cfg));
        idx = findFirst (
          i: elemAt sameHostAgentNames i == name
        ) (throw "agent '${name}' not found in host group") (genList (x: x) (length sameHostAgentNames));
      in
      vncPortBase + 1 + idx;

  # Chrome services run on the agent's host (alongside labwc)
  chromeAgents = filterAttrs (_: agentCfg: agentCfg.chrome.enable) localAgents;
  hasChromeAgents = chromeAgents != { };

  # Sorted chrome agent names for deterministic debug port assignment
  sortedChromeAgentNames = sort lessThan (attrNames chromeAgents);

  # Resolve Chrome debug port for a chrome agent
  agentChromeDebugPort =
    name: agentCfg:
    if agentCfg.chrome.debugPort != null then
      agentCfg.chrome.debugPort
    else
      let
        idx = findFirst (
          i: elemAt sortedChromeAgentNames i == name
        ) (throw "chrome agent '${name}' not found") (genList (x: x) (length sortedChromeAgentNames));
      in
      chromeDebugPortBase + idx;

  # Resolve Chrome debug port for ANY agent by simulating per-host grouping.
  # Used in MCP configs which are built for all agents, not just local ones.
  globalAgentChromeDebugPort =
    name: agentCfg:
    if agentCfg.chrome.debugPort != null then
      agentCfg.chrome.debugPort
    else
      let
        sameHostAgentNames = sort lessThan (filter (n: cfg.${n}.host == agentCfg.host) (attrNames cfg));
        idx = findFirst (
          i: elemAt sameHostAgentNames i == name
        ) (throw "agent '${name}' not found in host group") (genList (x: x) (length sameHostAgentNames));
      in
      chromeDebugPortBase + idx;

  # Resolve Chrome MCP port for a chrome agent
  agentChromeMcpPort =
    name: agentCfg:
    if agentCfg.chrome.mcp.port != null then
      agentCfg.chrome.mcp.port
    else
      let
        idx = findFirst (
          i: elemAt sortedChromeAgentNames i == name
        ) (throw "chrome agent '${name}' not found") (genList (x: x) (length sortedChromeAgentNames));
      in
      chromeMcpPortBase + 1 + idx;

  # TODO: Re-enable per-agent Tailscale after fixing agenix.service dependency
  tailscaleAgents = { };
  hasTailscaleAgents = false;

  # fwmark base for per-agent tailscale routing (one per agent)
  tailscaleFwmarkBase = 51820;
  sortedTailscaleAgentNames = sort lessThan (attrNames tailscaleAgents);

  # Compute fwmark for a tailscale agent
  agentFwmark =
    name:
    let
      idx = findFirst (
        i: elemAt sortedTailscaleAgentNames i == name
      ) (throw "tailscale agent '${name}' not found") (genList (x: x) (length sortedTailscaleAgentNames));
    in
    tailscaleFwmarkBase + 1 + idx;

  # Generate labwc config for an agent's home directory setup script
  labwcConfigScript = username: agentCfg: ''
      # Create labwc config directory
      mkdir -p /home/${username}/.config/labwc
      # autostart: create virtual output for headless VNC
      cat > /home/${username}/.config/labwc/autostart <<'AUTOSTART'
      # Create virtual output for headless VNC
      ${pkgs.wlr-randr}/bin/wlr-randr --output HEADLESS-1 --custom-mode ${agentCfg.desktop.resolution}
    AUTOSTART
      chmod +x /home/${username}/.config/labwc/autostart
      # rc.xml: minimal labwc config
      cat > /home/${username}/.config/labwc/rc.xml <<'RCXML'
    <?xml version="1.0"?>
    <labwc_config>
      <theme><name>default</name></theme>
    </labwc_config>
    RCXML
      chown -R ${username}:agents /home/${username}/.config
  '';

in
{
  inherit
    osCfg
    cfg
    keysCfg
    topDomain
    ;
  inherit agentPublicKey allKeysForAgent useZfs;
  inherit
    agentUidBase
    vncPortBase
    chromeDebugPortBase
    chromeMcpPortBase
    ;
  inherit sortedAgentNames agentsWithUids agentSvcHelper;
  inherit localAgents;
  inherit desktopAgents hasDesktopAgents;
  inherit mailAgents hasMailAgents;
  inherit sshAgents hasSshAgents;
  inherit chromeAgents hasChromeAgents;
  inherit tailscaleAgents hasTailscaleAgents;
  inherit sortedDesktopAgentNames sortedChromeAgentNames sortedTailscaleAgentNames;
  inherit agentVncPort globalAgentVncPort;
  inherit agentChromeDebugPort globalAgentChromeDebugPort agentChromeMcpPort;
  inherit tailscaleFwmarkBase agentFwmark;
  inherit labwcConfigScript;
}
