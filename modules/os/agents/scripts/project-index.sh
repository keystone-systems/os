#!/usr/bin/env bash
set -euo pipefail

NOTES_DIR="${NOTES_DIR:-$HOME/notes}"

usage() {
  cat <<'EOF'
Usage:
  keystone-project-index list
  keystone-project-index get <slug>
  keystone-project-index normalize-repo <url>
EOF
}

valid_slug() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

normalize_repo_url() {
  local url="$1"
  local normalized=""

  case "$url" in
    ssh://*)
      normalized="${url#ssh://}"
      normalized="${normalized#*@}"
      normalized="${normalized#*/}"
      ;;
    http://*|https://*)
      normalized="${url#http://}"
      normalized="${normalized#https://}"
      normalized="${normalized#*/}"
      ;;
    git@*:*/*)
      normalized="${url#git@}"
      normalized="${normalized#*:}"
      ;;
    *)
      echo "error: unsupported repo URL '${url}'" >&2
      return 1
      ;;
  esac

  normalized="${normalized%.git}"
  normalized="${normalized%%\?*}"
  normalized="${normalized%%#*}"

  if [[ "$normalized" != */* ]]; then
    echo "error: failed to normalize repo URL '${url}'" >&2
    return 1
  fi

  printf '%s\n' "$normalized"
}

project_index_json() {
  local zk_json

  if ! zk_json=$(zk --notebook-dir "$NOTES_DIR" list index/ --format json --quiet); then
    echo "error: failed to discover project hubs via zk in ${NOTES_DIR}" >&2
    return 1
  fi

  printf '%s\n' "$zk_json" | jq -c '
    def merged_tags:
      if ((.metadata.tags // []) | length) > 0 then
        (.metadata.tags // [])
      else
        (.tags // [])
      end
      | map(select(type == "string"))
      | unique;

    def explicit_project_tags:
      merged_tags
      | map(select(startswith("project/")) | sub("^project/"; ""))
      | unique;

    def bare_project_tags:
      if (merged_tags | index("project")) == null then
        []
      else
        merged_tags
        | map(
            select(
              test("^[a-z0-9]+(-[a-z0-9]+)*$")
              and . != "index"
              and . != "project"
              and . != "archive"
            )
          )
        | unique
      end;

    def status_markers:
      merged_tags
      | map(select(startswith("status/") or . == "archive"))
      | unique;

    def inferred_project:
      if (.metadata.project // "") != "" then
        .metadata.project
      elif (explicit_project_tags | length) == 1 then
        explicit_project_tags[0]
      elif (explicit_project_tags | length) > 1 then
        "__AMBIGUOUS__:" + (explicit_project_tags | join(","))
      elif (bare_project_tags | length) == 1 then
        bare_project_tags[0]
      elif (bare_project_tags | length) > 1 then
        "__AMBIGUOUS__:" + (bare_project_tags | join(","))
      elif (
        (.absPath | split("/") | last | sub("\\.md$"; "") | sub("^[0-9]{8,12} "; ""))
        | test("^[a-z0-9]+(-[a-z0-9]+)*$")
      ) then
        (.absPath | split("/") | last | sub("\\.md$"; "") | sub("^[0-9]{8,12} "; ""))
      else
        ""
      end;

    {
      projects:
        [
          .[]
          | select((.metadata.type // "") == "index")
          | select((status_markers | index("status/archived")) == null)
          | select((status_markers | index("archive")) == null)
          | select((.metadata.status // "") != "archived")
          | {
              slug: inferred_project,
              hub_path: .absPath,
              name: (.metadata.name // .metadata.title // inferred_project),
              description: (.metadata.description // ""),
              priority: (.metadata.priority // null),
              repos: ((.metadata.repos // []) | map(select(type == "string" and . != "")) | unique),
              sources: (.metadata.sources // [])
            }
          | select(.slug != "")
        ]
    }
  '
}

validate_projects() {
  local projects_json="$1"
  printf '%s\n' "$projects_json" | jq -e '
    .projects
    | all(
        if (.slug | startswith("__AMBIGUOUS__:")) then
          false
        else
          (.slug | test("^[a-z0-9]+(-[a-z0-9]+)*$"))
        end
      )
  ' >/dev/null
}

print_project_validation_error() {
  local projects_json="$1"

  local ambiguous
  ambiguous=$(printf '%s\n' "$projects_json" | jq -r '
    .projects[]
    | select(.slug | startswith("__AMBIGUOUS__:"))
    | "error: active project hub \(.hub_path) has ambiguous project tags: \(.slug | sub("^__AMBIGUOUS__:"; ""))"
  ' | head -n 1)
  if [[ -n "$ambiguous" ]]; then
    echo "$ambiguous" >&2
    return
  fi

  local invalid
  invalid=$(printf '%s\n' "$projects_json" | jq -r '
    .projects[]
    | select((.slug | test("^[a-z0-9]+(-[a-z0-9]+)*$")) | not)
    | "error: active project hub \(.hub_path) uses invalid project slug '\''\(.slug)'\''"
  ' | head -n 1)
  if [[ -n "$invalid" ]]; then
    echo "$invalid" >&2
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
  fi

  case "$1" in
    list)
      local projects_json
      projects_json=$(project_index_json)
      if ! validate_projects "$projects_json"; then
        print_project_validation_error "$projects_json"
        exit 1
      fi
      printf '%s\n' "$projects_json"
      ;;
    get)
      if [[ $# -ne 2 ]]; then
        usage >&2
        exit 1
      fi
      if ! valid_slug "$2"; then
        echo "error: invalid project slug '$2'" >&2
        exit 1
      fi
      local projects_json
      projects_json=$(project_index_json)
      if ! validate_projects "$projects_json"; then
        print_project_validation_error "$projects_json"
        exit 1
      fi
      local project_json
      project_json=$(printf '%s\n' "$projects_json" | jq -c --arg slug "$2" '.projects[] | select(.slug == $slug)' | head -n 1)
      if [[ -z "$project_json" ]]; then
        echo "error: project '$2' not found in zk project index" >&2
        exit 1
      fi
      printf '%s\n' "$project_json"
      ;;
    normalize-repo)
      if [[ $# -ne 2 ]]; then
        usage >&2
        exit 1
      fi
      normalize_repo_url "$2"
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
