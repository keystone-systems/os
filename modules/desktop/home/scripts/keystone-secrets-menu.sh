#!/usr/bin/env bash
# keystone-secrets-menu — Walker/Elephant controller for agenix secret workflows.

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

identity_file_path() {
  local path="${HOME}/.age/yubikey-identity.txt"
  if [[ -f "$path" ]]; then
    printf "%s\n" "$path"
  fi
}

yubikey_status() {
  local identity_file=""
  identity_file="$(identity_file_path || true)"

  if [[ -z "$identity_file" ]]; then
    printf "no managed YubiKey identity file\n"
    return 0
  fi

  if ! command -v ykman >/dev/null 2>&1; then
    printf "identity file present, ykman unavailable\n"
    return 0
  fi

  local serials=""
  serials="$(ykman list --serials 2>/dev/null || true)"
  if [[ -z "$serials" ]]; then
    printf "identity file present, no YubiKey detected\n"
    return 0
  fi

  printf "identity file present, YubiKey detected: %s\n" "$(printf "%s" "$serials" | tr '\n' ',' | sed 's/,$//')"
}

current_config_repo() {
  # Authoritative source: pointer file written at NixOS activation time.
  # KEYSTONE_SYSTEM_FLAKE_POINTER_FILE may be set in test environments.
  local _pointer_file="${KEYSTONE_SYSTEM_FLAKE_POINTER_FILE:-/run/current-system/keystone-system-flake}"
  if [[ -r "$_pointer_file" ]]; then
    local _path
    _path="$(tr -d '\n' < "$_pointer_file" 2>/dev/null || true)"
    if [[ -n "$_path" && -d "$_path" ]]; then
      printf "%s\n" "$_path"
      return 0
    fi
  fi

  return 1
}

secrets_repo_path() {
  local config_repo=""
  config_repo="$(current_config_repo || true)"

  if [[ -n "$config_repo" && -d "$config_repo/agenix-secrets" ]]; then
    readlink -f "$config_repo/agenix-secrets"
    return 0
  fi

  if [[ -d "$HOME/.keystone/repos/ncrmro/agenix-secrets" ]]; then
    printf "%s\n" "$HOME/.keystone/repos/ncrmro/agenix-secrets"
    return 0
  fi

  return 1
}

require_secrets_repo() {
  local repo=""
  repo="$(secrets_repo_path || true)"
  if [[ -z "$repo" || ! -d "$repo" ]]; then
    printf "Managed agenix-secrets checkout not found.\n" >&2
    exit 1
  fi

  printf "%s\n" "$repo"
}

blocked_entry_json() {
  local title="$1"
  local message="$2"

  jq -n --arg title "$title" --arg message "$message" '
    [
      {
        Text: $title,
        Subtext: $message,
        Value: ("blocked\t" + $title + "\t" + $message),
        Icon: "dialog-warning-symbolic",
        Preview: ("printf " + (($title + "\n\n" + $message + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
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

declare -a CONFIG_USERNAMES=()
declare -a CONFIG_HOSTNAMES=()
CONFIG_CLASSIFIERS_READY=0

load_config_classifiers() {
  [[ "$CONFIG_CLASSIFIERS_READY" -eq 0 ]] || return 0

  local config_repo=""
  config_repo="$(current_config_repo || true)"
  if [[ -n "$config_repo" && -d "$config_repo/home-manager" ]]; then
    mapfile -t CONFIG_USERNAMES < <(
      find "$config_repo/home-manager" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
        | rg -v '^(common|keys)$' \
        | sort -u
    )
  fi

  if [[ -n "$config_repo" && -d "$config_repo/hosts" ]]; then
    mapfile -t CONFIG_HOSTNAMES < <(
      find "$config_repo/hosts" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
        | rg -v '^common$' \
        | sort -u
    )
  fi

  CONFIG_CLASSIFIERS_READY=1
}

classify_secret() {
  local relpath="$1"
  local name="${relpath##*/}"
  name="${name%.age}"
  local username=""
  local hostname=""

  load_config_classifiers

  if [[ "$name" == custom-* ]]; then
    printf "custom\n"
    return 0
  fi

  for username in "${CONFIG_USERNAMES[@]}"; do
    [[ -n "$username" ]] || continue
    if [[ "$name" == "${username}-"* ]]; then
      printf "user-home\n"
      return 0
    fi
  done

  for hostname in "${CONFIG_HOSTNAMES[@]}"; do
    [[ -n "$hostname" ]] || continue
    if [[ "$name" == "${hostname}-"* ]]; then
      printf "os-level\n"
      return 0
    fi
  done

  printf "service\n"
}

category_label() {
  case "$1" in
    os-level) printf "OS-level" ;;
    service) printf "Service" ;;
    user-home) printf "User-home" ;;
    custom) printf "Custom" ;;
    *) printf "%s" "$1" ;;
  esac
}

category_description() {
  case "$1" in
    os-level) printf "Host and operating-system scoped secrets" ;;
    service) printf "Service-owned secrets consumed by system services" ;;
    user-home) printf "Home Manager user secrets shared across hosts" ;;
    custom) printf "Ad hoc secrets outside the standard prefixes" ;;
    *) printf "Unknown secret category" ;;
  esac
}

