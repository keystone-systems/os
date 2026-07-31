#!/usr/bin/env bash
# Sync generated Keystone agent assets from the current profile manifest.
# See conventions/code.shell-scripts.md and
# conventions/tool.cli-coding-agents.md § "Consumer Flake Agent Assets".

set -euo pipefail

manifest_path="${KEYSTONE_AGENT_ASSETS_MANIFEST:-$HOME/.config/keystone/agent-assets.json}"

usage() {
  cat <<'EOF'
Usage: keystone-sync-agent-assets

Refresh generated Keystone agent assets for the current user from the current
profile manifest. Most content is written into the consumer flake at
<consumer-flake>/agents/. Two files in the home dir are also (re)written
unconditionally on every run:

  ~/.keystone/AGENTS.md          legacy host-rendered conventions copy
  ~/.config/opencode/AGENTS.md   same content; OpenCode reads it natively

The locked-mode home-manager activation in
modules/terminal/conventions.nix also writes these via `home.file.text` for
hosts without the dev-mode script entry point. The two paths produce the
same content, so either order of activation + manual sync converges.

The committed canonical surface:

  <consumer-flake>/agents/
    _shared/AGENTS.md             host-rendered instruction file
    _shared/skills.yaml           optional user-authored skill overrides
    skills/<name>/SKILL.md        per-skill body, spec-compliant naming
    skills/<name>/<convention>.md colocated conventions/roles

Home-manager activation symlinks ~/.agents/skills/ → <flake>/agents/skills/
(read by Codex, Gemini, Copilot, Cursor, Kiro, OpenCode, Augment per the
.agents/skills/ open standard) and ~/.claude/skills/ → <flake>/agents/skills/
(Claude-only shadow at the same target). Per-tool instruction filenames
(CLAUDE.md, GEMINI.md, codex AGENTS.md) symlink to _shared/AGENTS.md via
the activation. No per-tool rendering, no hyphenated-codex fan-out — the
spec-compliant naming makes one canonical tree sufficient for every agent.

The merged skill map is built from conventions/archetypes.yaml.skills
(keystone defaults) plus an optional <consumer-flake>/agents/_shared/skills.yaml
(user overrides, wholesale-replace on key conflict). See
docs/research/agent-skills.md for the standard.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$manifest_path" ]]; then
  echo "Error: agent asset manifest not found at $manifest_path" >&2
  exit 1
fi

# Resolve the consumer-flake agents root. This is where skill content lands.
# Precedence (matches the Rust precedence in packages/ks/src/app.rs:current_system_flake_path):
#   1. KEYSTONE_CONSUMER_FLAKE env var (test override)
#   2. /run/current-system/keystone-system-flake (runtime pointer file)
#   3. Manifest's eval-time consumerFlakeAgents value (Nix-eval fallback)
# The runtime pointer is a *regular file* written by modules/shared/system-flake.nix
# containing the path as text — not a symlink — so read with `read`, not
# `readlink`. The activation in generated-agent-assets.nix uses the same pattern.
consumer_flake_root="${KEYSTONE_CONSUMER_FLAKE:-}"
if [[ -z "$consumer_flake_root" && -f /run/current-system/keystone-system-flake ]]; then
  IFS= read -r consumer_flake_root < /run/current-system/keystone-system-flake || consumer_flake_root=""
fi
if [[ -z "$consumer_flake_root" ]]; then
  manifest_consumer="$(jq -r '.consumerFlakeAgents // ""' "$manifest_path")"
  if [[ -n "$manifest_consumer" ]]; then
    # The manifest stores `<flake>/agents` already; strip the trailing /agents
    # to get the flake root so the rest of this script can re-append per-tool.
    consumer_flake_root="${manifest_consumer%/agents}"
  fi
fi
if [[ -z "$consumer_flake_root" ]]; then
  echo "Error: cannot determine consumer-flake path. Set KEYSTONE_CONSUMER_FLAKE or ensure /run/current-system/keystone-system-flake is present." >&2
  exit 1
fi

CONSUMER_FLAKE_AGENTS="$consumer_flake_root/agents"
CONSUMER_FLAKE_SHARED="$CONSUMER_FLAKE_AGENTS/_shared"
# Canonical, spec-compliant skill tree. All CLI coding agents read from a
# home-dir symlink (`~/.agents/skills/` for Codex/Gemini/Copilot/Cursor/Kiro/
# OpenCode/Augment, `~/.claude/skills/` for Claude Code) that resolves here.
# See docs/research/agent-skills.md for the standard.
CANONICAL_SKILLS_DEST="$CONSUMER_FLAKE_AGENTS/skills"
# Optional user-authored override for the skill map. Same flat schema as
# archetypes.yaml.skills. Wholesale-replace merge: user keys win on conflict;
# user-only keys are emitted as new skills. Absent file is fine.
USER_SKILLS_YAML="$CONSUMER_FLAKE_SHARED/skills.yaml"

json_get() {
  local filter="$1"
  jq -r "$filter" "$manifest_path"
}

json_get_lines() {
  local filter="$1"
  jq -r "$filter | .[]" "$manifest_path"
}

yaml_quote() {
  jq -Rn --arg value "$1" '$value'
}

write_file() {
  local target="$1"
  local content="$2"
  local target_dir
  local tmp

  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  rm -f "$target"

  tmp="$(mktemp "$target.tmp.XXXXXX")"
  printf '%s' "$content" > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$target"
}

append_file_content() {
  local output_file="$1"
  local source_file="$2"

  printf '\n' >> "$output_file"
  cat "$source_file" >> "$output_file"
}

render_template() {
  local template_path="$1"
  local content

  content="$(cat "$template_path")"
  content="${content//__CAPABILITIES__/$capabilities_display}"
  content="${content//__DEVELOPMENT_MODE__/$development_mode_display}"
  content="${content//__PUBLISHED_COMMANDS__/$published_commands_display}"
  content="${content//__ALLOWED_ROUTES__/$ks_allowed_routes}"

  printf '%s\n' "$content"
}

render_skill_md() {
  local name="$1"
  local description="$2"
  local body="$3"

  cat <<EOF
---
name: $name
description: "$(printf '%s' "$description" | sed 's/"/\\"/g')"
---

$body
EOF
}

command_template_name() {
  local template
  template="$(jq -r --arg k "$1" '.[$k].template // empty' <<< "$merged_skills_json")"
  if [[ -n "$template" ]]; then
    printf '%s' "$template"
    return
  fi
  case "$1" in
    ks-system) printf '%s' "ks.template.md" ;;
    ks-assistant) printf '%s' "ks-assistant.template.md" ;;
    ks-notes) printf '%s' "ks-notes.template.md" ;;
    ks-projects) printf '%s' "ks-projects.template.md" ;;
    ks-dev) printf '%s' "ks-dev.template.md" ;;
    *) return 1 ;;
  esac
}

