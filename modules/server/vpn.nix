# Keystone VPN Server Module
#
# Provides VPN server with Headscale operator running on Kubernetes.
# This is a Kubernetes-based solution for managing Tailscale/Headscale infrastructure.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
{
  options.keystone.server.vpn = {
    namespace = mkOption {
      type = types.str;
      default = "headscale-system";
      description = "Kubernetes namespace for Headscale operator";
    };

    headscale = {
      serverUrl = mkOption {
        type = types.str;
        example = "https://headscale.example.com";
        description = "Public URL for the Headscale server";
      };

      baseDomain = mkOption {
        type = types.str;
        example = "example.com";
        description = "Base domain for MagicDNS";
      };

      derpMap = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://controlplane.tailscale.com/derpmap/default";
        description = "Custom DERP map URL (optional)";
      };
    };

    kubernetes = {
      enableRBAC = mkOption {
        type = types.bool;
        default = true;
        description = "Enable RBAC for Headscale operator";
      };

      storageClass = mkOption {
        type = types.str;
        default = "default";
        description = "Storage class for persistent volumes";
      };

      resources = {
        requests = {
          cpu = mkOption {
            type = types.str;
            default = "100m";
            description = "CPU request for Headscale pods";
          };
          memory = mkOption {
            type = types.str;
            default = "128Mi";
            description = "Memory request for Headscale pods";
          };
        };
        limits = {
          cpu = mkOption {
            type = types.str;
            default = "500m";
            description = "CPU limit for Headscale pods";
          };
          memory = mkOption {
            type = types.str;
            default = "512Mi";
            description = "Memory limit for Headscale pods";
          };
        };
      };
    };
  };

  config = mkIf config.keystone.server.vpn.enable {
    # Enable Kubernetes
    services.kubernetes = {
      roles = [
        "master"
        "node"
      ];
      masterAddress = "127.0.0.1";
      easyCerts = true;

      apiserver = {
        enable = true;
        advertiseAddress = "127.0.0.1";
        allowPrivileged = true;
      };

      controllerManager.enable = true;
      scheduler.enable = true;

      kubelet = {
        enable = true;
        registerNode = true;
      };

      proxy.enable = true;
    };

    # Install kubectl and helm
    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      curl
    ];

    # Create systemd service to deploy Headscale operator
    systemd.services.headscale-operator-deploy = {
      description = "Deploy Headscale Kubernetes Operator";
      wantedBy = [ "multi-user.target" ];
      after = [ "kubernetes-cluster.target" ];
      wants = [ "kubernetes-cluster.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script =
        let
          cfg = config.keystone.server.vpn;
          headscaleOperatorManifest = pkgs.writeText "headscale-operator.yaml" ''
            apiVersion: v1
            kind: Namespace
            metadata:
              name: ${cfg.namespace}
            ---
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: headscale-operator
              namespace: ${cfg.namespace}
              labels:
                app: headscale-operator
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: headscale-operator
              template:
                metadata:
                  labels:
                    app: headscale-operator
                spec:
                  serviceAccountName: headscale-operator
                  containers:
                  - name: operator
                    image: ghcr.io/orange-cloudavenue/headscale-operator:latest
                    imagePullPolicy: Always
                    env:
                    - name: WATCH_NAMESPACE
                      value: ""
                    - name: POD_NAME
                      valueFrom:
                        fieldRef:
                          fieldPath: metadata.name
                    - name: OPERATOR_NAME
                      value: "headscale-operator"
                    resources:
                      requests:
                        cpu: ${cfg.kubernetes.resources.requests.cpu}
                        memory: ${cfg.kubernetes.resources.requests.memory}
                      limits:
                        cpu: ${cfg.kubernetes.resources.limits.cpu}
                        memory: ${cfg.kubernetes.resources.limits.memory}
            ---
            apiVersion: v1
            kind: ServiceAccount
            metadata:
              name: headscale-operator
              namespace: ${cfg.namespace}
            ${optionalString cfg.kubernetes.enableRBAC ''
              ---
              apiVersion: rbac.authorization.k8s.io/v1
              kind: ClusterRole
              metadata:
                name: headscale-operator
              rules:
              - apiGroups: [""]
                resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "events", "configmaps", "secrets"]
                verbs: ["*"]
              - apiGroups: ["apps"]
                resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]
                verbs: ["*"]
              - apiGroups: ["headscale.net"]
                resources: ["*"]
                verbs: ["*"]
              ---
              apiVersion: rbac.authorization.k8s.io/v1
              kind: ClusterRoleBinding
              metadata:
                name: headscale-operator
              roleRef:
                apiGroup: rbac.authorization.k8s.io
                kind: ClusterRole
                name: headscale-operator
              subjects:
              - kind: ServiceAccount
                name: headscale-operator
                namespace: ${cfg.namespace}
            ''}
            ---
            apiVersion: headscale.net/v1alpha1
            kind: Headscale
            metadata:
              name: headscale
              namespace: ${cfg.namespace}
            spec:
              serverURL: ${cfg.headscale.serverUrl}
              baseDomain: ${cfg.headscale.baseDomain}
              ${optionalString (cfg.headscale.derpMap != null) ''
                derpMap: ${cfg.headscale.derpMap}
              ''}
              persistence:
                enabled: true
                storageClass: ${cfg.kubernetes.storageClass}
                size: 1Gi
              resources:
                requests:
                  cpu: ${cfg.kubernetes.resources.requests.cpu}
                  memory: ${cfg.kubernetes.resources.requests.memory}
                limits:
                  cpu: ${cfg.kubernetes.resources.limits.cpu}
                  memory: ${cfg.kubernetes.resources.limits.memory}
          '';
        in
        ''
          set -euo pipefail

          # Wait for Kubernetes API to be ready
          echo "Waiting for Kubernetes API server..."
          while ! ${pkgs.kubectl}/bin/kubectl cluster-info &>/dev/null; do
            sleep 5
          done

          echo "Kubernetes API server is ready"

          # Apply Headscale operator manifests
          echo "Deploying Headscale operator..."
          ${pkgs.kubectl}/bin/kubectl apply -f ${headscaleOperatorManifest}

          # Wait for operator deployment to be ready
          echo "Waiting for Headscale operator to be ready..."
          ${pkgs.kubectl}/bin/kubectl wait --for=condition=available --timeout=300s deployment/headscale-operator -n ${cfg.namespace}

          echo "Headscale operator deployed successfully"
        '';
    };

    # Open firewall ports for Headscale
    networking.firewall = {
      allowedTCPPorts = [
        8080 # Headscale HTTP
        443 # HTTPS
        3478 # DERP STUN
      ];
      allowedUDPPorts = [
        3478 # DERP STUN
        41641 # Default Tailscale UDP port
      ];
    };

    # Enable IP forwarding for VPN traffic
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
