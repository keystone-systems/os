# Keystone Journal Remote Nginx Proxy
#
# Auto-registers an nginx virtual host for systemd-journal-remote when the
# server module and journal-remote are both active. This provides HTTPS
# termination via the ACME wildcard certificate, with access restricted to
# the Tailscale network.
#
# See conventions/tool.journal-remote.md
# See docs/specs/REQ-020-journal-remote.md
{
  lib,
  config,
  ...
}:
let
  serverCfg = config.keystone.server;
  journalRemoteActive = config.services.journald.remote.enable;
  journalRemotePort = config.services.journald.remote.port;
in
{
  config = lib.mkIf (serverCfg.enable && journalRemoteActive) {
    keystone.server._enabledServices.journalRemote = {
      subdomain = "journal";
      port = journalRemotePort;
      access = "tailscale";
      maxBodySize = "0";
      websockets = false;
      registerDNS = true;
    };

    services.nginx.virtualHosts."journal.${config.keystone.domain}".locations."/".extraConfig = ''
      # systemd-journal-upload sends a streaming request body; avoid buffering
      # or downgrading the upstream request when proxying to journal-remote.
      proxy_http_version 1.1;
      proxy_request_buffering off;
      proxy_buffering off;
    '';
  };
}
