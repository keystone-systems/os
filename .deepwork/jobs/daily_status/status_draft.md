Daily Status - 2026-03-19

PRIORITIES

- execute-cross-account-cloud-resources-phase-1: Pull PR #486 (ncrmro/catalyst) and execute
  phase 1 of spec/012-cross-account-cloud-resources [BLOCKED - needs AWS IAM credentials and
  CloudFormation onboarding stack from Nicholas; Docker rootless overlayfs also restricts
  LocalStack fallback]

OPEN PRS

- ncrmro/plant-caravan #47: feat(dashboard): wire dashboard to real API data [DRAFT]
  https://github.com/ncrmro/plant-caravan/pull/47
- ncrmro/catalyst #490: fix(e2e): correct namespace assertion in deployment-environment spec
  https://github.com/ncrmro/catalyst/pull/490
- ncrmro/keystone #137: docs(specs): functional requirement specs for Keystone TUI [DRAFT]
  https://github.com/ncrmro/keystone/pull/137
- ncrmro/keystone #91: fix(agents): include system paths in agent systemd services PATH
  https://github.com/ncrmro/keystone/pull/91

RECENTLY COMPLETED

- review-projctl-session-management-stories: Reviewed projctl Terminal Session Management user
  stories in issue #102; all 5 stories approved, specs merged (#107), plan in #108
- review-keystone-tui-user-stories: Reviewed Keystone TUI user stories in issue #132; provided
  engineering feedback on feasibility and phasing
- review-nicholas-status-email: Read and responded to Nicholas's [status] email from 2026-03-14
- accept-github-invites: Accepted GitHub invites via Gmail
- respond-to-login-github-blocker: Replied to Nicholas re: login-to-github task blocked on credentials

BLOCKERS

- crossplane-smoke-test-needs-aws-credentials: Phase 1 smoke test needs management IAM user
  credentials in Bitwarden, CloudFormation onboarding stack in target AWS account, and
  workflow_dispatch rights on ncrmro/catalyst - needs Nicholas to set up
- catalyst-helm-vm-docker-socket-permission-denied: Docker socket not accessible to agent-drago
  user on catalyst helm VM; blocks local E2E test runs
- catalyst-helm-vm-cnpg-crds-not-installed: CloudNativePG CRDs not installed in k3s-vm; helm
  install of catalyst chart fails
- github-oauth-requires-human: Chrome signin to GitHub (kdrgo) needs chrome-devtools-mcp
  working first
- chrome-devtools-mcp-requires-nix-config: chrome-devtools-mcp needs nodejs in system packages
  and Chrome launched with --remote-debugging-port=9222; requires keystone NixOS changes
- vault-sync-hardcoded-paths: vault-sync.service has hardcoded paths for ncrmro's machine;
  fails every 5 min on agent VM
- incubator-requires-physical-action: Humidity/temp issues in incubator require physical check
  (humidity dome, watering zones 1/2, heat source review)
- crop-planting-requires-physical-action: Basil/cilantro/mint planting requires physical action

--
Drago (automated daily status)
