#!/usr/bin/env bash
# keystone-printer-menu — CUPS printer default controller for terminal and Elephant.

set -euo pipefail

notify() {
  notify-send "$@"
}

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

cups_available() {
  command -v lpstat >/dev/null 2>&1
}

cups_unavailable_reason() {
  if ! cups_available; then
    printf "lpstat is not available in PATH.\n"
    return 0
  fi

  printf "Printer defaults are unavailable.\n"
}

blocked_entry_json() {
  local title="$1"
  local reason="$2"

  jq -n --arg title "$title" --arg reason "$reason" '
    [
      {
        Text: $title,
        Subtext: $reason,
        Value: "blocked",
        Preview: ("printf " + (($title + "\n\n" + $reason + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

default_printer_name() {
  lpstat -d 2>/dev/null | awk '/system default destination:/ {print $NF}'
}

list_printers_raw() {
  # Output: one printer name per line
  lpstat -p 2>/dev/null | awk '/^printer / {print $2}'
}

DISCOVERY_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/keystone/printer-discovery.uris"
DISCOVERY_LOCK_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/keystone/printer-discovery.lock"
DISCOVERY_CACHE_TTL=300 # seconds before cache is considered stale

refresh_discoverable_background() {
  # Spawn a background job to refresh the discovery cache. Exits immediately.
  if ! cups_available; then
    return 0
  fi
  local cache_dir
  cache_dir="$(dirname "$DISCOVERY_CACHE_FILE")"
  mkdir -p "$cache_dir"
  # Skip if a refresh is already running
  [[ -f "$DISCOVERY_LOCK_FILE" ]] && return 0
  (
    touch "$DISCOVERY_LOCK_FILE"
    timeout 15 lpinfo --include-schemes=dnssd -v 2>/dev/null \
      | awk '{print $2}' \
      > "$DISCOVERY_CACHE_FILE.tmp" \
      && mv "$DISCOVERY_CACHE_FILE.tmp" "$DISCOVERY_CACHE_FILE"
    rm -f "$DISCOVERY_LOCK_FILE"
  ) </dev/null >/dev/null 2>&1 &
  disown
}

list_discoverable_raw() {
  # Return cached URIs immediately; kick off a background refresh if stale.
  if ! cups_available; then
    return 0
  fi
  local now
  now=$(date +%s)
  local cache_mtime=0
  if [[ -f "$DISCOVERY_CACHE_FILE" ]]; then
    cache_mtime=$(stat -c %Y "$DISCOVERY_CACHE_FILE" 2>/dev/null || echo 0)
  fi
  local age=$(( now - cache_mtime ))
  if [[ $age -gt $DISCOVERY_CACHE_TTL ]] || [[ ! -f "$DISCOVERY_CACHE_FILE" ]]; then
    refresh_discoverable_background
  fi
  [[ -f "$DISCOVERY_CACHE_FILE" ]] && cat "$DISCOVERY_CACHE_FILE" || true
}

uri_display_name() {
  local uri="$1"
  # Extract the host component from dnssd://NAME._service._tcp.local/path
  # then URL-decode it.
  local encoded
  encoded=$(printf '%s' "$uri" | sed 's|dnssd://||; s|\._.*/.*||; s|\._.*||')
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "from urllib.parse import unquote; print(unquote('${encoded//\'/\\'\\'}'))" 2>/dev/null || printf '%s' "$encoded"
  else
    # Fallback: decode only %20 → space
    printf '%s' "$encoded" | sed 's/%20/ /g'
  fi
}

uri_to_slug() {
  local display_name="$1"
  # Lowercase, spaces and special chars → underscore, collapse runs, strip leading/trailing
  printf '%s' "$display_name" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '_' \
    | sed 's/^_//; s/_$//'
}

printer_description() {
  local name="$1"
  # lpstat -l -p shows description; fall back to name if unavailable
  lpstat -l -p "$name" 2>/dev/null \
    | awk '/Description:/ {$1=""; sub(/^ /, ""); print; exit}' \
    || printf "%s\n" "$name"
}

printers_json() {
  local printer_menu
  printer_menu=$(keystone_cmd keystone-printer-menu)

  if ! cups_available; then
    blocked_entry_json "Printers unavailable" "$(cups_unavailable_reason)"
    return 0
  fi

  local current_default=""
  current_default=$(default_printer_name)

  # Build list of configured printers
  local configured=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && configured+=("$name")
  done < <(list_printers_raw)

  # Build list of discoverable URIs
  local discoverable_uris=()
  while IFS= read -r uri; do
    [[ -n "$uri" ]] && discoverable_uris+=("$uri")
  done < <(list_discoverable_raw)

  # If nothing at all, show blocked entry
  if [[ ${#configured[@]} -eq 0 && ${#discoverable_uris[@]} -eq 0 ]]; then
    blocked_entry_json "No printers found" "No CUPS printers are configured and none were discovered on the network."
    return 0
  fi

  local entries_json="[]"

  # --- Configured printers first ---
  for name in "${configured[@]}"; do
    local is_default=false
    [[ "$name" == "$current_default" ]] && is_default=true

    local icon
    icon=$(if $is_default; then printf "  "; else printf "  "; fi)

    local subtext
    if $is_default; then
      subtext="current default"
    else
      subtext="set as default"
    fi

    local entry
    entry=$(jq -n \
      --arg icon "$icon" \
      --arg name "$name" \
      --arg subtext "$subtext" \
      --arg printer_menu "$printer_menu" \
      '{
        Text: ($icon + $name),
        Subtext: $subtext,
        Value: ("set-default\t" + $name),
        Preview: ($printer_menu + " preview-printer " + ($name | @sh)),
        PreviewType: "command"
      }')
    entries_json=$(jq -n --argjson arr "$entries_json" --argjson entry "$entry" '$arr + [$entry]')
  done

  # --- Discoverable but not yet configured ---
  for uri in "${discoverable_uris[@]}"; do
    local display_name
    display_name=$(uri_display_name "$uri")
    local slug
    slug=$(uri_to_slug "$display_name")

    # Skip if a configured printer already has this slug or a matching name
    local already_configured=false
    for existing in "${configured[@]}"; do
      if [[ "$existing" == "$slug" || "$(uri_to_slug "$existing")" == "$slug" ]]; then
        already_configured=true
        break
      fi
    done
    $already_configured && continue

    local entry
    entry=$(jq -n \
      --arg display_name "$display_name" \
      --arg slug "$slug" \
      --arg uri "$uri" \
      --arg printer_menu "$printer_menu" \
      '{
        Text: ("  " + $display_name),
        Subtext: "add and set as default",
        Value: ("add-and-default\t" + $slug + "\t" + $uri),
        Preview: ($printer_menu + " preview-discoverable " + ($display_name | @sh) + " " + ($uri | @sh)),
        PreviewType: "command"
      }')
    entries_json=$(jq -n --argjson arr "$entries_json" --argjson entry "$entry" '$arr + [$entry]')
  done

  printf "%s\n" "$entries_json"
}

set_default_printer() {
  local name="$1"

  if ! cups_available; then
    printf "lpstat is not available\n" >&2
    exit 1
  fi

  lpoptions -d "$name"
  save_printer_defaults
  notify "Printer default updated" "Default printer: ${name}"
}

add_and_set_default_printer() {
  local slug="$1"
  local uri="$2"

  if ! cups_available; then
    printf "lpstat is not available\n" >&2
    exit 1
  fi

  lpadmin -p "$slug" -E -v "$uri"
  set_default_printer "$slug"
}

printer_defaults_snippet() {
  local default_printer
  default_printer=$(default_printer_name)

  printf '  keystone.desktop.printer.default = '
  if [[ -n "$default_printer" ]]; then
    printf '"%s";\n' "$default_printer"
  else
    printf 'null;\n'
  fi
}

save_printer_defaults() {
  printer_defaults_snippet | keystone-desktop-config write-desktop-state-section "printer defaults"
}

apply_config_defaults() {
  if ! cups_available; then
    return 0
  fi

  if [[ -n "${KEYSTONE_PRINTER_DEFAULT:-}" ]]; then
    lpoptions -d "$KEYSTONE_PRINTER_DEFAULT"
  fi
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-printer -p "Printers" >/dev/null 2>&1 &
}

preview_printer() {
  local name="$1"

  if ! cups_available; then
    printf "%s\n" "$(cups_unavailable_reason)"
    return 0
  fi

  local current_default=""
  current_default=$(default_printer_name)

  printf "Printer: %s\n\nCurrent default: %s\n\nSelecting this printer updates the live default and saves it into nixos-config.\n" \
    "$name" \
    "$(if [[ "$name" == "$current_default" ]]; then printf "yes"; else printf "no"; fi)"
}

preview_discoverable() {
  local display_name="$1"
  local uri="$2"

  printf "Discovered printer: %s\n\nURI: %s\n\nSelecting this will add it to CUPS and set it as the default printer.\n" \
    "$display_name" \
    "$uri"
}

summary() {
  if ! cups_available; then
    printf "Printers unavailable\n%s" "$(cups_unavailable_reason)"
    return 0
  fi

  local current_default=""
  current_default=$(default_printer_name)

  if [[ -n "$current_default" ]]; then
    printf "Default: %s\n" "$current_default"
  else
    printf "No default printer set\n"
  fi
}

dispatch() {
  local payload="${1:-}"
  local action="" name="" uri=""

  IFS=$'\t' read -r action name uri <<<"$payload"

  case "$action" in
    set-default)
      set_default_printer "$name"
      ;;
    add-and-default)
      add_and_set_default_printer "$name" "$uri"
      ;;
    blocked)
      notify "Printers unavailable" "$(cups_unavailable_reason)"
      ;;
    *)
      printf "Unknown dispatch action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  printers-json)
    shift
    printers_json "$@"
    ;;
  set-default)
    shift
    set_default_printer "$@"
    ;;
  add-and-default)
    shift
    add_and_set_default_printer "$@"
    ;;
  preview-printer)
    shift
    preview_printer "$@"
    ;;
  preview-discoverable)
    shift
    preview_discoverable "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  apply-config-defaults)
    shift
    apply_config_defaults "$@"
    ;;
  refresh-discoverable)
    shift
    refresh_discoverable_background
    ;;
  save-defaults)
    shift
    save_printer_defaults "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-printer-menu {open-menu|printers-json|set-default|add-and-default|preview-printer|preview-discoverable|summary|apply-config-defaults|refresh-discoverable|save-defaults|dispatch} ..." >&2
    exit 1
    ;;
esac
