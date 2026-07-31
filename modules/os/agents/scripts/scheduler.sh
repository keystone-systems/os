#!/usr/bin/env bash
# Agent scheduler: reads SCHEDULES.yaml, creates due tasks, triggers task loop.
# All tools come from the agent's home-manager profile PATH set in notes.nix.
# Pure bash, no LLM.
set -eo pipefail

# Sanity check: Ensure required system utilities are available
for cmd in bash tr systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

# Config values substituted by NixOS module via pkgs.replaceVars
NOTES_DIR="@notesDir@"    # only used for one-time migration
AGENT_NAME="@agentName@"

LOGS_DIR="$HOME/.local/state/agent-scheduler/logs"
PROMETHEUS_TEXTFILE_DIR="${PROMETHEUS_TEXTFILE_DIR:-}"

mkdir -p "$LOGS_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOGS_DIR/$TIMESTAMP.log"
TODAY=$(date +%Y-%m-%d)
DOW=$(date +%A | tr '[:upper:]' '[:lower:]')
DOM=$(date +%-d)
START_TIME=$(date +%s)
HOST_NAME=$(hostname)
UNIT_NAME="agent-${AGENT_NAME}-scheduler"
RUN_ID="${AGENT_NAME}-scheduler-${TIMESTAMP}"
METRIC_FILE=""
if [[ -n "$PROMETHEUS_TEXTFILE_DIR" ]]; then
  METRIC_FILE="${PROMETHEUS_TEXTFILE_DIR}/keystone-agent-scheduler-${AGENT_NAME}.prom"
fi
RUN_STATUS="success"

logfmt_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '"%s"' "$value"
}

append_log_field() {
  local key="$1"
  local value="$2"
  printf ' %s=%s' "$key" "$(logfmt_escape "$value")"
}