secret_relpaths() {
  local repo="$1"

  if [[ ! -d "$repo/secrets" ]]; then
    return 0
  fi

  find "$repo/secrets" -mindepth 1 -maxdepth 1 -type f -name '*.age' -printf 'secrets/%f\n' | sort
}

can_decrypt_secret() {
  local repo="$1"
  local relpath="$2"
  local identity_file=""
  identity_file="$(identity_file_path || true)"

  if [[ -n "$identity_file" ]]; then
    agenix -d -i "$identity_file" "$repo/$relpath" >/dev/null 2>&1
  else
    agenix -d "$repo/$relpath" >/dev/null 2>&1
  fi
}

secret_recipients_line() {
  local repo="$1"
  local relpath="$2"
  local line=""

  line="$(rg -n -F "\"${relpath}\"" "$repo/secrets.nix" 2>/dev/null | head -n1 || true)"
  printf "%s\n" "$line"
}

secret_line_number() {
  local repo="$1"
  local relpath="$2"
  local line=""
  line="$(secret_recipients_line "$repo" "$relpath")"
  if [[ -n "$line" ]]; then
    printf "%s\n" "${line%%:*}"
  fi
}

summary() {
  local repo=""
  repo="$(secrets_repo_path || true)"

  if [[ -z "$repo" || ! -d "$repo" ]]; then
    printf "Secrets\n\nManaged agenix-secrets checkout not found.\n"
    return 0
  fi

  local total=0 os_count=0 service_count=0 user_count=0 custom_count=0 relpath="" category=""
  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    total=$((total + 1))
    category="$(classify_secret "$relpath")"
    case "$category" in
      os-level) os_count=$((os_count + 1)) ;;
      service) service_count=$((service_count + 1)) ;;
      user-home) user_count=$((user_count + 1)) ;;
      custom) custom_count=$((custom_count + 1)) ;;
    esac
  done < <(secret_relpaths "$repo")

  printf "Secrets\n\n"
  printf "Repo: %s\n" "$repo"
  printf "YubiKey: %s\n" "$(yubikey_status)"
  printf "Total secrets: %s\n" "$total"
  printf "OS-level: %s\n" "$os_count"
  printf "Service: %s\n" "$service_count"
  printf "User-home: %s\n" "$user_count"
  printf "Custom: %s\n" "$custom_count"
}

