# Centralized journal collection via systemd-journal-remote/upload.
#
# Implements REQ-020 (Centralized Journal Collection)
# See docs/specs/REQ-020-journal-remote.md
#
# Configuration is auto-derived from keystone.hosts: the host with
# `journalRemote = true` becomes the server, all other hosts auto-forward
# via systemd-journal-upload. No per-host config needed in nixos-config.
#
# TRANSPORT: When keystone.domain is set, uploads use HTTPS via the nginx
# reverse proxy (journal.<domain>). The server-side nginx vhost is registered
# by modules/server/services/journal-remote.nix. When no domain is set,
# the module falls back to direct HTTP over Tailscale.
{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.os.journalRemote;
  osCfg = config.keystone.os;
  hostname = config.networking.hostName;
  domain = config.keystone.domain;

  # Auto-derive serverHost from keystone.hosts registry.
  # Find the host entry with journalRemote = true.
  journalRemoteHosts = filterAttrs (_: h: h.journalRemote or false) config.keystone.hosts;
  journalRemoteHostNames = attrNames journalRemoteHosts;
  derivedServerHost =
    if journalRemoteHostNames != [ ] then
      (builtins.getAttr (builtins.head journalRemoteHostNames) journalRemoteHosts).hostname
    else
      null;

  # Effective serverHost: explicit override > auto-derived from hosts registry
  effectiveServerHost = if cfg.serverHost != null then cfg.serverHost else derivedServerHost;

  # Derive the server URL from the serverHost hostname.
  # When domain is set, use the nginx HTTPS proxy. Otherwise use direct HTTP.
  derivedServerUrl =
    if effectiveServerHost != null then
      if domain != null then
        "https://journal.${domain}:443"
      else
        "http://${effectiveServerHost}:${toString cfg.server.port}"
    else
      null;

  # Effective server URL: explicit override > auto-derived from serverHost
  effectiveServerUrl =
    if cfg.upload.serverUrl != null then cfg.upload.serverUrl else derivedServerUrl;

  # Is this host the journal server?
  isServer = effectiveServerHost == hostname;

  # Should this host upload? Only if: not the server, upload enabled, and a URL exists.
  shouldUpload = !isServer && cfg.upload.enable && effectiveServerUrl != null;

  # When a domain is configured, nginx terminates HTTPS and proxies locally.
  useNginxProxy = domain != null;
in
{
  options.keystone.os.journalRemote = {
    serverHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Hostname of the journal-remote server. Auto-derived from keystone.hosts
        (the host with journalRemote = true). Override only for non-standard setups.
        When null and no host has journalRemote = true, journal forwarding is disabled.
      '';
      example = "ocean";
    };

    server = {
      enable = mkEnableOption "centralized journal collection (systemd-journal-remote receiver)";

      port = mkOption {
        type = types.port;
        default = 19532;
        description = "Listen port for systemd-journal-remote.";
      };
    };

    upload = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Forward this host's journal to the fleet's journal-remote server.
          Set to false to opt out (e.g., for ephemeral VMs or test boxes).
          Has no effect if no serverHost is configured.
        '';
      };

      serverUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          URL of the journal-remote server. Auto-derived from serverHost
          when null. Override for non-standard setups.
        '';
      };
    };
  };

  config = mkIf osCfg.enable (mkMerge [
    # --- Auto-derive server.enable from hosts registry ---
    (mkIf isServer {
      keystone.os.journalRemote.server.enable = mkDefault true;
    })

    # --- Assertions and warnings ---
    {
      assertions = [
        {
          # Only one host in keystone.hosts should have journalRemote = true
          assertion = length journalRemoteHostNames <= 1;
          message = ''
            keystone.hosts: multiple hosts have journalRemote = true: ${concatStringsSep ", " journalRemoteHostNames}.
            Exactly one host should be the journal-remote server.
          '';
        }
      ];

      warnings = optional (cfg.server.enable && effectiveServerHost == null) ''
        keystone.os.journalRemote: server.enable is true but no serverHost is configured
        and no host in keystone.hosts has journalRemote = true. Clients won't auto-discover
        this server. Set journalRemote = true on this host's entry in keystone.hosts.
      '';
    }

    # --- Server: receive journals from the fleet ---
    (mkIf isServer {
      services.journald.remote = {
        enable = true;
        listen = "http";
        port = cfg.server.port;
      };
    })

    # When nginx is proxying, bind journal-remote to localhost only.
    (mkIf (isServer && useNginxProxy) {
      systemd.sockets.systemd-journal-remote.listenStreams = mkForce [
        "127.0.0.1:${toString cfg.server.port}"
      ];
    })

    # Without nginx, expose the backend directly on Tailscale only.
    (mkIf (isServer && !useNginxProxy) {
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.server.port ];
    })

    # --- Client: forward journals to the server ---
    # REQ-020.7: auto-forward when serverHost is set
    # REQ-020.9: skip if this host IS the server (no self-loop)
    # REQ-020.13: no-op when serverHost is null
    (mkIf shouldUpload {
      services.journald.upload = {
        enable = true;
        settings.Upload = {
          URL = effectiveServerUrl;
        }
        // optionalAttrs useNginxProxy {
          # nginx terminates TLS, so the client must not require a separate mTLS keypair.
          ServerCertificateFile = "-";
          ServerKeyFile = "-";
          # Use the system CA bundle to verify nginx's public certificate chain.
          TrustedCertificateFile = "/etc/ssl/certs/ca-bundle.crt";
        };
      };

      systemd.services.systemd-journal-upload = {
        serviceConfig = {
          # systemd-journal-upload exits 1 for malformed or oversized local
          # journal entries. Treat that as retryable so observability cannot
          # make switch-to-configuration fail an otherwise valid system update.
          SuccessExitStatus = [ 1 ];
          RestartSec = mkForce "5min";
        };

        # Don't let switch-to-configuration restart this unit during a system
        # switch. With SuccessExitStatus=1 and RestartSec=5min, the unit sits
        # in `activating` between auto-restart cycles whenever the local
        # journal hits a malformed entry; switch-to-configuration's
        # post-restart health check sees that transient state and exits 4
        # ("warning: units failed"), which `ks update --approve` then treats
        # as a hard failure and refuses to advance flake.lock. The currently
        # running daemon keeps uploading regardless of switches; config
        # changes here (URL, certs, drop-ins) take effect on the next reboot
        # or manual `systemctl restart systemd-journal-upload`. That trade
        # is acceptable for an observability uploader — losing a flake.lock
        # advance every time the daemon is mid-cycle is not.
        #
        # mkDefault so a host that needs different behavior (e.g., wants
        # immediate config rollout via stop/start during switch) can
        # override without an option-redefinition conflict.
        restartIfChanged = mkDefault false;
      };
    })
  ]);
}