command_description() {
  local desc
  desc="$(jq -r --arg k "$1" '.[$k].description // empty' <<< "$merged_skills_json")"
  if [[ -n "$desc" ]]; then
    printf '%s' "$desc"
    return
  fi
  case "$1" in
    ks-system)
      desc="Keystone system — may start keystone_system/issue or keystone_system/doctor"
      if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
        desc+=", or executive_assistant workflows"
      fi
      printf '%s' "$desc"
      ;;
    ks-assistant) printf '%s' "Personal assistant — may start personal_assistant/reservation, personal_assistant/birthday, personal_assistant/calendar_prioritize, or personal_assistant/memory_search" ;;
    ks-notes) printf '%s' "Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup" ;;
    ks-projects) printf '%s' "Project workflows — may start project/onboard, project/press_release, or project/success" ;;
    ks-dev) printf '%s' "Keystone development — may start keystone_system/develop, keystone_system/issue, keystone_system/convention, or keystone_system/doctor" ;;
    *) return 1 ;;
  esac
}

# Colocate conventions and roles for a skill. Each unique source file is
# written once to `<consumer-flake>/agents/_shared/conventions/<name>.md`
# (the central, deduplicated copy), then a symlink is created from the
# skill directory pointing at the central file. Multiple skills referencing
# the same convention end up with separate symlinks to the same canonical
# file, instead of duplicated bytes across skill dirs.
colocate_skill_conventions() {
  local skill_key="$1"
  local target_dir="$2"
  local canonical_dir="$CONSUMER_FLAKE_SHARED/conventions"
  local conv_name src_file canonical_file

  mkdir -p "$target_dir"

  while IFS= read -r conv_name; do
    [[ -z "$conv_name" ]] && continue
    src_file="$conventions_dir/${conv_name}.md"
    if [[ -f "$src_file" ]]; then
      canonical_file="${canonical_dir}/${conv_name}.md"
      write_file "$canonical_file" "$(cat "$src_file")"
      ln -snf "../../_shared/conventions/${conv_name}.md" "${target_dir}/${conv_name}.md"
      canonical_conventions_used[$conv_name]=1
    fi
  done < <(jq -r --arg k "$skill_key" '.[$k].colocated_conventions[]? // empty' <<< "$merged_skills_json")

  while IFS= read -r conv_name; do
    [[ -z "$conv_name" ]] && continue
    src_file="$conventions_dir/roles/${conv_name}.md"
    if [[ -f "$src_file" ]]; then
      canonical_file="${canonical_dir}/${conv_name}.md"
      write_file "$canonical_file" "$(cat "$src_file")"
      ln -snf "../../_shared/conventions/${conv_name}.md" "${target_dir}/${conv_name}.md"
      canonical_conventions_used[$conv_name]=1
    fi
  done < <(jq -r --arg k "$skill_key" '.[$k].colocated_roles[]? // empty' <<< "$merged_skills_json")
}