categories_json() {
  local repo=""
  repo="$(secrets_repo_path || true)"

  if [[ -z "$repo" || ! -d "$repo" ]]; then
    blocked_entry_json "No secrets repo" "Managed agenix-secrets checkout not found."
    return 0
  fi

  local os_count=0 service_count=0 user_count=0 custom_count=0 relpath="" category=""
  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    category="$(classify_secret "$relpath")"
    case "$category" in
      os-level) os_count=$((os_count + 1)) ;;
      service) service_count=$((service_count + 1)) ;;
      user-home) user_count=$((user_count + 1)) ;;
      custom) custom_count=$((custom_count + 1)) ;;
    esac
  done < <(secret_relpaths "$repo")

  jq -n \
    --arg secrets_menu "$(keystone_cmd keystone-secrets-menu)" \
    --argjson os_count "$os_count" \
    --argjson service_count "$service_count" \
    --argjson user_count "$user_count" \
    --argjson custom_count "$custom_count" '
    [
      {
        Text: "OS-level",
        Subtext: ("Host and operating-system scoped secrets · " + ($os_count | tostring)),
        Value: "os-level",
        SubMenu: "keystone-secret-list",
        Preview: ($secrets_menu + " preview-category os-level"),
        PreviewType: "command",
        Icon: "computer-symbolic"
      },
      {
        Text: "Service",
        Subtext: ("Service-owned secrets · " + ($service_count | tostring)),
        Value: "service",
        SubMenu: "keystone-secret-list",
        Preview: ($secrets_menu + " preview-category service"),
        PreviewType: "command",
        Icon: "applications-system-symbolic"
      },
      {
        Text: "User-home",
        Subtext: ("Home Manager user secrets · " + ($user_count | tostring)),
        Value: "user-home",
        SubMenu: "keystone-secret-list",
        Preview: ($secrets_menu + " preview-category user-home"),
        PreviewType: "command",
        Icon: "user-home-symbolic"
      },
      {
        Text: "Custom",
        Subtext: ("Ad hoc secrets · " + ($custom_count | tostring)),
        Value: "custom",
        SubMenu: "keystone-secret-list",
        Preview: ($secrets_menu + " preview-category custom"),
        PreviewType: "command",
        Icon: "document-properties-symbolic"
      }
    ]
  '
}

preview_category() {
  local category="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local count=0 relpath=""

  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    if [[ "$(classify_secret "$relpath")" == "$category" ]]; then
      count=$((count + 1))
    fi
  done < <(secret_relpaths "$repo")

  printf "%s secrets\n\n%s\n\nCount: %s\n" \
    "$(category_label "$category")" \
    "$(category_description "$category")" \
    "$count"
  printf "YubiKey: %s\n" "$(yubikey_status)"
}

secrets_json() {
  local category="$1"
  local repo=""
  repo="$(require_secrets_repo)"

  local rows=""
  local relpath="" name="" decryptable="" line_no=""

  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    if [[ "$(classify_secret "$relpath")" != "$category" ]]; then
      continue
    fi

    name="${relpath##*/}"
    name="${name%.age}"
    decryptable="no"
    if can_decrypt_secret "$repo" "$relpath"; then
      decryptable="yes"
    fi
    line_no="$(secret_line_number "$repo" "$relpath")"

    rows+="$(
      jq -cn \
        --arg name "$name" \
        --arg relpath "$relpath" \
        --arg decryptable "$decryptable" \
        --arg line_no "${line_no:-unknown}" \
        '{
          Text: $name,
          Subtext: ("decryptable: " + $decryptable + " · " + $relpath + " · secrets.nix:" + $line_no),
          Value: $relpath,
          SubMenu: "keystone-secret-actions",
          Preview: ("keystone-secrets-menu preview-secret " + ($relpath | @sh)),
          PreviewType: "command",
          Icon: "dialog-password-symbolic"
        }'
    )"$'\n'
  done < <(secret_relpaths "$repo")

  if [[ -z "$rows" ]]; then
    blocked_entry_json "No secrets found" "No secrets matched the selected category."
    return 0
  fi

  printf "%s" "$rows" | jq -s '.'
}

