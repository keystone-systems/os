{ ... }:
{
  services.k3s.autoDeployCharts = {
    loki = {
      name = "loki";
      repo = "https://grafana.github.io/helm-charts";
      version = "6.39.0";
      hash = "sha256-d91DPheDPX1HNydWhjgJjgPsyNlMBfbU+wLIJMLLvNE=";
      targetNamespace = "observability";
      createNamespace = false;
      values = {
        loki = {
          auth_enabled = false;
          # https://grafana.com/docs/loki/latest/configuration/#common_config
          commonConfig = {
            replication_factor = 1;
          };
          schemaConfig = {
            configs = [
              {
                from = "2024-04-01";
                store = "tsdb";
                object_store = "s3";
                schema = "v13";
                index = {
                  prefix = "loki_index_";
                  period = "24h";
                };
              }
            ];
          };
          ingester = {
            chunk_encoding = "snappy";
          };
          querier = {
            max_concurrent = 4;
          };
          pattern_ingester = {
            enabled = true;
          };
          limits_config = {
            allow_structured_metadata = true;
            volume_enabled = true;
          };
        };

        deploymentMode = "SimpleScalable";

        backend = {
          replicas = 1;
          persistence = {
            storageClass = "ocean-nvme";
          };
        };
        read = {
          replicas = 1;
        };
        write = {
          replicas = 1;
          persistence = {
            storageClass = "ocean-nvme";
          };
        };

        minio = {
          enabled = true;
          persistence = {
            storageClass = "ocean-nvme";
          };
        };

        gateway = {
          service = {
            type = "ClusterIP";
          };
          ingress = {
            enabled = true;
            ingressClassName = "nginx";
            hosts = [
              {
                host = "loki.ncrmro.com";
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                  }
                ];
              }
            ];
            tls = [
              {
                # Using default ingress-nginx wildcard cert (*.ncrmro.com)
                hosts = [ "loki.ncrmro.com" ];
              }
            ];
          };
        };
      };
    };
  };
}
