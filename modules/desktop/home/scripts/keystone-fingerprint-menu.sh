#!/usr/bin/env bash
# keystone-fingerprint-menu — Fingerprint enrollment and management controller.

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

fprintd_status_json() {
  if ! command -v fprintd-list >/dev/null 2>&1; then
    printf '{"available":false,"enrolled_fingers":[],"summary":"fprintd-list unavailable"}\n'
    return 0
  fi

  local user output enrolled_fingers
  user="${USER:-$(id -un)}"
  if ! output=$(fprintd-list "$user" 2>&1); then
    jq -n --arg output "$output" '
      {
        available: false,
        enrolled_fingers: [],
        summary: "fprintd-list failed",
        detail: $output
      }
    '
    return 0
  fi
  enrolled_fingers=$(printf '%s\n' "$output" | grep -oP '^\s+-\s+\K\S+' || true)

  local fingers_json
  if [[ -z "$enrolled_fingers" ]]; then
    fingers_json="[]"
  else
    fingers_json=$(printf '%s\n' "$enrolled_fingers" | jq -R . | jq -s .)
  fi

  jq -n --argjson fingers "$fingers_json" --arg output "$output" '
    {
      available: true,
      enrolled_fingers: $fingers,
      summary: (if ($fingers | length) > 0 then (($fingers | length | tostring) + " finger(s) enrolled") else "No fingers enrolled" end),
      detail: $output
    }
  '
}

summary() {
  local status
  status=$(fprintd_status_json)

  jq -nr --argjson status "$status" '
    [
      "Fingerprint",
      "",
      ("Status: " + (if $status.available then "fprintd available" else "fprintd unavailable" end)),
      ("Enrolled: " + $status.summary),
      (if ($status.enrolled_fingers | length) > 0 then
        "Fingers: " + ($status.enrolled_fingers | join(", "))
      else
        "No fingers enrolled — use Enroll to add one"
      end)
    ]
    | join("\n")
  '
}

entries_json() {
  local fingerprint_menu status
  fingerprint_menu=$(keystone_cmd keystone-fingerprint-menu)
  status=$(fprintd_status_json)

  jq -n \
    --arg fingerprint_menu "$fingerprint_menu" \
    --argjson status "$status" '
    [
      (if $status.available then
        {
          Text: "Status",
          Subtext: $status.summary,
          Value: ("blocked\tFingerprint status\t" + $status.summary),
          Preview: ($fingerprint_menu + " preview status"),
          PreviewType: "command"
        }
      else
        {
          Text: "Status",
          Subtext: "fprintd is not available",
          Value: ("blocked\tFingerprint\tfprintd-list is not available in PATH."),
          Preview: ($fingerprint_menu + " preview status"),
          PreviewType: "command"
        }
      end),
      {
        Text: "Enroll finger",
        Subtext: "Start an interactive fingerprint enrollment terminal",
        Value: "enroll",
        Preview: ($fingerprint_menu + " preview enroll"),
        PreviewType: "command"
      },
      {
        Text: "Verify finger",
        Subtext: "Test an enrolled fingerprint",
        Value: "verify",
        Preview: ($fingerprint_menu + " preview verify"),
        PreviewType: "command"
      },
      {
        Text: "Delete fingerprints",
        Subtext: ("Remove all enrolled fingerprints for " + env.USER),
        Value: "delete",
        Preview: ($fingerprint_menu + " preview delete"),
        PreviewType: "command"
      }
    ]
  '
}

preview() {
  local topic="${1:-summary}"

  case "$topic" in
    status)
      summary
      ;;
    enroll)
      cat <<'EOF'
Enroll finger

This action opens a detached terminal and runs:
  fprintd-enroll

You will be prompted to swipe your finger several times on the
fingerprint reader. Once enrolled, the fingerprint can be used
for hyprlock screen unlock and other PAM-authenticated actions.
EOF
      ;;
    verify)
      cat <<'EOF'
Verify finger

This action opens a detached terminal and runs:
  fprintd-verify

Swipe an enrolled finger on the reader to confirm it is
recognized correctly.
EOF
      ;;
    delete)
      cat <<EOF
Delete fingerprints

This action opens a detached terminal and runs:
  fprintd-delete $USER

All enrolled fingerprints for the current user will be removed.
You can re-enroll afterwards using the Enroll action.
EOF
      ;;
    *)
      summary
      ;;
  esac
}

dispatch() {
  local payload="${1:-}"
  local action="" title="" message=""

  IFS=$'\t' read -r action title message <<<"$payload"

  case "$action" in
    enroll)
      local ghostty_cmd
      ghostty_cmd="$(keystone_cmd ghostty)"
      detach "$ghostty_cmd" -e bash -lc 'printf "Starting fingerprint enrollment...\n\n"; exec fprintd-enroll'
      ;;
    verify)
      local ghostty_cmd
      ghostty_cmd="$(keystone_cmd ghostty)"
      detach "$ghostty_cmd" -e bash -lc 'printf "Starting fingerprint verification...\n\n"; exec fprintd-verify'
      ;;
    delete)
      local ghostty_cmd username delete_cmd
      ghostty_cmd="$(keystone_cmd ghostty)"
      username="$(id -un)"
      printf -v delete_cmd 'printf "%s\n\n" %q; exec fprintd-delete -- %q' \
        "Deleting enrolled fingerprints for ${username}..." "$username"
      detach "$ghostty_cmd" -e bash -lc "$delete_cmd"
      ;;
    blocked)
      notify "$title" "$message"
      ;;
    *)
      printf "Unknown fingerprint action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-fingerprint -p "Fingerprint" >/dev/null 2>&1 &
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  entries-json)
    shift
    entries_json "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  preview)
    shift
    preview "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-fingerprint-menu {open-menu|entries-json|summary|preview|dispatch} ..." >&2
    exit 1
    ;;
esac