preview_secret() {
  local relpath="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local category decryptable recipients_line

  category="$(classify_secret "$relpath")"
  if can_decrypt_secret "$repo" "$relpath"; then
    decryptable="yes"
  else
    decryptable="no"
  fi
  recipients_line="$(secret_recipients_line "$repo" "$relpath")"

  printf "%s\n\n" "${relpath##*/}"
  printf "Category: %s\n" "$(category_label "$category")"
  printf "Decryptable: %s\n" "$decryptable"
  printf "YubiKey: %s\n" "$(yubikey_status)"
  printf "Path: %s\n" "$repo/$relpath"
  if [[ -n "$recipients_line" ]]; then
    printf "\nRecipients entry:\n%s\n" "$recipients_line"
  fi
}

actions_json() {
  local category="$1"
  local relpath="$2"
  local repo=""
  repo="$(require_secrets_repo)"

  if [[ ! -f "$repo/$relpath" ]]; then
    blocked_entry_json "Missing secret" "The selected secret file was not found."
    return 0
  fi

  local name="${relpath##*/}"
  name="${name%.age}"
  local line_no decryptable="false"
  line_no="$(secret_line_number "$repo" "$relpath")"
  if can_decrypt_secret "$repo" "$relpath"; then
    decryptable="true"
  fi

  jq -n \
    --arg relpath "$relpath" \
    --arg name "$name" \
    --arg category_label "$(category_label "$category")" \
    --arg line_no "${line_no:-unknown}" \
    --arg decryptable "$decryptable" '
    [
      (if $decryptable == "true" then
        {
          Text: "View value",
        Subtext: "Open a dedicated inspection terminal with YubiKey-aware agenix",
          Value: ("view-value\t" + $relpath),
          Icon: "document-preview-symbolic"
        }
      else
        {
          Text: "View value unavailable",
          Subtext: "Current user cannot decrypt this secret",
          Value: ("blocked\tView value unavailable\tCurrent user cannot decrypt this secret."),
          Icon: "dialog-warning-symbolic"
        }
      end),
      (if $decryptable == "true" then
        {
          Text: "Edit value",
          Subtext: "Run agenix -e for this secret with YubiKey-aware identity selection",
          Value: ("edit-value\t" + $relpath),
          Icon: "document-edit-symbolic"
        }
      else
        {
          Text: "Edit value unavailable",
          Subtext: "Current user cannot decrypt this secret",
          Value: ("blocked\tEdit value unavailable\tCurrent user cannot decrypt this secret."),
          Icon: "dialog-warning-symbolic"
        }
      end),
      {
        Text: "Edit recipients and rekey",
        Subtext: ("Open secrets.nix at line " + $line_no + ", then rekey if changed"),
        Value: ("edit-recipients\t" + $relpath),
        Icon: "system-run-symbolic"
      },
      {
        Text: "Rekey now",
        Subtext: "Run hwrekey when available, otherwise agenix -r with YubiKey identity",
        Value: ("rekey\t" + $relpath),
        Icon: "view-refresh-symbolic"
      },
      {
        Text: "Reveal in checkout",
        Subtext: ("Show " + $category_label + " metadata in a terminal"),
        Value: ("show-metadata\t" + $relpath),
        Icon: "text-x-script-symbolic"
      }
    ]
  '
}

view_value() {
  local relpath="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local command_literal=""
  local identity_file=""
  identity_file="$(identity_file_path || true)"

  if [[ -n "$identity_file" ]]; then
    command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && agenix -d -i $(printf '%q' "$identity_file") $(printf '%q' "$relpath") | less -R")
  else
    command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && agenix -d $(printf '%q' "$relpath") | less -R")
  fi
  launch_terminal_command "keystone-secret-view" "$command_literal"
}

edit_value() {
  local relpath="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local command_literal=""
  local identity_file=""
  identity_file="$(identity_file_path || true)"

  if [[ -n "$identity_file" ]]; then
    command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && agenix -e $(printf '%q' "$relpath") -i $(printf '%q' "$identity_file")")
  else
    command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && agenix -e $(printf '%q' "$relpath")")
  fi
  launch_terminal_command "keystone-secret-edit" "$command_literal"
}