emit_event() {
  local event="$1"
  local message="$2"
  shift 2

  local line="[$(date '+%H:%M:%S')]"
  line+=$(append_log_field "event" "$event")
  line+=$(append_log_field "msg" "$message")
  line+=$(append_log_field "host" "$HOST_NAME")
  line+=$(append_log_field "agent" "$AGENT_NAME")
  line+=$(append_log_field "unit" "$UNIT_NAME")
  line+=$(append_log_field "run_id" "$RUN_ID")

  while [[ $# -ge 2 ]]; do
    line+=$(append_log_field "$1" "$2")
    shift 2
  done

  echo "$line" | tee -a "$LOG_FILE" >&2
}

log() {
  emit_event "log" "$*"
}

write_metrics() {
  local exit_code="$1"
  local duration="$2"
  local now
  now=$(date +%s)

  if [[ -z "$METRIC_FILE" || ! -d "$PROMETHEUS_TEXTFILE_DIR" ]]; then
    return
  fi

  local tmp_file
  tmp_file=$(mktemp "${PROMETHEUS_TEXTFILE_DIR}/.${AGENT_NAME}-scheduler.XXXXXX")
  cat > "$tmp_file" <<EOF
# HELP keystone_agent_scheduler_last_run_timestamp_seconds Unix timestamp of the last scheduler run.
# TYPE keystone_agent_scheduler_last_run_timestamp_seconds gauge
keystone_agent_scheduler_last_run_timestamp_seconds{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${now}
# HELP keystone_agent_scheduler_last_success_timestamp_seconds Unix timestamp of the last successful scheduler run.
# TYPE keystone_agent_scheduler_last_success_timestamp_seconds gauge
keystone_agent_scheduler_last_success_timestamp_seconds{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} $(if [[ "$exit_code" -eq 0 ]]; then printf '%s' "$now"; else printf '0'; fi)
# HELP keystone_agent_scheduler_last_exit_code Exit code of the last scheduler run.
# TYPE keystone_agent_scheduler_last_exit_code gauge
keystone_agent_scheduler_last_exit_code{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${exit_code}
# HELP keystone_agent_scheduler_last_duration_seconds Duration of the last scheduler run.
# TYPE keystone_agent_scheduler_last_duration_seconds gauge
keystone_agent_scheduler_last_duration_seconds{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${duration}
# HELP keystone_agent_scheduler_tasks_created_total Number of tasks created in the last scheduler run.
# TYPE keystone_agent_scheduler_tasks_created_total gauge
keystone_agent_scheduler_tasks_created_total{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${CREATED:-0}
EOF
  mv "$tmp_file" "$METRIC_FILE"
}

finish_run() {
  local exit_code=$?
  local end_time duration
  end_time=$(date +%s)
  duration=$((end_time - START_TIME))

  if [[ "$exit_code" -ne 0 ]]; then
    RUN_STATUS="error"
  fi

  emit_event "run_finish" "Scheduler finished" \
    "status" "$RUN_STATUS" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "tasks_created" "${CREATED:-0}"
  write_metrics "$exit_code" "$duration"
}

trap finish_run EXIT

# -- Migrate queue files from notes repo to agent home (one-time) -------------
for _mf in TASKS.yaml SCHEDULES.yaml; do
  if [[ -f "$NOTES_DIR/$_mf" && ! -f "$HOME/$_mf" ]]; then
    cp "$NOTES_DIR/$_mf" "$HOME/$_mf"
    log "Migrated $_mf from $NOTES_DIR to $HOME"
  fi
done
unset _mf

cd "$HOME"
emit_event "run_start" "Starting scheduler" "status" "started" "date" "$TODAY" "day_of_week" "$DOW" "day_of_month" "$DOM"

if [ ! -f SCHEDULES.yaml ]; then
  log "No SCHEDULES.yaml found, exiting"
  exit 0
fi

if [ ! -f TASKS.yaml ]; then
  log "No TASKS.yaml found, creating empty one"
  echo "tasks: []" > TASKS.yaml
fi

SCHEDULE_COUNT=$(yq '.schedules | length' SCHEDULES.yaml 2>/dev/null || echo "0")
CREATED=0

for i in $(seq 0 $((SCHEDULE_COUNT - 1))); do
  SCHED_NAME=$(yq ".schedules[$i].name" SCHEDULES.yaml)
  SCHED_DESC=$(yq ".schedules[$i].description" SCHEDULES.yaml)
  SCHED_SCHEDULE=$(yq ".schedules[$i].schedule" SCHEDULES.yaml)
  SCHED_WORKFLOW=$(yq ".schedules[$i].workflow" SCHEDULES.yaml)

  # Check if schedule is due today
  IS_DUE=false

  case "$SCHED_SCHEDULE" in
    daily)
      IS_DUE=true
      ;;
    weekly:*)
      TARGET_DAY="${SCHED_SCHEDULE#weekly:}"
      if [ "$DOW" = "$TARGET_DAY" ]; then
        IS_DUE=true
      fi
      ;;
    monthly:*)
      TARGET_DOM="${SCHED_SCHEDULE#monthly:}"
      if [ "$DOM" = "$TARGET_DOM" ]; then
        IS_DUE=true
      fi
      ;;
    *)
      log "  Unknown schedule format: $SCHED_SCHEDULE for $SCHED_NAME"
      ;;
  esac

  if [ "$IS_DUE" = "false" ]; then
    continue
  fi

  # Build source_ref for deduplication
  SOURCE_REF="schedule-${SCHED_NAME}-${TODAY}"

  # Check if task already exists
  EXISTING=$(yq "[.tasks[] | select(.source_ref == \"$SOURCE_REF\")] | length" TASKS.yaml 2>/dev/null || echo "0")

  if [ "$EXISTING" -gt 0 ]; then
    log "  Skipping $SCHED_NAME (already exists: $SOURCE_REF)"
    continue
  fi

  # Append new task to TASKS.yaml
  log "  Creating task: ${SCHED_NAME}-${TODAY}"
  TASK_CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  yq -i ".tasks += [{
    \"name\": \"${SCHED_NAME}-$(date +%Y-%m-%d)\",
    \"description\": \"$SCHED_DESC\",
    \"status\": \"pending\",
    \"source\": \"schedule\",
    \"source_ref\": \"$SOURCE_REF\",
    \"workflow\": \"$SCHED_WORKFLOW\",
    \"created_at\": \"$TASK_CREATED_AT\"
  }]" TASKS.yaml

  emit_event "task_created" "Created scheduled task" \
    "task_name" "${SCHED_NAME}-${TODAY}" \
    "source" "schedule" \
    "source_ref" "$SOURCE_REF" \
    "workflow" "$SCHED_WORKFLOW"

  CREATED=$((CREATED + 1))
