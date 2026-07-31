# Keystone OS Observability Module
#
# Configures host-level observability tools:
# - Prometheus Node Exporter with standard collectors
# - Standard directory for textfile metrics
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os.observability;
in
{
  options.keystone.os.observability = {
    enable = lib.mkEnableOption "host-level observability (node exporter)";

    nodeExporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the Prometheus node exporter.";
      };

      textfileDirectory = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/prometheus-node-exporter";
        description = "Directory for Prometheus textfile collector metrics.";
      };
    };
  };

  config = lib.mkIf (config.keystone.os.enable && cfg.enable) {
    # The textfile directory tmpfiles rule lives in agents/notes.nix (the
    # producer). This module only configures the node exporter (the consumer).
    services.prometheus.exporters.node = lib.mkIf cfg.nodeExporter.enable {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
        "textfile"
      ];
      extraFlags = [
        "--collector.textfile.directory=${cfg.nodeExporter.textfileDirectory}"
      ];
    };
  };
}