edit_recipients_and_rekey() {
  local relpath="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local line_no=""
  line_no="$(secret_line_number "$repo" "$relpath")"
  local shell_cmd=""
  local message="rekey: update ${relpath##*/} recipients"
  local identity_file=""
  identity_file="$(identity_file_path || true)"

  printf -v shell_cmd '%s' "cd $(printf '%q' "$repo")
before_hash=\$(sha256sum secrets.nix | cut -d' ' -f1)
if command -v hx >/dev/null 2>&1; then
  hx +${line_no:-1} secrets.nix
else
  \${EDITOR:-vi} secrets.nix
fi
after_hash=\$(sha256sum secrets.nix | cut -d' ' -f1)
if [[ \"\$before_hash\" != \"\$after_hash\" ]]; then
  if command -v hwrekey >/dev/null 2>&1; then
    hwrekey -m $(printf '%q' "$message")
  else
    if [[ -n $(printf '%q' "$identity_file") && -f $(printf '%q' "$identity_file") ]]; then
      agenix -r -i $(printf '%q' "$identity_file")
    else
      agenix -r
    fi
  fi
else
  echo 'No recipient changes detected in secrets.nix.'
fi"

  launch_terminal_command "keystone-secret-recipients" "$(terminal_command_literal bash -lc "$shell_cmd")"
}

rekey_now() {
  local relpath="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local message="rekey: refresh ${relpath##*/}"
  local command_literal=""
  local identity_file=""
  identity_file="$(identity_file_path || true)"

  if [[ -n "$identity_file" ]]; then
    command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && if command -v hwrekey >/dev/null 2>&1; then hwrekey -m $(printf '%q' "$message"); else agenix -r -i $(printf '%q' "$identity_file"); fi")
  else
    command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && if command -v hwrekey >/dev/null 2>&1; then hwrekey -m $(printf '%q' "$message"); else agenix -r; fi")
  fi
  launch_terminal_command "keystone-secret-rekey" "$command_literal"
}

show_metadata() {
  local relpath="$1"
  local repo=""
  repo="$(require_secrets_repo)"
  local line_no=""
  line_no="$(secret_line_number "$repo" "$relpath")"
  local command_literal=""

  command_literal=$(terminal_command_literal bash -lc "cd $(printf '%q' "$repo") && printf 'Path: %s\n\n' $(printf '%q' "$relpath") && sed -n '$(( ${line_no:-1} > 2 ? ${line_no:-1} - 2 : 1 )),\$(( ${line_no:-1} + 2 ))p' secrets.nix | less -R")
  launch_terminal_command "keystone-secret-metadata" "$command_literal"
}

dispatch() {
  local payload="${1:-}"
  local action="" arg1="" arg2=""

  IFS=$'\t' read -r action arg1 arg2 <<<"$payload"

  case "$action" in
    view-value)
      view_value "$arg1"
      ;;
    edit-value)
      edit_value "$arg1"
      ;;
    edit-recipients)
      edit_recipients_and_rekey "$arg1"
      ;;
    rekey)
      rekey_now "$arg1"
      ;;
    show-metadata)
      show_metadata "$arg1"
      ;;
    blocked)
      notify "$arg1" "$arg2"
      ;;
    *)
      printf "Unknown secrets action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-secrets -p "Secrets" >/dev/null 2>&1 &
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  categories-json)
    shift
    categories_json "$@"
    ;;
  secrets-json)
    shift
    secrets_json "$@"
    ;;
  actions-json)
    shift
    actions_json "$@"
    ;;
  preview-category)
    shift
    preview_category "$@"
    ;;
  preview-secret)
    shift
    preview_secret "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-secrets-menu {open-menu|categories-json|secrets-json|actions-json|preview-category|preview-secret|summary|dispatch} ..." >&2
    exit 1
    ;;
esac