ks_allowed_routes_lines=(
  "- Keystone usage help, module discovery, configuration guidance, and workflow recommendations: answer directly when no workflow is needed."
  "- Feature requests, bug reports, paper cuts, and missing Keystone capabilities: start \`keystone_system/issue\`."
  "- Keystone health checks and troubleshooting: start \`keystone_system/doctor\` when the user wants diagnosis rather than documentation."
)

resolved_capabilities=()
while IFS= read -r capability; do
  resolved_capabilities+=("$capability")
done < <(json_get_lines '.resolvedCapabilities')

published_commands=()
while IFS= read -r command_id; do
  published_commands+=("$command_id")
done < <(json_get_lines '.publishedCommands')

repos=()
while IFS= read -r repo_name; do
  repos+=("$repo_name")
done < <(json_get_lines '.repos')

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'assistant'; then
  ks_allowed_routes_lines+=("- Personal assistant requests (reservations, birthdays, calendar, photo memories): direct the user to \`/ks-assistant\` instead of handling directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  ks_allowed_routes_lines+=("- Notes workflows (repair, inbox, init, setup): direct the user to \`/ks-notes\` instead of starting a notes workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project'; then
  ks_allowed_routes_lines+=("- Project workflows (onboard, press release, success): direct the user to \`/ks-projects\` instead of starting a project workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
  ks_allowed_routes_lines+=("- Executive assistant workflows (calendar, inbox, events, portfolio reviews, task coordination): direct the user to \`/ks-ea\` instead of starting executive_assistant workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'engineer'; then
  ks_allowed_routes_lines+=("- Engineering workflows (implementation, code review, architecture, CI): direct the user to \`/ks-engineer\` instead of starting engineer workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'product'; then
  ks_allowed_routes_lines+=("- Product workflows (press releases, milestones, stakeholder communication): direct the user to \`/ks-product\` instead of starting project workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project-manager'; then
  ks_allowed_routes_lines+=("- Project management workflows (task decomposition, tracking, boards): direct the user to \`/ks-project-manager\` instead of managing tasks directly.")
fi

repo_checkout="$(json_get '.repoCheckout')"
archetype="$(json_get '.archetype')"
development_mode="$(json_get '.developmentMode')"

if [[ "$repo_checkout" == "null" || -z "$repo_checkout" ]]; then
  echo "Error: manifest does not declare a live keystone repo checkout" >&2
  exit 1
fi

if [[ ! -d "$repo_checkout" ]]; then
  repo_slug="ncrmro/keystone"
  if [[ "$repo_checkout" == */repos/*/* ]]; then
    repo_slug="${repo_checkout##*/repos/}"
  elif [[ "$repo_checkout" == */.keystone/repos/*/* ]]; then
    repo_slug="${repo_checkout##*/.keystone/repos/}"
  fi
  echo "Live keystone repo checkout not found at $repo_checkout — cloning $repo_slug..."
  mkdir -p "$(dirname "$repo_checkout")"
  git clone "https://github.com/$repo_slug.git" "$repo_checkout"
fi

conventions_dir="$repo_checkout/conventions"
templates_dir="$repo_checkout/modules/terminal/agents/templates"
archetypes_file="$conventions_dir/archetypes.yaml"

if [[ ! -f "$archetypes_file" ]]; then
  echo "Error: archetypes.yaml not found at $archetypes_file" >&2
  exit 1
fi

# Build the effective skill map: keystone defaults + optional consumer-flake
# overrides. Field-level merge (jq's `*` operator): missing user fields fall
# back to keystone defaults, explicit user fields override per-field. This
# lets a user override just `description` or `colocated_conventions` for a
# built-in skill without having to repeat `template` (which would otherwise
# fall back to a derived name like `ks-engineer-skill.template.md` that
# doesn't exist, silently dropping the skill).
keystone_skills_json="$(yq -o json '.skills // {}' "$archetypes_file")"
if [[ -f "$USER_SKILLS_YAML" ]]; then
  user_skills_json="$(yq -o json '.skills // {}' "$USER_SKILLS_YAML")"
else
  user_skills_json='{}'
fi
merged_skills_json="$(jq -n --argjson a "$keystone_skills_json" --argjson b "$user_skills_json" '$a * $b')"

capabilities_display="_none_"
if [[ ${#resolved_capabilities[@]} -gt 0 ]]; then
  capabilities_display="$(printf '%s, ' "${resolved_capabilities[@]}")"
  capabilities_display="${capabilities_display%, }"
fi

published_commands_display="_none_"
if [[ ${#published_commands[@]} -gt 0 ]]; then
  published_commands_display="$(printf '%s, ' "${published_commands[@]}")"
  published_commands_display="${published_commands_display%, }"
fi

development_mode_display="disabled"
if [[ "$development_mode" == "true" ]]; then
  development_mode_display="enabled"
fi

ks_allowed_routes="$(printf '%s\n' "${ks_allowed_routes_lines[@]}")"

global_agents_tmp="$(mktemp)"
cat <<'EOF' > "$global_agents_tmp"
# Shared-surface tracking

- For issue-backed work, post `Work Started` and `Work Update` comments on the source issue.
- Treat issues, pull requests, milestones, and boards as the canonical public record.

# Commit format

- Use Conventional Commits: `type(scope): subject`.
- Valid types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `build`.
- Each commit SHOULD represent one logical change.
EOF

while IFS= read -r convention_name; do
  append_file_content "$global_agents_tmp" "$conventions_dir/${convention_name}.md"
done < <(yq -r ".archetypes.\"$archetype\".inlined_conventions[]?" "$archetypes_file")

global_agents_content="$(cat "$global_agents_tmp")"
rm -f "$global_agents_tmp"

write_file "$HOME/.keystone/AGENTS.md" "$global_agents_content"
# Canonical instruction file lives in the consumer flake at _shared/AGENTS.md.
# Home-manager activation symlinks each per-tool instruction filename
# (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md, ~/.codex/AGENTS.md) directly to
# this canonical path.
write_file "$CONSUMER_FLAKE_SHARED/AGENTS.md" "$global_agents_content"
# OpenCode keeps its own home.file.text-managed instruction file via
# modules/terminal/conventions.nix; the sync script also writes it here
# so manual invocations don't leave it stale.
write_file "$HOME/.config/opencode/AGENTS.md" "$global_agents_content"

repos_agents_tmp="$(mktemp)"
{
  cat <<'EOF'
# Keystone repos

The standard Keystone checkout layout is `~/repos/{owner}/{repo}/`. The
consumer flake convention is `~/repos/{owner}/ks-config`, and local Keystone
development prefers the sibling checkout at `~/repos/{owner}/keystone`.
`~/.keystone/repos/` is legacy compatibility only.

## Repositories

EOF
  for repo_name in "${repos[@]}"; do
    if [[ "$repo_name" == */notes ]]; then
      continue
    fi
    printf '### `%s` → [`%s/AGENTS.md`](%s/AGENTS.md)\n\n' "$repo_name" "$repo_name" "$repo_name"
  done
} > "$repos_agents_tmp"

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  cat <<'EOF' >> "$repos_agents_tmp"

## Notes command guidance

- Route durable note capture, note cleanup, inbox promotion, and notebook repair requests through `ks-notes`.
- Use `ks-notes` proactively when a task produces durable decisions, meaningful findings, or reusable operational context.
- On Keystone systems, the human notebook lives at `NOTES_DIR` (`~/notes` by default), not in the repo checkout inventory.
- When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read `~/.config/keystone/conventions/process.notes.md` and `~/.config/keystone/conventions/tool.zk-notes.md`.
- When a task is tied to an issue, pull request, or milestone, capture normalized refs in notes when known and keep the shared surface as the public system of record.
EOF
fi

cat <<'EOF' >> "$repos_agents_tmp"

## Shared-surface tracking

- For issue-backed work, follow `process.issue-journal` and post `Work Started` and `Work Update` comments on the source issue.
- For milestone and board-backed work, follow `process.project-board` so issue and PR state stays visible on the shared board.
- Treat issues, pull requests, milestones, and boards as the canonical public record for status, review state, and decisions that affect collaborators.
- Use notes to preserve durable rationale and memory, not to replace shared-surface tracking.
EOF

while IFS= read -r convention_name; do
  append_file_content "$repos_agents_tmp" "$conventions_dir/${convention_name}.md"
done < <(yq -r '.archetypes."keystone-developer".inlined_conventions[]?' "$archetypes_file")

repos_agents_content="$(cat "$repos_agents_tmp")"
rm -f "$repos_agents_tmp"

write_file "$HOME/.keystone/repos/AGENTS.md" "$repos_agents_content"

# Legacy cleanup: remove old per-tool skill / command artifacts that predate
# the `.agents/skills/` convention. Idempotent — safe to re-run.
for command_file in ks.md ks.system.md ks.assistant.md ks.notes.md ks.projects.md ks.dev.md ks.ea.md ks.engineer.md ks.product.md ks.project-manager.md ks.pm.md; do
  rm -f "$HOME/.claude/commands/$command_file"
  rm -f "$HOME/.config/opencode/commands/$command_file"
done
for command_file in ks.toml notes.toml projects.toml dev.toml deepwork.toml ks.ea.toml ks.engineer.toml ks.product.toml ks.pm.toml wrap-up.toml; do
  rm -f "$HOME/.gemini/commands/$command_file"
done
# Remove the old per-tool skill trees in the consumer flake (superseded by
# the canonical `agents/skills/` tree). Also clean up the previous PR #542
# location at `agents/_shared/skills/`.
for legacy_path in \
  "$CONSUMER_FLAKE_AGENTS/claude/skills" \
  "$CONSUMER_FLAKE_AGENTS/gemini/skills" \
  "$CONSUMER_FLAKE_AGENTS/codex/skills" \
  "$CONSUMER_FLAKE_AGENTS/_shared/skills" \
  "$CONSUMER_FLAKE_AGENTS/claude/CLAUDE.md" \
  "$CONSUMER_FLAKE_AGENTS/gemini/GEMINI.md" \
  "$CONSUMER_FLAKE_AGENTS/codex/AGENTS.md"; do
  rm -rf "$legacy_path"
done

# Build the set of skills to render: the union of (manifest-published ks-*
# commands) and (always-on yaml keys). Always-on keys are anything in the
# merged skill map that doesn't start with `ks-` — deepwork-family entries
# and any user-authored additions in _shared/skills.yaml. ks-* keys are
# emitted only when published by the user's manifest.
skills_to_emit=()
declare -A seen_skills=()
while IFS= read -r yaml_key; do
  [[ -z "$yaml_key" ]] && continue
  if [[ "$yaml_key" != ks-* ]] && [[ -z "${seen_skills[$yaml_key]:-}" ]]; then
    skills_to_emit+=("$yaml_key")
    seen_skills[$yaml_key]=1
  fi
done < <(jq -r 'keys[]' <<< "$merged_skills_json")
for command_id in "${published_commands[@]}"; do
  [[ -z "$command_id" ]] && continue
  if [[ -z "${seen_skills[$command_id]:-}" ]]; then
    skills_to_emit+=("$command_id")
    seen_skills[$command_id]=1
  fi
done

# Prune stale skill directories before rendering. A skill that was emitted
# on a previous sync but is no longer in the merged map (user removed it
# from `_shared/skills.yaml`) or no longer in `publishedCommands` (host
# capability set changed) must be removed from the consumer flake — the
# files would otherwise stay tracked and discoverable. Idempotent.
if [[ -d "$CANONICAL_SKILLS_DEST" ]]; then
  while IFS= read -r -d '' existing_dir; do
    skill_name="$(basename "$existing_dir")"
    if [[ -z "${seen_skills[$skill_name]:-}" ]]; then
      rm -rf "$existing_dir"
    fi
  done < <(find "$CANONICAL_SKILLS_DEST" -mindepth 1 -maxdepth 1 -type d -print0)
fi

# Track which canonical convention files this sync will emit, so the
# colocate helper can prune stale ones afterwards. The set is populated as
# colocate_skill_conventions writes files.
declare -A canonical_conventions_used=()

# Render each skill once into the canonical agents/skills/<name>/ tree.
# Claude reads it via `~/.claude/skills` → consumer-flake/agents/skills/
# symlink; Codex/Gemini/Copilot/Cursor/Kiro/OpenCode/Augment read it via
# `~/.agents/skills/` → same target. Both symlinks are created by
# home-manager activation in modules/terminal/agents/assets.nix.
for skill_key in "${skills_to_emit[@]}"; do
  description="$(command_description "$skill_key" || printf '%s' "")"
  if ! template_name="$(command_template_name "$skill_key" 2>/dev/null)"; then
    template_name=""
  fi
  if [[ -z "$template_name" ]]; then
    template_name="${skill_key}-skill.template.md"
  fi
  template_path="$templates_dir/$template_name"
  if [[ ! -f "$template_path" ]]; then
    echo "Warning: skill '$skill_key' references missing template '$template_path'; skipping" >&2
    continue
  fi

  command_body="$(render_template "$template_path")"
  skill_md="$(render_skill_md "$skill_key" "$description" "$command_body")"
  write_file "$CANONICAL_SKILLS_DEST/${skill_key}/SKILL.md" "$skill_md"
  colocate_skill_conventions "$skill_key" "$CANONICAL_SKILLS_DEST/${skill_key}"
done

# Prune stale canonical conventions. Any .md file under
# `_shared/conventions/` that was NOT written by this sync (no longer
# referenced by any emitted skill's colocated_conventions / colocated_roles)
# is removed. README.md is excluded — it's re-rendered below regardless.
if [[ -d "$CONSUMER_FLAKE_SHARED/conventions" ]]; then
  while IFS= read -r -d '' existing_file; do
    base_name="$(basename "$existing_file" .md)"
    [[ "$(basename "$existing_file")" == "README.md" ]] && continue
    if [[ -z "${canonical_conventions_used[$base_name]:-}" ]]; then
      rm -f "$existing_file"
    fi
  done < <(find "$CONSUMER_FLAKE_SHARED/conventions" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0)
fi

# README emission. Every managed directory under `agents/` gets a README
# explaining its purpose, layout, and how tools consume it. Re-written on
# each sync — edits in these files are clobbered. The `claude/agents/`
# README documents a user-authored directory; the README itself is still
# keystone-managed and overwritten.
mkdir -p "$CONSUMER_FLAKE_AGENTS/claude/agents"

write_file "$CONSUMER_FLAKE_AGENTS/README.md" '# Agents

This directory holds the agent assets installed on this host. Every CLI
coding agent — Claude Code, Codex, Gemini CLI, GitHub Copilot CLI,
Cursor, Rovo Dev, Kiro, OpenCode, Augment — reads from this tree via
home-dir symlinks that home-manager activation creates.

## Layout

| Path | Purpose |
|---|---|
| `_shared/AGENTS.md` | Single canonical instruction file. The per-tool symlinks (`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md`) all resolve here. |
| `_shared/conventions/` | Centralized conventions and roles, referenced by skills via per-skill symlinks. |
| `skills/` | Canonical skill tree per the [`.agents/skills/` open standard][spec]. Read by every spec-compliant agent. |
| `claude/agents/` | Claude-specific subagent personas. Read via `~/.claude/agents/`. |

## Maintenance

- `ks sync-agent-assets` regenerates keystone-curated content. Per-host
  state (capabilities, archetype) determines which skills land. The
  command is manual — `ks switch` / `ks update --dev` never write here
  implicitly.
- User-authored content in `claude/agents/<persona>.md` and
  `_shared/skills.yaml` survives sync.
- README files in this tree (including this one) are regenerated;
  edits there will be overwritten.

[spec]: https://github.com/ncrmro/keystone/blob/main/docs/research/agent-skills.md
'

write_file "$CONSUMER_FLAKE_SHARED/README.md" '# _shared

Canonical, deduplicated agent assets for every CLI coding agent on this
host.

## Layout

- **`AGENTS.md`** — host-rendered instruction file. Interpolates
  resolved capabilities, dev-mode flag, published commands, and allowed
  routes for this host. The per-tool instruction-file symlinks
  (`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md`)
  all resolve here, so every tool reads the same bytes.
- **`conventions/`** — centralized convention and role bodies, each
  committed once. Skills under `../skills/<name>/` reference these via
  symlinks. A convention bump shows as a single diff in the canonical
  file, not duplicated across every skill that uses it.
- **`skills.yaml`** *(optional, user-authored)* — overrides or additions
  to the keystone-default skill set. Same flat-map schema as
  `conventions/archetypes.yaml.skills` in the keystone repo.

`AGENTS.md` and `conventions/` are regenerated by `ks sync-agent-assets`.
`skills.yaml` is user-authored and survives sync.
'

write_file "$CONSUMER_FLAKE_SHARED/conventions/README.md" '# Shared conventions

Centralized convention and role bodies referenced by skills under
`../../skills/<name>/`. Each file appears once here and is symlinked
into every skill that references it via `colocated_conventions` or
`colocated_roles` in `conventions/archetypes.yaml.skills` (keystone
repo).

## Naming

- `process.<name>.md` — process conventions (how we ship, review,
  branch, etc.)
- `code.<name>.md` — code-level conventions (shell scripts, comments,
  etc.)
- `tool.<name>.md` — tool-specific conventions (forgejo, github,
  mermaid, etc.)
- `<role>.md` — role definitions (`software-engineer`, `code-reviewer`,
  `project-lead`, etc.) — flat namespace, no `role.` prefix.

## Source of truth

These files are copies of keystone repo `conventions/*.md` and
`conventions/roles/*.md`. Edits here are clobbered by the next
`ks sync-agent-assets`. To change a convention, edit the keystone repo
(or your consumer-flake overlay) instead.
'

write_file "$CANONICAL_SKILLS_DEST/README.md" '# Skills

Canonical skill tree per the [`.agents/skills/` open standard][spec].
Every CLI coding agent reads this directory:

- **Codex, Gemini CLI, GitHub Copilot CLI, Cursor, Rovo Dev, Kiro,
  OpenCode, Augment** read it via `~/.agents/skills/` (the user-tier
  spec path).
- **Claude Code** reads it via `~/.claude/skills/` (Claude vendor
  path). Same target — home-manager activation symlinks both at the
  same canonical directory.

## Layout

Each skill is a subdirectory named lowercase-with-hyphens per the
spec. Inside:

- `SKILL.md` — frontmatter (`name` + `description`) + body. The
  `name:` field MUST match the directory name; mismatch causes silent
  load failure in spec-compliant agents.
- `<convention>.md` — symlinks into `../../_shared/conventions/`, one
  per colocated convention or role.

## Naming

- `ks-*` — keystone-curated skills tied to a slash-command id
  published by this host (e.g., `/ks-engineer`, `/ks-notes`). Only
  emitted if the host capability set includes the matching command.
- Bare names (`deepwork`, `wrap-up`, `review`) — always-on workflow
  skills that don'\''t gate on capability.

Add user-authored skills via `<consumer-flake>/agents/_shared/skills.yaml`.

[spec]: https://github.com/ncrmro/keystone/blob/main/docs/research/agent-skills.md
'

write_file "$CONSUMER_FLAKE_AGENTS/claude/README.md" '# Claude-specific assets

Files that only Claude Code reads. Other CLI coding agents read from
`../skills/` and `../_shared/` — those are cross-tool. This directory
holds the Claude-only surface.

## Layout

- **`agents/`** — Claude subagent personas (`name` + `description`
  frontmatter, full persona body). Claude'\''s Task tool discovers
  subagents from this path and uses the `description` to decide when to
  delegate.

The `~/.claude/skills/` symlink resolves to `../skills/` (the
cross-tool canonical), so Claude shares the skill catalog with every
other spec-compliant agent. Only subagents are vendor-specific.

Gemini and Codex have their own subagent/persona surfaces upstream,
but keystone does not currently emit content for them — only Claude.
The directory layout is keystone-managed; the upstream tools may
have richer support that keystone simply hasn'\''t wired in yet.
'

write_file "$CONSUMER_FLAKE_AGENTS/claude/agents/README.md" '# Claude subagents

Personas Claude Code can delegate to via its Task tool. Each `.md`
file declares a persona with frontmatter:

```yaml
---
name: <persona-name>
description: When to delegate to this agent
---
<body — instructions for the persona>
```

The `description` field is load-bearing — Claude uses it to decide
when to delegate. Front-load the trigger words ("Use when…").

## Authorship

Files here (other than this README) are **user-authored**. The
`ks sync-agent-assets` script does not generate persona files; it
only manages this README.

## Subagents vs colocated roles

Keystone'\''s skill `colocated_roles` (e.g., `software-engineer`,
`code-reviewer` colocated into `ks-engineer/`) ship the role text as
*conventions* inside a skill. To expose a role as a Claude *subagent*
(something Claude can explicitly delegate to via the Task tool),
author a persona file here. The two paths are independent: a role can
be colocated without a subagent, or have a subagent without being
colocated.
'
