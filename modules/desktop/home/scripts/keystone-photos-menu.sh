#!/usr/bin/env bash
# keystone-photos-menu — Walker/Elephant adapter for Keystone Photos.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-photos-menu"
RESULTS_PATH="${STATE_DIR}/results.json"
QUERY_PATH="${STATE_DIR}/query.txt"

keystone_cmd() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return 0
  fi

  if [[ -x "$HOME/.local/bin/$command_name" ]]; then
    printf "%s\n" "$HOME/.local/bin/$command_name"
    return 0
  fi

  printf "Unable to locate %s\n" "$command_name" >&2
  exit 1
}

notify() {
  notify-send "$@"
}

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

current_query() {
  if [[ -f "$QUERY_PATH" ]]; then
    cat "$QUERY_PATH"
  fi
}

write_state() {
  local query="$1"
  local results="$2"

  ensure_state_dir
  printf '%s\n' "$query" >"$QUERY_PATH"
  printf '%s\n' "$results" >"$RESULTS_PATH"
}

results_json() {
  if [[ -f "$RESULTS_PATH" ]]; then
    cat "$RESULTS_PATH"
  else
    printf '[]\n'
  fi
}

search_query() {
  local query="${1:-}"
  [[ -n "$query" ]] || return 1

  local results=""
  if ! results="$("$(keystone_cmd ks)" photos search --text "$query" --json --limit 50 2>/dev/null)"; then
    notify "Photo search failed" "Unable to search Immich for '$query'."
    return 1
  fi

  write_state "$query" "$results"
}

entries_json() {
  local query=""
  query="$(current_query)"

  jq -n \
    --arg query "$query" \
    --argjson results "$(results_json)" '
    [
      {
        Text: "Search photos",
        Subtext: (if ($query | length) > 0 then "Current query: " + $query else "Search Keystone Photos" end),
        Value: "search",
        Icon: "edit-find-symbolic"
      }
    ]
    +
    (
      if ($results | length) == 0 then
        [
          {
            Text: "No photo results loaded",
            Subtext: "Run a search to populate results",
            Value: "search",
            Icon: "image-missing-symbolic"
          }
        ]
      else
        (
          $results
          | map({
              Text: (if (.filename | length) > 0 then .filename else .id end),
              Subtext: (
                [
                  (.datetime // "" | sub("\\.000Z$"; "Z")),
                  (.assetType // ""),
                  (.match.query // "" | select(length > 0))
                ]
                | map(select(length > 0))
                | join(" • ")
              ),
              Value: ("preview\t" + .id),
              Icon: "image-x-generic-symbolic",
              Preview: ("keystone-photos-menu preview-text " + (.id | @sh)),
              PreviewType: "command"
            })
        )
      end
    )
  '
}

preview_text() {
  local asset_id="${1:-}"
  [[ -n "$asset_id" ]] || exit 0

  results_json | jq -r --arg asset_id "$asset_id" '
    map(select(.id == $asset_id)) | first // {}
    | [
        (.filename // $asset_id),
        "",
        ("Taken: " + (.datetime // "unknown")),
        ("Type: " + (.assetType // "unknown")),
        (if (.originalPath // "" | length) > 0 then "Path: " + .originalPath else empty end),
        (if (.match.query // "" | length) > 0 then "Query: " + .match.query else empty end)
      ]
    | join("\n")
  '
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m "menus:keystone-photos" -p "Photos" >/dev/null 2>&1 &
}

prompt_query() {
  local existing_query=""
  local query=""

  existing_query="$(current_query || true)"

  walker -q >/dev/null 2>&1 || true
  query="$(
    printf '%s\n' "$existing_query" \
      | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "Search photos…" 2>/dev/null \
      | tr -d '\r'
  )" || true

  [[ -n "$query" ]] || return 0
  search_query "$query" || return 1
  open_menu
}

dispatch() {
  local payload="${1:-}"
  local action=""
  local arg1=""

  IFS=$'\t' read -r action arg1 <<<"$payload"

  case "$action" in
    search)
      prompt_query
      ;;
    preview)
      detach "$(keystone_cmd ks)" photos preview "$arg1"
      ;;
    *)
      printf "Unknown photos menu action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  prompt-query)
    shift
    prompt_query "$@"
    ;;
  entries-json)
    shift
    entries_json "$@"
    ;;
  preview-text)
    shift
    preview_text "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-photos-menu {open-menu|prompt-query|entries-json|preview-text|dispatch} ..." >&2
    exit 1
    ;;
esac
