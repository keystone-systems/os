#!/usr/bin/env bash
# keystone-package-menu — Package search/install flow for the Mod+Escape menu.

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

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

entries_json() {
  jq -n '
    [
      {
        Text: "Search packages",
        Subtext: "Search the current system flake package set and choose an install target",
        Value: "search-and-install",
        Icon: "system-software-install-symbolic"
      }
    ]
  '
}

current_hostname() {
  uname -n
}

current_system() {
  nix eval --impure --raw --expr 'builtins.currentSystem'
}

keystone_dev_enabled() {
  local repo_root="$1"
  local host_key=""
  local value=""

  host_key=$(current_host_key)
  if [[ -z "$host_key" ]]; then
    printf "false\n"
    return 0
  fi

  value=$(nix eval "$repo_root#nixosConfigurations.${host_key}.config.keystone.development" --json 2>/dev/null || printf 'false')
  if [[ "$value" == "true" ]]; then
    printf "true\n"
  else
    printf "false\n"
  fi
}

current_nixpkgs_ref() {
  local repo_root="$1"

  nix flake metadata --json "$repo_root" | jq -r '
    . as $meta
    | ($meta.locks.nodes.root.inputs.nixpkgs) as $root_input
    | (
        if ($root_input | type) == "array" then
          $meta.locks.nodes[$root_input[0]].inputs[$root_input[1]]
        else
          $root_input
        end
      ) as $node_id
    | $meta.locks.nodes[$node_id].locked as $locked
    | if $locked.type == "github" then
        "github:\($locked.owner)/\($locked.repo)/\($locked.rev)"
      elif $locked.type == "path" then
        "path:\($locked.path)"
      else
        error("Unsupported nixpkgs lock type: \($locked.type)")
      end
  '
}

prompt_input() {
  local placeholder="$1"
  local value=""

  value=$(printf '\n' | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "$placeholder" 2>/dev/null | tr -d '\r') || true
  if [[ -z "$value" || "$value" == "CNCLD" ]]; then
    return 1
  fi

  printf "%s\n" "$value"
}

prompt_selection() {
  local placeholder="$1"
  local value=""

  value=$("$(keystone_cmd keystone-launch-walker)" --dmenu --placeholder "$placeholder" 2>/dev/null | tr -d '\r') || true
  if [[ -z "$value" || "$value" == "CNCLD" ]]; then
    return 1
  fi

  printf "%s\n" "$value"
}

escape_regex() {
  printf "%s" "$1" | sed -E 's/[][(){}.^$+*?|\\-]/\\&/g'
}

search_packages_json() {
  local nixpkgs_ref="$1"
  local system="$2"
  local query="$3"
  local escaped_query=""

  escaped_query=$(escape_regex "$query")
  nix search --json "${nixpkgs_ref}#legacyPackages.${system}" "$escaped_query" 2>/dev/null || printf '{}\n'
}

