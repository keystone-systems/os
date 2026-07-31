#!/usr/bin/env bash
# Precompute script for the milestone_github_sync .deepreview rule.
# Iterates every docs/milestones/M*/ directory, parses each README.md's
# YAML frontmatter, and dumps the matching GitHub milestone + tracker
# issue + attached issue list. Output is injected as the reviewer's
# "Precomputed Context" so a single review pass can compare local vs
# remote across every milestone.
#
# CRITICAL: deepwork's runtime does NOT pass the matched-file list to the
# precompute command — the script must self-discover. Don't switch back
# to `git diff` detection; on a clean tree (post-merge or `/review --files`)
# it produces an empty block.
set -euo pipefail

REPO="ncrmro/keystone"

dirs=$(find docs/milestones -mindepth 1 -maxdepth 1 -type d -name 'M[0-9]*-*' 2>/dev/null \
       | sort)

if [ -z "$dirs" ]; then
  echo "No docs/milestones/M*/ directories found."
  exit 0
fi

for dir in $dirs; do
  readme="$dir/README.md"
  if [ ! -f "$readme" ]; then
    echo "=== $dir ==="
    echo "ERROR: README.md missing — cannot resolve trackerMilestone."
    continue
  fi

  # Frontmatter = lines between the first two `---` markers.
  fm=$(awk '/^---[[:space:]]*$/{c++; if (c==2) exit; next} c==1' "$readme")
  if [ -z "$fm" ]; then
    echo "=== $dir ==="
    echo "ERROR: README.md has no YAML frontmatter."
    continue
  fi

  trackerMilestone=$(printf '%s\n' "$fm" | yq '.trackerMilestone // "null"')
  trackerIssue=$(printf '%s\n' "$fm" | yq '.trackerIssue // "null"')
  status=$(printf '%s\n' "$fm" | yq '.status // "null"')
  slug=$(printf '%s\n' "$fm" | yq '.slug // "null"')

  echo "=== $dir ==="
  echo "Local frontmatter: slug=$slug trackerMilestone=$trackerMilestone trackerIssue=$trackerIssue status=$status"
  echo

  if [ "$trackerMilestone" = "null" ] || [ -z "$trackerMilestone" ]; then
    echo "ERROR: frontmatter has no trackerMilestone — cannot fetch GitHub state."
    continue
  fi

  echo "--- gh api repos/$REPO/milestones/$trackerMilestone ---"
  if ! gh api "repos/$REPO/milestones/$trackerMilestone" \
       --jq '{title, state, description, open_issues, closed_issues, due_on, html_url}' 2>&1; then
    echo "ERROR: failed to fetch GitHub milestone $trackerMilestone."
    continue
  fi
  echo

  if [ "$trackerIssue" != "null" ] && [ -n "$trackerIssue" ]; then
    echo "--- gh api repos/$REPO/issues/$trackerIssue ---"
    gh api "repos/$REPO/issues/$trackerIssue" \
       --jq '{number, state, title, milestone_number: (.milestone.number // null), body_first_2k: (.body[0:2000])}' 2>&1 || \
       echo "ERROR: failed to fetch tracker issue $trackerIssue."
    echo
  fi

  ms_title=$(gh api "repos/$REPO/milestones/$trackerMilestone" --jq '.title' 2>/dev/null || true)
  if [ -n "$ms_title" ]; then
    echo "--- gh issue list --milestone \"$ms_title\" --state all ---"
    gh issue list --repo "$REPO" --milestone "$ms_title" --state all --limit 60 \
       --json number,title,state \
       --jq 'sort_by(.state, -.number) | .[] |
             "[\(.state)] #\(.number) — \(.title)"' 2>&1 || \
       echo "ERROR: failed to list issues for milestone \"$ms_title\"."
    echo
  fi
done
