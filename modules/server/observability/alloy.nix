{ ... }:
{
  services.k3s.autoDeployCharts = {
    # Grafana Alloy Helm Chart: https://artifacthub.io/packages/helm/grafana/alloy
    alloy = {
      name = "alloy";
      repo = "https://grafana.github.io/helm-charts";
      version = "0.12.0";
      hash = "sha256-Ky9tzbEtEtJWy3dRzjSIWRBylIK8FwwOxB65V8WNtac=";
      targetNamespace = "observability";
      createNamespace = false;
      values = {
        alloy = {
          configMap = {
            content = ''
              // Basic Kubernetes logs collection
              discovery.kubernetes "pods" {
                role = "pod"
              }

              loki.source.kubernetes "pods" {
                targets    = discovery.kubernetes.pods.targets
                forward_to = [loki.write.default.receiver]
              }

              // Node logs collection
              local.file_match "node_logs" {
                path_targets = [{
                    // Monitor syslog to scrape node-logs
                    __path__  = "/var/log/syslog",
                    job       = "node/syslog",
                    node_name = sys.env("HOSTNAME"),
                    cluster   = "k3s-home",
                }]
              }

              loki.source.file "node_logs" {
                targets    = local.file_match.node_logs.targets
                forward_to = [loki.write.default.receiver]
              }

              // Kubernetes events collection
              loki.source.kubernetes_events "cluster_events" {
                job_name   = "integrations/kubernetes/eventhandler"
                log_format = "logfmt"
                forward_to = [
                  loki.process.cluster_events.receiver,
                ]
              }

              loki.process "cluster_events" {
                forward_to = [loki.write.default.receiver]

                stage.static_labels {
                  values = {
                    cluster = "k3s-home",
                  }
                }

                stage.labels {
                  values = {
                    kubernetes_cluster_events = "job",
                  }
                }
              }

              loki.write "default" {
                endpoint {
                  url = "http://loki-gateway.observability.svc.cluster.local/loki/api/v1/push"
                }
              }
            '';
          };
        };
      };
    };
  };
}
