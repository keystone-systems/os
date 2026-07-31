#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="@configFile@"
JQ="@jq@"

usage() {
  cat <<'EOF'
Usage: keystone-approve-exec [--validate] --reason <reason> -- <command> [args...]

Validate or execute a Keystone allowlisted privileged command.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

join_argv_json() {
  # shellcheck disable=SC2016
  # jq filter is intentionally single-quoted.
  #
  # CRITICAL: two jq argv quirks both bite this helper:
  #   1. The filter program MUST come before `--args`, otherwise jq treats
  #      the filter as just another positional, finds no filter, falls back
  #      to interpreting the first positional ("ks") as a filter, and dies
  #      with "jq: error: ks/0 is not defined".
  #   2. `--args` only consumes non-option-shaped tokens as positionals; any
  #      `--flag` after `--args` (e.g. `ks update --approve`,
  #      `keystone-enroll-fido2 --auto`) is parsed as a jq option unless a
  #      `--` separator immediately follows `--args`.
  # Both bites only manifest in non-tty contexts (e.g. ks-update.service
  # invoking `ks update --approve`); interactive callers historically went
  # through a tty path that bypassed this helper entirely.
  "$JQ" -cn '$ARGS.positional' --args -- "$@"
}

match_entry_json() {
  local requested_json="$1"

  # shellcheck disable=SC2016
  # jq program is intentionally single-quoted.
  "$JQ" -cn \
    --slurpfile config "$CONFIG_FILE" \
    --argjson requested "$requested_json" '
    def startswith_array($prefix; $value):
      ($prefix | length) <= ($value | length) and ($value[0:($prefix | length)] == $prefix);

    ($config[0].commands // [])
    | map(
        . + {
          argvLength: (.argv | length),
          exactMatch: (.match == "exact" and .argv == $requested),
          prefixMatch: (.match == "prefix" and startswith_array(.argv; $requested))
        }
      )
    | map(select(.exactMatch or .prefixMatch))
    | sort_by(.argvLength)
    | reverse
    | .[0] // empty
  '
}

VALIDATE_ONLY=false
REASON=""
REQUESTED_ARGV=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate)
      VALIDATE_ONLY=true
      shift
      ;;
    --reason)
      [[ $# -lt 2 ]] && die "--reason requires a value"
      REASON="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      REQUESTED_ARGV=("$@")
      break
      ;;
    *)
      die "unknown option '$1'"
      ;;
  esac
done

[[ -n "$REASON" ]] || die "missing --reason"
[[ -r "$CONFIG_FILE" ]] || die "approval config not found at $CONFIG_FILE"
[[ ${#REQUESTED_ARGV[@]} -gt 0 ]] || die "missing command to validate or execute"

REQUESTED_JSON="$(join_argv_json "${REQUESTED_ARGV[@]}")"
MATCHED_ENTRY="$(match_entry_json "$REQUESTED_JSON")"

[[ -n "$MATCHED_ENTRY" && "$MATCHED_ENTRY" != "null" ]] || {
  printf 'Rejected command:'
  printf ' %q' "${REQUESTED_ARGV[@]}"
  printf '\n' >&2
  die "command is not allowlisted"
}

if [[ "$VALIDATE_ONLY" == true ]]; then
  printf '%s\n' "$MATCHED_ENTRY"
  exit 0
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "keystone-approve-exec must run as root unless --validate is used"
fi

MATCHED_NAME="$("$JQ" -r '.name' <<<"$MATCHED_ENTRY")"
MATCHED_DISPLAY_NAME="$("$JQ" -r '.displayName' <<<"$MATCHED_ENTRY")"
MATCHED_REASON="$("$JQ" -r '.reason' <<<"$MATCHED_ENTRY")"
MATCHED_RUN_AS="$("$JQ" -r '.runAs // "root"' <<<"$MATCHED_ENTRY")"

if [[ "$MATCHED_RUN_AS" != "root" ]]; then
  die "unsupported runAs target '$MATCHED_RUN_AS' for entry '$MATCHED_NAME'"
fi

echo "Keystone approval granted: $MATCHED_DISPLAY_NAME" >&2
echo "Requested reason: $REASON" >&2
echo "Policy reason: $MATCHED_REASON" >&2
printf 'Executing command:'
printf ' %q' "${REQUESTED_ARGV[@]}"
printf '\n' >&2

if [[ "${REQUESTED_ARGV[0]}" != */* ]]; then
  if command -v "${REQUESTED_ARGV[0]}" >/dev/null 2>&1; then
    REQUESTED_ARGV[0]="$(command -v "${REQUESTED_ARGV[0]}")"
  elif [[ -x "/run/current-system/sw/bin/${REQUESTED_ARGV[0]}" ]]; then
    REQUESTED_ARGV[0]="/run/current-system/sw/bin/${REQUESTED_ARGV[0]}"
  else
    die "command '${REQUESTED_ARGV[0]}' is allowlisted but not available in PATH"
  fi
fi

export KS_APPROVE_EXECUTING=1
exec "${REQUESTED_ARGV[@]}"
