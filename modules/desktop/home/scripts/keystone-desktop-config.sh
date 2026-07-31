#!/usr/bin/env bash
# keystone-desktop-config — Shared helpers for persisting desktop state into
# nixos-config. Packaged as a CLI with subcommands so other Walker menu
# scripts (each built via writeShellScriptBin into its own $out/bin) can
# reach these helpers without a sibling-path source.

set -euo pipefail

keystone_config_repo_root() {
  # Authoritative source: pointer file written at NixOS activation time.
  # KEYSTONE_SYSTEM_FLAKE_POINTER_FILE may be set in test environments.
  local _pointer_file="${KEYSTONE_SYSTEM_FLAKE_POINTER_FILE:-/run/current-system/keystone-system-flake}"
  if [[ -r "$_pointer_file" ]]; then
    local _path
    _path="$(tr -d '\n' < "$_pointer_file")"
    if [[ -n "$_path" && -d "$_path" ]]; then
      printf "%s\n" "$_path"
      return 0
    fi
  fi

  printf "Unable to locate system flake: %s not found or invalid.\n" "$_pointer_file" >&2
  return 1
}

keystone_home_manager_host_file() {
  if [[ -n "${KEYSTONE_HOME_MANAGER_HOST_FILE:-}" ]]; then
    printf "%s\n" "$KEYSTONE_HOME_MANAGER_HOST_FILE"
    return 0
  fi

  local repo_root user_name host_name candidate
  repo_root=$(keystone_config_repo_root)
  user_name="${KEYSTONE_CONFIG_USER:-$USER}"
  host_name="${KEYSTONE_CONFIG_HOST:-$(hostname)}"
  candidate="${repo_root}/home-manager/${user_name}/${host_name}.nix"

  if [[ ! -f "$candidate" ]]; then
    printf "Unable to locate host home-manager file: %s\n" "$candidate" >&2
    return 1
  fi

  printf "%s\n" "$candidate"
}

keystone_write_managed_section() {
  local target_file="$1"
  local top_label="$2"
  local section_name="$3"
  local section_body=""
  section_body=$(cat)

  KEYSTONE_SECTION_BODY="$section_body" python3 - "$target_file" "$top_label" "$section_name" <<'PYCODE'
import pathlib
import re
import sys
import os

target = pathlib.Path(sys.argv[1])
top_label = sys.argv[2]
section_name = sys.argv[3]
section_body = os.environ["KEYSTONE_SECTION_BODY"].rstrip("\n")

doc = target.read_text()
top_start = f"  # BEGIN keystone-managed {top_label}"
top_end = f"  # END keystone-managed {top_label}"
section_start = f"  # BEGIN keystone-managed {section_name}"
section_end = f"  # END keystone-managed {section_name}"
section_block = f"{section_start}\n{section_body}\n{section_end}\n"

top_re = re.compile(
    rf"{re.escape(top_start)}\n(?P<body>.*?){re.escape(top_end)}\n?",
    re.S,
)
section_re = re.compile(
    rf"{re.escape(section_start)}\n.*?{re.escape(section_end)}\n?",
    re.S,
)

match = top_re.search(doc)
if match:
    top_body = match.group("body")
    if section_re.search(top_body):
        top_body = section_re.sub(section_block, top_body)
    else:
        if top_body and not top_body.endswith("\n"):
            top_body += "\n"
        top_body += section_block
    doc = doc[: match.start("body")] + top_body + doc[match.end("body") :]
else:
    insert = f"{top_start}\n{section_block}{top_end}\n"
    closing_index = doc.rfind("}")
    if closing_index == -1:
        raise SystemExit(f"Could not find closing brace in {target}")
    doc = doc[:closing_index].rstrip() + "\n\n" + insert + doc[closing_index:]

target.write_text(doc)
PYCODE
}

keystone_write_desktop_state_section() {
  local section_name="$1"
  local target_file=""

  target_file=$(keystone_home_manager_host_file)
  keystone_write_managed_section "$target_file" "desktop state" "$section_name"
}

usage() {
  cat >&2 <<'USAGE'
Usage: keystone-desktop-config <subcommand> [args...]

Subcommands:
  config-repo-root
      Print the resolved nixos-config repo root.
  home-manager-host-file
      Print the path to the current host's home-manager .nix file.
  write-managed-section <target-file> <top-label> <section-name>
      Read section body from stdin; upsert it into <target-file>.
  write-desktop-state-section <section-name>
      Read section body from stdin; upsert into the current host's
      home-manager file under the "desktop state" top-label.
USAGE
  exit 2
}

main() {
  # CRITICAL: dispatch must fail loudly on unknown subcommands so upstream
  # callers surface typos instead of silently no-op'ing.
  local sub="${1:-}"
  if [[ -z "$sub" ]]; then
    usage
  fi
  shift

  case "$sub" in
    config-repo-root) keystone_config_repo_root "$@" ;;
    home-manager-host-file) keystone_home_manager_host_file "$@" ;;
    write-managed-section) keystone_write_managed_section "$@" ;;
    write-desktop-state-section) keystone_write_desktop_state_section "$@" ;;
    -h | --help | help) usage ;;
    *)
      printf "keystone-desktop-config: unknown subcommand: %s\n" "$sub" >&2
      usage
      ;;
  esac
}

main "$@"
