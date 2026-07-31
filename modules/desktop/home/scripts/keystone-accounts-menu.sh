#!/usr/bin/env bash
# keystone-accounts-menu — Multi-account mail and calendar controller.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-accounts-menu"
CURRENT_ACCOUNT_FILE="${STATE_DIR}/current-account"
CURRENT_CALENDAR_FILE="${STATE_DIR}/current-calendar"
MAIL_QUERY_FILE="${STATE_DIR}/mail-query"
mkdir -p "$STATE_DIR"

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

shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

mail_cli_available() {
  command -v himalaya >/dev/null 2>&1
}

calendar_cli_available() {
  command -v calendula >/dev/null 2>&1
}

mail_metadata_json() {
  local file="${XDG_CONFIG_HOME:-$HOME/.config}/keystone/mail-accounts.json"
  if [[ -r "$file" ]]; then
    cat "$file"
  else
    printf '[]\n'
  fi
}

calendar_metadata_json() {
  local file="${XDG_CONFIG_HOME:-$HOME/.config}/keystone/calendar-accounts.json"
  if [[ -r "$file" ]]; then
    cat "$file"
  else
    printf '[]\n'
  fi
}

merged_accounts_json() {
  jq -n \
    --argjson mail "$(mail_metadata_json)" \
    --argjson calendar "$(calendar_metadata_json)" '
    (($mail // []) | map(. + {has_mail: true, has_calendar: false}))
    + (($calendar // []) | map(. + {has_mail: false, has_calendar: true}))
    | sort_by(.name)
    | group_by(.name)
    | map({
        name: .[0].name,
        displayName: ((map(.displayName // "") | map(select(. != "")) | .[0]) // .[0].name),
        email: ((map(.email // "") | map(select(. != "")) | .[0]) // ""),
        provider: ((map(.provider // "") | map(select(. != "")) | .[0]) // "custom"),
        default: (map(.default // false) | any),
        has_mail: (map(.has_mail // false) | any),
        has_calendar: (map(.has_calendar // false) | any)
      })
  '
}

blocked_entry_json() {
  local title="$1"
  local reason="$2"

  jq -n --arg title "$title" --arg reason "$reason" '
    [
      {
        Text: $title,
        Subtext: $reason,
        Value: ("blocked\t" + $title + "\t" + $reason),
        Preview: ("printf " + (($title + "\n\n" + $reason + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

set_current_account() {
  printf "%s\n" "$1" > "$CURRENT_ACCOUNT_FILE"
}

current_account() {
  if [[ -f "$CURRENT_ACCOUNT_FILE" ]]; then
    cat "$CURRENT_ACCOUNT_FILE"
  fi
}

set_current_calendar() {
  printf "%s\n" "$1" > "$CURRENT_CALENDAR_FILE"
}

current_calendar() {
  if [[ -f "$CURRENT_CALENDAR_FILE" ]]; then
    cat "$CURRENT_CALENDAR_FILE"
  fi
}

set_mail_query() {
  printf "%s\n" "$1" > "$MAIL_QUERY_FILE"
}

clear_mail_query() {
  rm -f "$MAIL_QUERY_FILE"
}

current_mail_query() {
  if [[ -f "$MAIL_QUERY_FILE" ]]; then
    cat "$MAIL_QUERY_FILE"
  fi
}

account_record_json() {
  local account_name="$1"
  merged_accounts_json | jq -c --arg account_name "$account_name" 'map(select(.name == $account_name)) | first'
}

summary() {
  local account_name="${1:-}"

  if [[ -z "$account_name" ]]; then
    local accounts
    accounts=$(merged_accounts_json)
    jq -nr --argjson accounts "$accounts" '
      if ($accounts | length) == 0 then
        "No accounts configured"
      else
        (
          ["Accounts", ""]
          + (
            $accounts
            | sort_by([(.default | not), .displayName, .name])
            | map(
                "- "
                + (.displayName // .name)
                + " ("
                + (
                    [
                      (if .has_mail then "mail" else empty end),
                      (if .has_calendar then "calendar" else empty end)
                    ]
                    | join(", ")
                  )
                + ")"
              )
          )
        )
        | join("\n")
      end
    '
    return 0
  fi

  local account
  account=$(account_record_json "$account_name")

  if [[ -z "$account" || "$account" == "null" ]]; then
    printf "Unknown account: %s\n" "$account_name"
    return 0
  fi

  jq -rn --argjson account "$account" '
    [
      ($account.displayName // $account.name),
      "",
      ("Name: " + ($account.name // "unknown")),
      ("Email: " + (($account.email // "") | if . == "" then "not set" else . end)),
      ("Provider: " + ($account.provider // "custom")),
      ("Mail: " + (if ($account.has_mail // false) then "configured" else "not configured" end)),
      ("Calendar: " + (if ($account.has_calendar // false) then "configured" else "not configured" end))
    ]
    | join("\n")
  '
}

accounts_json() {
  local accounts_json
  accounts_json=$(merged_accounts_json)

  if [[ "$accounts_json" == "[]" ]]; then
    blocked_entry_json "No accounts configured" "Configure keystone.terminal.mail.accounts or keystone.terminal.calendar.accounts to populate this menu."
    return 0
  fi

  local accounts_menu
  accounts_menu=$(keystone_cmd keystone-accounts-menu)

  jq -n --arg accounts_menu "$accounts_menu" --argjson accounts "$accounts_json" '
    $accounts
    | sort_by([(.default | not), .displayName, .name])
    | map({
        Text: (
          (if .default then "  " else "󰓨  " end)
          + (.displayName // .name)
        ),
        Subtext: (
          [
            (.email // .name),
            (if .has_mail then "mail" else null end),
            (if .has_calendar then "calendar" else null end)
          ]
          | map(select(. != null and . != ""))
          | join(" · ")
        ),
        Value: .name,
        SubMenu: "keystone-account-sections",
        Preview: ($accounts_menu + " summary " + (.name | @sh)),
        PreviewType: "command"
      })
  '
}

sections_json() {
  local account_name="$1"
  local account account_menu
  account=$(account_record_json "$account_name")
  account_menu=$(keystone_cmd keystone-accounts-menu)

  if [[ -z "$account" || "$account" == "null" ]]; then
    blocked_entry_json "Unknown account" "The selected account is not configured."
    return 0
  fi

  jq -n --arg account_name "$account_name" --arg account_menu "$account_menu" --argjson account "$account" '
    [
      (if ($account.has_mail // false) then
        {
          Text: "Recent inbox",
          Subtext: "Browse the latest inbox envelopes",
          Value: ("open-mailbox\t" + $account_name),
          Preview: ($account_menu + " summary " + ($account_name | @sh)),
          PreviewType: "command"
        }
      else empty end),
      (if ($account.has_mail // false) then
        {
          Text: "Search mail",
          Subtext: "Prompt for a mail query, then browse the results",
          Value: ("prompt-mail-search\t" + $account_name),
          Preview: ($account_menu + " preview-search"),
          PreviewType: "command"
        }
      else empty end),
      (if ($account.has_calendar // false) then
        {
          Text: "Calendars",
          Subtext: "Browse configured calendars and upcoming events",
          Value: ("open-calendars\t" + $account_name),
          Preview: ($account_menu + " preview-calendars " + ($account_name | @sh)),
          PreviewType: "command"
        }
      else empty end)
    ]
    | if length == 0 then
        [
          {
            Text: "No account actions",
            Subtext: "This account has no configured mail or calendar services",
            Value: ("blocked\t" + $account_name + "\tNo account actions available")
          }
        ]
      else .
      end
  '
}

mailbox_raw_json() {
  local account_name="$1"
  local query="${2:-}"
  local query_words=()

  if ! mail_cli_available; then
    printf '[]\n'
    return 0
  fi

  if [[ -n "$query" ]]; then
    read -r -a query_words <<<"$query"
  fi

  himalaya envelope list -a "$account_name" -o json -s 25 "${query_words[@]}"
}

mailbox_json() {
  local account_name query accounts_menu mailbox_data
  account_name=$(current_account)
  query=$(current_mail_query)
  accounts_menu=$(keystone_cmd keystone-accounts-menu)

  if [[ -z "$account_name" ]]; then
    blocked_entry_json "No account selected" "Pick an account before opening mailbox entries."
    return 0
  fi

  if ! mail_cli_available; then
    blocked_entry_json "Mail unavailable" "himalaya is not available in PATH."
    return 0
  fi

  mailbox_data=$(mailbox_raw_json "$account_name" "$query")

  jq -n \
    --arg accounts_menu "$accounts_menu" \
    --arg account_name "$account_name" \
    --arg query "$query" \
    --argjson data "$mailbox_data" '
    $data
    | if length == 0 then
        [
          {
            Text: "No mail found",
            Subtext: (if $query == "" then "The inbox is empty" else "No messages matched the current query" end),
            Value: ("blocked\tMail\t" + (if $query == "" then "The inbox is empty" else "No messages matched the current query" end))
          }
        ]
      else
        map({
          Text: (.subject // "(no subject)"),
          Subtext: (
            [
              (.from.name // .from.addr // "unknown sender"),
              (.date // "unknown date"),
              (if ((.flags // []) | index("Seen")) == null then "unread" else "seen" end)
            ]
            | join(" · ")
          ),
          Value: ("open-message\t" + $account_name + "\t" + (.id | tostring)),
          Preview: ($accounts_menu + " preview-envelope " + ($account_name | @sh) + " " + ((.id | tostring) | @sh)),
          PreviewType: "command"
        })
      end
  '
}

preview_envelope() {
  local account_name="$1"
  local message_id="$2"

  if ! mail_cli_available; then
    printf "himalaya is not available in PATH.\n"
    return 0
  fi

  himalaya message read -a "$account_name" "$message_id" 2>/dev/null | sed -n '1,160p'
}

prompt_mail_search() {
  local account_name="$1"
  local query=""

  walker -q >/dev/null 2>&1 || true
  query=$(
    printf '\n' \
      | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "Mail search..." 2>/dev/null \
      | tr -d '\r'
  ) || true

  if [[ "$query" == "CNCLD" ]]; then
    return 0
  fi

  set_current_account "$account_name"
  set_mail_query "$query"
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-account-mailbox -p "Mail" >/dev/null 2>&1 &
}

open_mailbox_menu() {
  local account_name="$1"
  set_current_account "$account_name"
  clear_mail_query
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-account-mailbox -p "Mail" >/dev/null 2>&1 &
}

calendars_raw_json() {
  local account_name="$1"

  if ! calendar_cli_available; then
    printf '[]\n'
    return 0
  fi

  calendula calendars list -a "$account_name" --json
}

events_raw_json() {
  local account_name="$1"
  local calendar_id="$2"

  if ! calendar_cli_available; then
    printf '[]\n'
    return 0
  fi

  calendula events list -a "$account_name" --json "$calendar_id"
}

preview_calendars() {
  local account_name="$1"

  if ! calendar_cli_available; then
    printf "calendula is not available in PATH.\n"
    return 0
  fi

  calendula calendars list -a "$account_name" --json \
    | jq -r '
        if length == 0 then
          "No calendars found"
        else
          (["Calendars", ""] + map("- " + (.display_name // .id))) | join("\n")
        end
      '
}

open_calendars_menu() {
  local account_name="$1"
  set_current_account "$account_name"
  rm -f "$CURRENT_CALENDAR_FILE"
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-account-calendar -p "Calendars" >/dev/null 2>&1 &
}

calendars_json() {
  local account_name calendar_data accounts_menu
  account_name=$(current_account)
  accounts_menu=$(keystone_cmd keystone-accounts-menu)

  if [[ -z "$account_name" ]]; then
    blocked_entry_json "No account selected" "Pick an account before opening calendars."
    return 0
  fi

  if ! calendar_cli_available; then
    blocked_entry_json "Calendar unavailable" "calendula is not available in PATH."
    return 0
  fi

  calendar_data=$(calendars_raw_json "$account_name")

  jq -n --arg accounts_menu "$accounts_menu" --arg account_name "$account_name" --argjson data "$calendar_data" '
    $data
    | if length == 0 then
        [
          {
            Text: "No calendars found",
            Subtext: "No CalDAV calendars were returned for this account",
            Value: ("blocked\tCalendars\tNo calendars were returned for this account")
          }
        ]
      else
        map({
          Text: (.display_name // .id),
          Subtext: (.description // .id),
          Value: ("open-events\t" + $account_name + "\t" + .id),
          Preview: ($accounts_menu + " preview-calendar " + ($account_name | @sh) + " " + (.id | @sh)),
          PreviewType: "command",
          SubMenu: "keystone-account-events"
        })
      end
  '
}

preview_calendar() {
  local account_name="$1"
  local calendar_id="$2"
  local calendar_data events_data

  if ! calendar_cli_available; then
    printf "calendula is not available in PATH.\n"
    return 0
  fi

  calendar_data=$(calendars_raw_json "$account_name")
  events_data=$(events_raw_json "$account_name" "$calendar_id")

  jq -nr \
    --arg calendar_id "$calendar_id" \
    --argjson calendars "$calendar_data" \
    --argjson events "$events_data" '
    ([$calendars[] | select(.id == $calendar_id)] | first) as $calendar
    | [
        ($calendar.display_name // $calendar_id),
        "",
        "Upcoming events:",
        (
          if ($events | length) == 0 then
            "- none"
          else
            ($events
              | map("- " + (.summary // .title // .uid // (.id // "event" | tostring)))
              | .[0:10]
              | join("\n"))
          end
        )
      ]
    | join("\n")
  '
}

open_events_menu() {
  local account_name="$1"
  local calendar_id="$2"
  set_current_account "$account_name"
  set_current_calendar "$calendar_id"
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-account-events -p "Events" >/dev/null 2>&1 &
}

events_json() {
  local account_name calendar_id event_data
  account_name=$(current_account)
  calendar_id=$(current_calendar)

  if [[ -z "$account_name" || -z "$calendar_id" ]]; then
    blocked_entry_json "No calendar selected" "Pick a calendar before opening upcoming events."
    return 0
  fi

  if ! calendar_cli_available; then
    blocked_entry_json "Calendar unavailable" "calendula is not available in PATH."
    return 0
  fi

  event_data=$(events_raw_json "$account_name" "$calendar_id")

  jq -n --argjson data "$event_data" '
    $data
    | if length == 0 then
        [
          {
            Text: "No upcoming events",
            Subtext: "This calendar has no visible upcoming events",
            Value: ("blocked\tEvents\tNo upcoming events were returned")
          }
        ]
      else
        map({
          Text: (.summary // .title // .uid // ((.id // "event") | tostring)),
          Subtext: (
            [
              (.start // .date // .dtstart // ""),
              (.end // .dtend // "")
            ]
            | map(tostring)
            | map(select(. != ""))
            | join(" · ")
          ),
          Value: ("blocked\tEvent\tDesktop event opening is not implemented yet"),
          Preview: ("printf " + ((. | tostring) | @sh)),
          PreviewType: "command"
        })
      end
  '
}

preview_search() {
  cat <<'EOF'
Search mail

Enter any Himalaya-supported query, for example:
- from drago@ncrmro.com
- subject status
- after 2026-03-01
- subject daily and from drago@ncrmro.com
EOF
}

open_message_terminal() {
  local account_name="$1"
  local message_id="$2"
  local himalaya_cmd shell_cmd ghostty_cmd
  himalaya_cmd="$(keystone_cmd himalaya)"
  ghostty_cmd="$(keystone_cmd ghostty)"
  printf -v shell_cmd '%q message read -a %q %q | less -R' "$himalaya_cmd" "$account_name" "$message_id"
  detach "$ghostty_cmd" -e bash -lc "$shell_cmd"
}

dispatch() {
  local payload="${1:-}"
  local action="" arg1="" arg2=""

  IFS=$'\t' read -r action arg1 arg2 <<<"$payload"

  case "$action" in
    open-mailbox)
      open_mailbox_menu "$arg1"
      ;;
    prompt-mail-search)
      prompt_mail_search "$arg1"
      ;;
    open-calendars)
      open_calendars_menu "$arg1"
      ;;
    open-events)
      open_events_menu "$arg1" "$arg2"
      ;;
    open-message)
      open_message_terminal "$arg1" "$arg2"
      ;;
    blocked)
      notify "$arg1" "$arg2"
      ;;
    *)
      printf "Unknown accounts action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-accounts -p "Accounts" >/dev/null 2>&1 &
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  accounts-json)
    shift
    accounts_json "$@"
    ;;
  sections-json)
    shift
    sections_json "$@"
    ;;
  mailbox-json)
    shift
    mailbox_json "$@"
    ;;
  calendars-json)
    shift
    calendars_json "$@"
    ;;
  events-json)
    shift
    events_json "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  preview-envelope)
    shift
    preview_envelope "$@"
    ;;
  preview-calendars)
    shift
    preview_calendars "$@"
    ;;
  preview-calendar)
    shift
    preview_calendar "$@"
    ;;
  preview-search)
    shift
    preview_search "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-accounts-menu {open-menu|accounts-json|sections-json|mailbox-json|calendars-json|events-json|summary|preview-envelope|preview-calendars|preview-calendar|preview-search|dispatch} ..." >&2
    exit 1
    ;;
esac