done

log "Scheduler: $CREATED tasks from SCHEDULES.yaml"

# -- CalDAV calendar events ---------------------------------------------------
# Read upcoming events from the agent's CalDAV calendar via calendula.
# All events on the calendar become tasks — the calendar itself is the
# scheduling mechanism. Events missing a UID or summary are skipped.
# Gracefully skips if calendula is not available.
if command -v calendula &>/dev/null; then
  log "Reading CalDAV calendar events..."
  CAL_EVENTS=$(calendula --json events list default 2>>"$LOG_FILE" || echo "[]")

  if [ "$CAL_EVENTS" != "[]" ] && [ -n "$CAL_EVENTS" ]; then
    CAL_COUNT=$(echo "$CAL_EVENTS" | jq 'length' 2>/dev/null || echo "0")
    log "  Found $CAL_COUNT calendar events"

    if [ "$CAL_COUNT" -gt 0 ]; then
    for j in $(seq 0 $((CAL_COUNT - 1))); do
      CAL_UID=$(echo "$CAL_EVENTS" | jq -r ".[$j].uid // empty" 2>/dev/null || true)
      CAL_SUMMARY=$(echo "$CAL_EVENTS" | jq -r ".[$j].summary // empty" 2>/dev/null || true)
      CAL_DESCRIPTION=$(echo "$CAL_EVENTS" | jq -r ".[$j].description // .[$j].summary // empty" 2>/dev/null || true)
      CAL_START=$(echo "$CAL_EVENTS" | jq -r ".[$j].start // empty" 2>/dev/null || true)

      # Skip events without a UID or summary
      if [ -z "$CAL_UID" ] || [ -z "$CAL_SUMMARY" ]; then
        continue
      fi

      # Use event start date for deduplication when available, fall back to today
      CAL_DATE="${TODAY}"
      if [ -n "$CAL_START" ]; then
        # Extract date portion (YYYY-MM-DD) from start timestamp without relying on grep -P
        CAL_DATE_PARSED=${CAL_START:0:10}
        case "$CAL_DATE_PARSED" in
          ????-??-??) CAL_DATE="$CAL_DATE_PARSED" ;;
        esac
      fi

      # Build source_ref for deduplication: calendar-<uid>-<date>
      CAL_SOURCE_REF="calendar-${CAL_UID}-${CAL_DATE}"

      # Check if task already exists
      EXISTING=$(yq "[.tasks[] | select(.source_ref == \"$CAL_SOURCE_REF\")] | length" TASKS.yaml 2>/dev/null || echo "0")
      if [ "$EXISTING" -gt 0 ]; then
        log "  Skipping calendar event (already exists: $CAL_SOURCE_REF)"
        continue
      fi

      # Create task from calendar event — use yq env() to safely handle special chars
      CAL_TASK_NAME="calendar-$(echo "$CAL_SUMMARY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')-${CAL_DATE}"
      TASK_CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      log "  Creating task from calendar: $CAL_TASK_NAME"
      export CAL_TASK_NAME CAL_DESCRIPTION CAL_SOURCE_REF TASK_CREATED_AT
      yq -i '.tasks += [{
        "name": env(CAL_TASK_NAME),
        "description": env(CAL_DESCRIPTION),
        "status": "pending",
        "source": "calendar",
        "source_ref": env(CAL_SOURCE_REF),
        "created_at": env(TASK_CREATED_AT)
      }]' TASKS.yaml

      emit_event "task_created" "Created calendar task" \
        "task_name" "$CAL_TASK_NAME" \
        "source" "calendar" \
        "source_ref" "$CAL_SOURCE_REF"

      CREATED=$((CREATED + 1))
    done
    fi # CAL_COUNT > 0
  else
    log "  No calendar events found"
  fi
else
  log "Skipping CalDAV events: calendula not found"
fi

log "Scheduler finished: created $CREATED total tasks"

# Trigger task loop if we created any tasks
if [ $CREATED -gt 0 ]; then
  log "Triggering agent-${AGENT_NAME}-task-loop.service..."
  systemctl --user start "agent-${AGENT_NAME}-task-loop.service" || {
    log "  WARNING: Failed to trigger task loop"
  }
fi
