# Keystone Alloy Module
#
# Grafana Alloy is a telemetry collector that ships logs to Loki and metrics
# to Prometheus. This module provides standard keystone telemetry shipping
# with pre-configured processing for agent logs (journal priority mapping,
# task/step extraction, and structured metadata).
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os.alloy;
in
{
  options.keystone.os.alloy = {
    enable = lib.mkEnableOption "Grafana Alloy telemetry collector";

    lokiEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://loki.\${config.keystone.domain}/loki/api/v1/push";
      description = "Loki endpoint URL for log shipping. Defaults to auto-derived keystone URL.";
    };

    prometheusEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://prometheus.\${config.keystone.domain}/api/v1/write";
      description = "Prometheus remote_write endpoint URL. Defaults to auto-derived keystone URL.";
    };

    enableMetrics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable metrics collection and shipping to Prometheus";
    };

    enableZfsExporter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ZFS exporter metrics collection";
    };

    hostLabel = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Host label to attach to logs and metrics";
    };

    extraLabels = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional static labels to attach to logs and metrics";
      example = {
        environment = "production";
      };
    };
  };

  config = lib.mkIf (config.keystone.os.enable && cfg.enable) {
    services.alloy = {
      enable = true;
    };

    # Reduce shutdown timeout from default 1m30s to 10s
    systemd.services.alloy.serviceConfig.TimeoutStopSec = 10;

    # Enable ZFS exporter when requested
    services.prometheus.exporters.zfs = lib.mkIf cfg.enableZfsExporter {
      enable = true;
      port = 9134;
    };

    # Create Alloy configuration
    environment.etc."alloy/config.alloy".text =
      let
        allLabels = {
          host = cfg.hostLabel;
        }
        // cfg.extraLabels;
        labelsList = lib.mapAttrsToList (k: v: "            ${k} = \"${v}\"") allLabels;
        labelsStr = lib.concatStringsSep ",\n" labelsList + ",";
        staticLabels = ''
                  stage.static_labels {
                    values = {
          ${labelsStr}
                    }
                  }'';
      in
      ''
        // System journal logs collection
        loki.source.journal "system_logs" {
          format_as_json = true
          forward_to     = [loki.process.system.receiver]
          labels         = {
            job = "systemd-journal",
            host = "${cfg.hostLabel}",
          }
        }

        // Process system logs
        loki.process "system" {
          forward_to = [loki.write.default.receiver]

          ${staticLabels}

          // Extract log level and agent-relevant fields from journal
          stage.json {
            expressions = {
              priority = "PRIORITY",
              unit = "_SYSTEMD_UNIT",
              user_unit = "_SYSTEMD_USER_UNIT",
              syslog_identifier = "SYSLOG_IDENTIFIER",
              message = "MESSAGE",
            }
          }

          // Map journal priority to log level
          stage.template {
            source = "priority"
            template = "{{ if eq . \"0\" }}emergency{{ else if eq . \"1\" }}alert{{ else if eq . \"2\" }}critical{{ else if eq . \"3\" }}error{{ else if eq . \"4\" }}warning{{ else if eq . \"5\" }}notice{{ else if eq . \"6\" }}info{{ else }}debug{{ end }}"
          }

          // Extract agent name from syslog identifier (agent-drago-task-loop -> drago)
          stage.regex {
            source = "syslog_identifier"
            expression = "^agent-(?P<agent_name>[^-]+)-(?:task-loop|scheduler|notes-sync)$"
          }

          // Extract step and task from structured log tags
          stage.regex {
            source = "message"
            expression = "\\[step=(?P<agent_step>[a-z]+)\\](?:\\[task=(?P<agent_task>[^\\]]+)\\])?"
          }

          stage.labels {
            values = {
              level = "priority",
              unit = "unit",
              user_unit = "user_unit",
              agent = "agent_name",
              agent_step = "agent_step",
            }
          }

          stage.structured_metadata {
            values = {
              task = "agent_task",
            }
          }

          // Use MESSAGE as the log line content
          stage.output {
            source = "message"
          }
        }

        // Write to remote Loki
        loki.write "default" {
          endpoint {
            url = "${cfg.lokiEndpoint}"
          }

          external_labels = {
            cluster = "keystone",
          }
        }
      ''
      + lib.optionalString cfg.enableMetrics ''

        // ============================================
        // Metrics Collection (Prometheus remote_write)
        // ============================================

        // Scrape local node_exporter
        prometheus.scrape "node" {
          targets = [{ __address__ = "127.0.0.1:9100" }]
          scrape_interval = "15s"
          job_name = "node"
          forward_to = [prometheus.relabel.instance.receiver]
        }
      ''
      + lib.optionalString (cfg.enableMetrics && cfg.enableZfsExporter) ''

        // Scrape local zfs_exporter
        prometheus.scrape "zfs" {
          targets = [{ __address__ = "127.0.0.1:9134" }]
          scrape_interval = "15s"
          job_name = "zfs"
          forward_to = [prometheus.relabel.instance.receiver]
        }
      ''
      + lib.optionalString cfg.enableMetrics ''

        // Relabel instance to hostname instead of IP:port
        prometheus.relabel "instance" {
          rule {
            target_label = "instance"
            replacement  = "${cfg.hostLabel}"
          }
          forward_to = [prometheus.remote_write.central.receiver]
        }

        // Ship metrics to central Prometheus
        prometheus.remote_write "central" {
          endpoint {
            url = "${cfg.prometheusEndpoint}"
          }
          external_labels = {
            host = "${cfg.hostLabel}",
            cluster = "keystone",
          }
        }
      '';
  };
}