pick_package() {
  local nixpkgs_ref="$1"
  local system="$2"
  local query="$3"
  local choices=""
  local selected=""

  choices=$(
    search_packages_json "$nixpkgs_ref" "$system" "$query" \
      | jq -r --arg system "$system" '
          to_entries
          | map({
              attr: (.key | sub("^legacyPackages\\." + $system + "\\."; "")),
              pname: (.value.pname // (.key | split(".") | last)),
              version: (.value.version // ""),
              description: ((.value.description // "No description") | gsub("[\r\n\t]+"; " "))
            })
          | unique_by(.attr)
          | sort_by(.pname, .attr)
          | .[:80]
          | .[]
          | [
              (.pname + (if .version == "" then "" else " " + .version end)),
              .attr,
              .description
            ]
          | @tsv
        '
  )

  if [[ -z "$choices" ]]; then
    return 1
  fi

  selected=$(printf '%s\n' "$choices" | prompt_selection "Select package") || return 1
  printf "%s\n" "$selected"
}

pick_target() {
  local selected=""

  selected=$(
    cat <<'EOF' | prompt_selection "Install target"
System	system	Manage environment.systemPackages in the system flake
Home Manager	home-manager	Manage home.packages in the current user's config
Nix profile	nix-profile	Install for this user from the locked nixpkgs input
EOF
  ) || return 1

  printf "%s\n" "$selected"
}

host_registry_json() {
  local repo_root="$1"
  nix eval --json --file "${repo_root}/hosts.nix"
}

current_host_key() {
  local repo_root=""
  local hostname=""

  repo_root=$(keystone-desktop-config config-repo-root)
  hostname=$(current_hostname)

  host_registry_json "$repo_root" | jq -r --arg hostname "$hostname" '
    to_entries[]
    | select(.value.hostname == $hostname)
    | .key
  ' | head -n1
}

pick_system_host() {
  local repo_root="$1"
  local current_key="$2"
  local selected=""

  selected=$(
    host_registry_json "$repo_root" | jq -r --arg current_key "$current_key" '
      to_entries
      | sort_by(
          (if .key == $current_key then 0 else 1 end),
          .key
        )
      | .[]
      | [
          (
            if .key == $current_key then
              .value.hostname + " (current)"
            else
              .value.hostname
            end
          ),
          .key,
          (.value.sshTarget // "local-only"),
          "System install target"
        ]
      | @tsv
    ' | prompt_selection "System host"
  ) || return 1

  printf "%s\n" "$selected"
}

pick_home_manager_host() {
  local repo_root="$1"
  local current_hostname="$2"
  local selected=""
  local host_json=""

  host_json=$(host_registry_json "$repo_root")
  selected=$(
    find "${repo_root}/home-manager/${USER}" -maxdepth 1 -type f -name '*.nix' -printf '%f\n' 2>/dev/null \
      | sed 's/\.nix$//' \
      | while IFS= read -r host_name; do
          [[ -z "$host_name" || "$host_name" == "base" ]] && continue
          if printf '%s\n' "$host_json" | jq -e --arg host_name "$host_name" '
            to_entries[]
            | select(.value.hostname == $host_name)
          ' >/dev/null; then
            if [[ "$host_name" == "$current_hostname" ]]; then
              printf "%s\t%s\t%s\n" "${host_name} (current)" "$host_name" "Home Manager install target"
            else
              printf "%s\t%s\t%s\n" "$host_name" "$host_name" "Home Manager install target"
            fi
          fi
        done \
      | awk -F '\t' -v current="$current_hostname" '
          {
            rank = ($2 == current ? 0 : 1)
            print rank "\t" $0
          }
        ' \
      | sort \
      | cut -f2- \
      | prompt_selection "Home Manager host"
  ) || return 1

  printf "%s\n" "$selected"
}

resolve_system_host_file() {
  local repo_root="$1"
  local host_key="$2"
  local hostname=""
  local matches=()

  hostname=$(host_registry_json "$repo_root" | jq -r --arg host_key "$host_key" '.[$host_key].hostname // empty')
  if [[ -z "$hostname" ]]; then
    printf "Unable to resolve hostname for host key %s\n" "$host_key" >&2
    return 1
  fi

  mapfile -t matches < <(rg -l "networking\\.hostName\\s*=\\s*\"${hostname}\";" "${repo_root}/hosts" -g 'default.nix' 2>/dev/null || true)
  if [[ "${#matches[@]}" -ne 1 ]]; then
    printf "Unable to uniquely resolve system host file for %s\n" "$hostname" >&2
    return 1
  fi

  printf "%s\n" "${matches[0]}"
}

resolve_home_manager_host_file() {
  local repo_root="$1"
  local host_name="$2"
  local candidate="${repo_root}/home-manager/${USER}/${host_name}.nix"

  if [[ ! -f "$candidate" ]]; then
    printf "Unable to locate Home Manager file: %s\n" "$candidate" >&2
    return 1
  fi

  printf "%s\n" "$candidate"
}

write_package_install_block() {
  local target_file="$1"
  local target_kind="$2"
  local package_attr="$3"

  KEYSTONE_PACKAGE_ATTR="$package_attr" python3 - "$target_file" "$target_kind" <<'PYCODE'
import os
import pathlib
import re
import sys

target = pathlib.Path(sys.argv[1])
target_kind = sys.argv[2]
package_attr = os.environ["KEYSTONE_PACKAGE_ATTR"]

doc = target.read_text()

top_start = "  # BEGIN keystone-managed package installs"
top_end = "  # END keystone-managed package installs"
section_start = "  # BEGIN keystone-managed package entries"
section_end = "  # END keystone-managed package entries"

assign = "environment.systemPackages" if target_kind == "system" else "home.packages"

top_re = re.compile(
    rf"{re.escape(top_start)}\n(?P<body>.*?){re.escape(top_end)}\n?",
    re.S,
)
assign_re = re.compile(
    rf"{re.escape(assign)} = with pkgs; \[(?P<items>.*?)\];",
    re.S,
)

items = []
match = top_re.search(doc)
if match:
    body = match.group("body")
    assign_match = assign_re.search(body)
    if assign_match:
        for line in assign_match.group("items").splitlines():
            stripped = line.strip()
            if stripped:
                items.append(stripped)

items = sorted({*items, package_attr})

lines = [f"  {assign} = with pkgs; ["]
lines.extend(f"    {item}" for item in items)
lines.append("  ];")
section_block = f"{section_start}\n" + "\n".join(lines) + f"\n{section_end}\n"

if match:
    replacement = f"{top_start}\n{section_block}{top_end}\n"
    doc = doc[: match.start()] + replacement + doc[match.end():]
else:
    insert = f"{top_start}\n{section_block}{top_end}\n"
    closing_index = doc.rfind("}")
    if closing_index == -1:
        raise SystemExit(f"Could not find closing brace in {target}")
    doc = doc[:closing_index].rstrip() + "\n\n" + insert + doc[closing_index:]

target.write_text(doc)
PYCODE
}

terminal_command_literal() {
  local parts=()
  local arg=""

  for arg in "$@"; do
    parts+=("$(printf '%q' "$arg")")
  done

  printf '%s' "${parts[*]}"
}

launch_terminal_command() {
  local title="$1"
  local command_literal="$2"
  local shell_cmd=""

  shell_cmd="${command_literal}; status=\$?; printf '\\n'; if [[ \$status -eq 0 ]]; then echo 'Command finished successfully.'; else echo \"Command failed with status \$status.\"; fi; read -r -n 1 -s -p 'Press any key to close...'; exit \$status"
  detach "$(keystone_cmd ghostty)" --title "$title" -e bash -lc "$shell_cmd"
}

apply_install() {
  local repo_root="$1"
  local target_kind="$2"
  local target_host="$3"
  local nixpkgs_ref="$4"
  local package_attr="$5"
  local target_file=""
  local is_dev=""
  local command_literal=""

  is_dev=$(keystone_dev_enabled "$repo_root")

  case "$target_kind" in
    nix-profile)
      command_literal=$(terminal_command_literal nix profile install "${nixpkgs_ref}#${package_attr}")
      launch_terminal_command "keystone-package-install" "$command_literal"
      notify "Package install started" "Installing ${package_attr} into the user profile."
      ;;
    home-manager)
      if ! target_file=$(resolve_home_manager_host_file "$repo_root" "$target_host" 2>/dev/null); then
        notify "Install blocked" "Unable to locate the Home Manager file for ${target_host}."
        return 0
      fi
      write_package_install_block "$target_file" "home-manager" "$package_attr"
      notify "Config updated" "Added ${package_attr} to ${target_file}."
      if [[ "$is_dev" == "true" ]]; then
        command_literal=$(terminal_command_literal ks update --dev "$target_host")
      else
        command_literal=$(terminal_command_literal ks update --lock "$target_host")
      fi
      launch_terminal_command "keystone-package-install" "$command_literal"
      ;;
    system)
      if ! target_file=$(resolve_system_host_file "$repo_root" "$target_host" 2>/dev/null); then
        notify "Install blocked" "Unable to resolve a unique system host file for ${target_host}."
        return 0
      fi
      write_package_install_block "$target_file" "system" "$package_attr"
      notify "Config updated" "Added ${package_attr} to ${target_file}."
      if [[ "$is_dev" == "true" ]]; then
        notify "System package saved" "Development mode detected. Run ks update --lock ${target_host} to apply the system change."
      else
        command_literal=$(terminal_command_literal ks update --lock "$target_host")
        launch_terminal_command "keystone-package-install" "$command_literal"
      fi
      ;;
    *)
      printf "Unknown install target: %s\n" "$target_kind" >&2
      exit 1
      ;;
  esac
}

cmd_search_and_install() {
  local repo_root=""
  local nixpkgs_ref=""
  local system=""
  local query=""
  local package_choice=""
  local target_choice=""
  local host_choice=""
  local package_attr=""
  local target_kind=""
  local target_host=""
  local current_key=""
  local current_name=""

  if ! repo_root=$(keystone-desktop-config config-repo-root 2>/dev/null); then
    notify "Install unavailable" "Unable to locate the active system flake."
    return 0
  fi
  if ! nixpkgs_ref=$(current_nixpkgs_ref "$repo_root" 2>/dev/null); then
    notify "Install unavailable" "Unable to resolve the flake's locked nixpkgs input."
    return 0
  fi
  system=$(current_system)
  current_key=$(current_host_key || true)
  current_name=$(current_hostname)

  query=$(prompt_input "Search packages") || return 0
  if [[ "${#query}" -lt 2 ]]; then
    notify "Search too short" "Enter at least two characters to search packages."
    return 0
  fi

  package_choice=$(pick_package "$nixpkgs_ref" "$system" "$query") || {
    notify "No packages found" "No packages matched \"${query}\" in the current system flake."
    return 0
  }
  IFS=$'\t' read -r _ package_attr _ <<<"$package_choice"

  target_choice=$(pick_target) || return 0
  IFS=$'\t' read -r _ target_kind _ <<<"$target_choice"

  case "$target_kind" in
    system)
      host_choice=$(pick_system_host "$repo_root" "$current_key") || return 0
      IFS=$'\t' read -r _ target_host _ _ <<<"$host_choice"
      ;;
    home-manager)
      host_choice=$(pick_home_manager_host "$repo_root" "$current_name") || return 0
      IFS=$'\t' read -r _ target_host _ <<<"$host_choice"
      ;;
    nix-profile)
      target_host=""
      ;;
  esac

  apply_install "$repo_root" "$target_kind" "$target_host" "$nixpkgs_ref" "$package_attr"
}

dispatch() {
  local payload="${1:-}"

  case "$payload" in
    search-and-install)
      cmd_search_and_install
      ;;
    blocked | "")
      return 0
      ;;
    *)
      printf "Unknown package menu action: %s\n" "$payload" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  entries-json)
    entries_json
    ;;
  dispatch)
    shift
    dispatch "${1:-}"
    ;;
  *)
    echo "Usage: keystone-package-menu {entries-json|dispatch}" >&2
    exit 1
    ;;
esac
