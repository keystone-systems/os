---
title: AWS Integration & Hybrid Cloud
description: Connecting Keystone clusters to AWS using OIDC and AWS Controllers
---

# AWS Integration & Hybrid Cloud

Keystone clusters are designed to interoperate seamlessly with public cloud providers like AWS. This allows you to leverage cloud-specific resources (like S3 buckets, RDS databases, or Auto Scaling Groups) directly from your Kubernetes manifests.

## Authentication: OIDC & AWS STS

We eschew long-lived access keys in favor of secure, temporary credentials using OpenID Connect (OIDC) and AWS Security Token Service (STS). This is often referred to as "IAM Roles for Service Accounts" (IRSA).

### How it Works

1.  **OIDC Provider:** Your Keystone Cluster exposes an OIDC discovery endpoint (secured and signed by the cluster's service account issuer).
2.  **AWS Trust Relationship:** You create an IAM Role in AWS and configure a Trust Policy that trusts the cluster's OIDC provider.
3.  **Pod Identity:** When a pod needs to access AWS, it projects a specialized Service Account token.
4.  **AssumeRole:** The AWS SDKs within the pod automatically exchange this token for temporary AWS credentials via the `AssumeRoleWithWebIdentity` API call.

### Configuration Example

**AWS IAM Trust Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.keystone.systems/CLUSTER_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.keystone.systems/CLUSTER_ID:sub": "system:serviceaccount:default:my-app"
        }
      }
    }
  ]
}
```

## AWS Controllers for Kubernetes (ACK)

To provision and manage AWS resources declaratively, we support the AWS Controllers for Kubernetes (ACK). This allows you to define AWS resources as Custom Resource Definitions (CRDs) in your cluster.

### Provisioning Worker Nodes (AWS Node Groups)

You can scale your cluster by defining AWS Auto Scaling Groups or EKS Managed Node Groups that join your Keystone control plane.

```yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: LaunchTemplate
metadata:
  name: worker-template
spec:
  imageId: ami-0c55b159cbfafe1f0 # Keystone-optimized node AMI
  instanceType: m6i.large
  userData: |
    #!/bin/bash
    /usr/local/bin/join-cluster --token <token> --endpoint https://api.cluster.keystone.systems
---
apiVersion: autoscaling.services.k8s.aws/v1alpha1
kind: AutoScalingGroup
metadata:
  name: cloud-workers
spec:
  minSize: 1
  maxSize: 10
  launchTemplate:
    launchTemplateName: worker-template
    version: "$Latest"
  availabilityZones:
    - us-east-1a
    - us-east-1b
```

## Use Cases

### Burst Scaling

Keep your steady-state workloads on cost-effective bare metal. When demand spikes, the cluster autoscaler detects pending pods and automatically provisions ephemeral AWS nodes to handle the load.

### Managed Services

Connect your on-prem applications to AWS RDS or S3 for robust storage and database solutions without migrating the compute layer.
