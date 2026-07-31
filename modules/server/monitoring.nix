# Keystone Monitoring Module
#
# Provides monitoring stack using NixOS services:
# - Prometheus for metrics collection
# - Grafana for visualization
# - Node exporter for system metrics
# - Optional: Loki for log aggregation
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.server.monitoring;
in
{
  options.keystone.server.monitoring = {
    prometheus = {
      port = mkOption {
        type = types.port;
        default = 9090;
        description = "Port for Prometheus web interface";
      };

      retention = mkOption {
        type = types.str;
        default = "90d";
        description = "How long to retain metrics";
      };

      scrapeInterval = mkOption {
        type = types.str;
        default = "15s";
        description = "How often to scrape metrics";
      };
    };

    grafana = {
      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Port for Grafana web interface";
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "grafana.example.com";
        description = "Domain for Grafana (for reverse proxy setup)";
      };
    };

    nodeExporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable node exporter for system metrics";
      };

      port = mkOption {
        type = types.port;
        default = 9100;
        description = "Port for node exporter";
      };
    };

    loki = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Loki for log aggregation";
      };

      port = mkOption {
        type = types.port;
        default = 3100;
        description = "Port for Loki";
      };
    };
  };

  config = mkIf cfg.enable {
    # Prometheus configuration
    services.prometheus = {
      enable = true;
      port = cfg.prometheus.port;
      retentionTime = cfg.prometheus.retention;

      globalConfig = {
        scrape_interval = cfg.prometheus.scrapeInterval;
      };

      scrapeConfigs = [
        # Scrape Prometheus itself
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "localhost:${toString cfg.prometheus.port}" ];
            }
          ];
        }
        # Scrape node exporter if enabled
        (mkIf cfg.nodeExporter.enable {
          job_name = "node";
          static_configs = [
            {
              targets = [ "localhost:${toString cfg.nodeExporter.port}" ];
            }
          ];
        })
      ];
    };

    # Grafana configuration
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.grafana.port;
          domain = mkIf (cfg.grafana.domain != null) cfg.grafana.domain;
        };
      };

      # Provision Prometheus as a datasource
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${toString cfg.prometheus.port}";
            isDefault = true;
          }
        ]
        ++ (optional cfg.loki.enable {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://localhost:${toString cfg.loki.port}";
        });
      };
    };

    # Node exporter configuration
    services.prometheus.exporters.node = mkIf cfg.nodeExporter.enable {
      enable = true;
      port = cfg.nodeExporter.port;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };

    # Loki configuration (optional)
    services.loki = mkIf cfg.loki.enable {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.loki.port;
        auth_enabled = false;

        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
          };
          chunk_idle_period = "1h";
          max_chunk_age = "1h";
          chunk_target_size = 999999;
          chunk_retain_period = "30s";
        };

        schema_config = {
          configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-index";
            cache_location = "/var/lib/loki/tsdb-cache";
            cache_ttl = "24h";
          };
          filesystem.directory = "/var/lib/loki/chunks";
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        table_manager = {
          retention_deletes_enabled = false;
          retention_period = "0s";
        };

        compactor = {
          working_directory = "/var/lib/loki";
          compactor_ring.kvstore.store = "inmemory";
        };
      };
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = [
      cfg.prometheus.port
      cfg.grafana.port
    ]
    ++ (optional cfg.nodeExporter.enable cfg.nodeExporter.port)
    ++ (optional cfg.loki.enable cfg.loki.port);

    # Add helpful packages
    environment.systemPackages = with pkgs; [
      prometheus
      grafana
    ];
  };
}
