# Research: AWS OIDC Integration

**Relates to**: REQ-006 (Clusters, FR-004)

## Decision

Primer Server acts as OIDC Identity Provider. AWS trusts Primer-issued JWTs via IAM OIDC provider. Uses IRSA pattern (not EKS Pod Identity) for multi-cloud compatibility.

## How It Works

1. Primer exposes OIDC discovery at `/.well-known/openid-configuration` + JWKS at `/keys`
2. AWS IAM OIDC provider points to Primer's endpoint
3. Kubernetes projected service account tokens (audience-scoped, auto-rotated) used for `AssumeRoleWithWebIdentity`
4. Short-lived credentials (1h default), no static API keys

## Key Decisions

| Decision                      | Rationale                                             |
| ----------------------------- | ----------------------------------------------------- |
| IRSA over Pod Identity        | Works with any K8s cluster, not EKS-only              |
| kubebuilder for operator      | Official K8s SIG, strong Go typing, clean scaffolding |
| Launch Templates + cloud-init | Proven pattern, supports NixOS bootstrap              |

## Security

- Tokens expire after 1h, audience-scoped
- OIDC endpoint accessible only via Headscale network
- IMDS disabled on provisioned nodes
- IAM permissions scoped via tag-based conditions (`keystone-cluster` tag)

## Gotchas

- AWS needs HTTPS with valid cert for OIDC discovery — expose via Cloudflare tunnel if behind NAT
- Existing tokens work until expiry if Primer goes offline; new tokens require Primer
- AWS SDK reads fresh projected token on each request (automatic refresh)
