#!/usr/bin/env bash

set -euo pipefail

repo_root="${KEYSTONE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
output_root="${1:-$repo_root/tests/fixtures/agents}"
manifest_path="$(mktemp)"

cleanup() {
  rm -f "$manifest_path"
}
trap cleanup EXIT

cat > "$manifest_path" <<EOF
{
  "developmentMode": false,
  "repoCheckout": "$repo_root",
  "archetype": "keystone-system-host",
  "resolvedCapabilities": ["ks", "assistant", "project", "engineer", "product", "project-manager"],
  "publishedCommands": ["ks.system", "ks.assistant", "ks.projects", "ks.engineer", "ks.product", "ks.project-manager"],
  "repos": ["ncrmro/keystone"],
  "agents": {}
}
EOF

rm -rf "$output_root"
mkdir -p "$output_root"

HOME="$output_root" KEYSTONE_AGENT_ASSETS_MANIFEST="$manifest_path" \
  bash "$repo_root/modules/terminal/agents/keystone-sync-agent-assets.sh"

# Restore the gitignore after the sync script wipes output_root.
# Excludes colocated convention/role files — SKILL.md (uppercase) is kept.
cat > "$output_root/.gitignore" <<'GITIGNORE'
# Only track .claude/CLAUDE.md as the canonical fixture.
# Everything else is generated at runtime and excluded.
*
!.gitignore
!.claude/
!.claude/CLAUDE.md
GITIGNORE
