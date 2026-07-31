# Keystone Grafana Service Module
#
# Grafana is an observability platform for metrics visualization.
# Default subdomain: grafana
# Default port: 3002
# Default access: tailscale
#
# When alerts.defaultEnabled is true (default), provisions standard
# infrastructure alert rules (e.g., nix store low disk space).
#
{
  lib,
  config,
  ...
}:
let
  serverLib = import ../../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.grafana;
  keystoneDashboards = ./dashboards;
  provisionKeystoneDashboards = !(config.keystone.development or false);
  extraDashboardProviders = lib.imap0 (
    index: pathOrAttr:
    if lib.isAttrs pathOrAttr then
      pathOrAttr
    else
      {
        name = "Extra ${toString (index + 1)}";
        folder = builtins.baseNameOf (toString pathOrAttr);
        options.path = pathOrAttr;
      }
  ) cfg.extraDashboardPaths;
in
{
  options.keystone.server.services.grafana =
    serverLib.mkServiceOptions {
      description = "Grafana observability platform";
      subdomain = "grafana";
      port = 3002;
      access = "tailscale";
      websockets = true;
      registerDNS = true;
    }
    // {
      extraDashboardPaths = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.path lib.types.attrs);
        default = [ ];
        description = ''
          Additional dashboard directories to provision alongside the built-in
          keystone dashboards. Can be a list of paths or { name, folder, options.path }
          attrsets. This lets nixos-config manage non-keystone Grafana dashboards
          declaratively without mixing them into the keystone repo.
        '';
      };

      alerts = {
        defaultEnabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Provision standard infrastructure alert rules (nix store disk space, etc.)";
        };
      };
    };

  config = lib.mkMerge [
    # Nginx/DNS registration + Grafana service — when keystone grafana is enabled
    (lib.mkIf (serverCfg.enable && cfg.enable) {
      keystone.server._enabledServices.grafana = {
        inherit (cfg)
          subdomain
          port
          access
          maxBodySize
          websockets
          registerDNS
          ;
      };

      services.grafana = {
        enable = true;
        settings.server = {
          http_port = cfg.port;
          http_addr = "127.0.0.1";
          domain = "${cfg.subdomain}.${config.keystone.domain}";
          root_url = "https://${cfg.subdomain}.${config.keystone.domain}/";
        };
        provision.enable = true;
        provision.dashboards.settings.providers =
          (lib.optionals provisionKeystoneDashboards [
            {
              name = "Keystone";
              folder = "Keystone";
              options.path = keystoneDashboards;
            }
          ])
          ++ extraDashboardProviders;

        provision.datasources.settings.datasources =
          (lib.optional serverCfg.services.prometheus.enable {
            name = "Prometheus";
            type = "prometheus";
            uid = serverLib.datasourceUids.prometheus;
            url = "http://127.0.0.1:${toString serverCfg.services.prometheus.port}";
            isDefault = true;
          })
          ++ (lib.optional serverCfg.services.loki.enable {
            name = "Loki";
            type = "loki";
            uid = serverLib.datasourceUids.loki;
            url = "http://127.0.0.1:${toString serverCfg.services.loki.port}";
          });
      };
    })

    # Alert provisioning — fires when Grafana is running, regardless of nginx registration
    (lib.mkIf (serverCfg.enable && config.services.grafana.enable && cfg.alerts.defaultEnabled) {
      services.grafana.provision.alerting.rules.settings = {
        groups = [
          {
            orgId = 1;
            name = "disk-alerts";
            folder = "Infrastructure";
            interval = "1m";
            rules = [
              {
                uid = "nix-store-low-disk-space";
                title = "Nix Store Low Disk Space";
                condition = "C";
                for = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Nix store on {{ $labels.host }} has less than 15% free space";
                };
                data = [
                  {
                    refId = "A";
                    datasourceUid = serverLib.datasourceUids.prometheus;
                    relativeTimeRange = {
                      from = 600;
                      to = 0;
                    };
                    model = {
                      refId = "A";
                      expr = ''max by (host) ((node_filesystem_avail_bytes{mountpoint="/nix/store", host!=""} / node_filesystem_size_bytes{mountpoint="/nix/store", host!=""}) * 100)'';
                      intervalMs = 1000;
                      maxDataPoints = 43200;
                    };
                  }
                  {
                    refId = "C";
                    datasourceUid = "__expr__";
                    relativeTimeRange = {
                      from = 600;
                      to = 0;
                    };
                    model = {
                      refId = "C";
                      type = "threshold";
                      conditions = [
                        {
                          evaluator = {
                            params = [ 15 ];
                            type = "lt";
                          };
                          operator = {
                            type = "and";
                          };
                          query = {
                            params = [ "C" ];
                          };
                          reducer = {
                            params = [ ];
                            type = "last";
                          };
                          type = "query";
                        }
                      ];
                      expression = "A";
                    };
                  }
                ];
                noDataState = "NoData";
                execErrState = "Error";
              }
            ];
          }
        ];
      };
    })
  ];
}
