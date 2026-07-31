{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.tailscale;

  # Find host in registry by matching networking.hostName
  # We search all hosts because the flake configuration name (the key)
  # might differ from the actual networking.hostName.
  hostList = attrValues config.keystone.hosts;

  # Filter out the default 'nixos' hostname which is present during early evaluation
  # of some configurations before they've set their actual hostname.
  currentHostname = config.networking.hostName;
  isDefaultHostname = currentHostname == "nixos";

  matchedHosts = filter (h: h.hostname == currentHostname) hostList;
  currentHost = if !isDefaultHostname && matchedHosts != [ ] then head matchedHosts else null;
in
{
  options.keystone.os.tailscale = {
    enable = mkOption {
      type = types.bool;
      default = config.keystone.os.enable;
      description = "Enable Tailscale integration for this host.";
    };

    tags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional tags to advertise for this Tailscale node";
    };

    loginServer = mkOption {
      type = types.str;
      default = "https://mercury.ncrmro.com";
      description = "Headscale login server URL";
    };

    useRoutingFeatures = mkOption {
      type = types.str;
      default = "client";
      description = "Routing features to enable";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !isDefaultHostname -> (currentHost != null && currentHost.role != null);
        message = "Tailscale is enabled but host '${currentHostname}' is missing from keystone.hosts registry (no host found with hostname='${currentHostname}') or has no 'role' defined.";
      }
    ];

    services.tailscale = {
      enable = true;
      useRoutingFeatures = cfg.useRoutingFeatures;

      extraUpFlags =
        let
          # Base tags derived from the registry role
          roleTags =
            if currentHost == null then
              [ ]
            else if currentHost.role == "server" then
              [ "tag:server" ]
            else if currentHost.role == "agent" then
              [ "tag:agent" ]
            else
              [ ]; # 'client' is untagged to preserve user identity

          # Merge base role tags with any manually specified tags
          allTags = unique (roleTags ++ cfg.tags);
        in
        [
          "--login-server=${cfg.loginServer}"
        ]
        ++ optionals (allTags != [ ]) [
          "--advertise-tags=${concatStringsSep "," allTags}"
        ];
    };

    # Install the tailscale package
    environment.systemPackages = with pkgs; [
      tailscale
    ];

    # Open firewall for Tailscale
    networking.firewall = {
      checkReversePath = "loose";
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };
  };
}
