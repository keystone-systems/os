#!/usr/bin/env bash
# Agent task loop: pre-fetch sources, ingest, prioritize, execute.
# All tools (yq, jq, claude, gemini, codex, himalaya, git, etc.) come from the
# home-manager profile PATH set in notes.nix — no individual path resolution.
#
# Queue and control files (TASKS.yaml, PROJECTS.yaml, ISSUES.yaml) live in
# the agent home directory ($HOME), NOT in the notes repo.  The notes repo is
# used only for memory, reports, handoffs, and long-term knowledge.
#
# Placeholders (injected via pkgs.replaceVars):
#   @notesDir@         - Agent notes checkout path (used only for migration)
#   @maxTasks@         - Max tasks per execute loop
#   @agentName@        - Agent name
#   @githubUsername@   - GitHub username
#   @forgejoUsername@  - Forgejo username
#   @defaultsJson@     - Global task-loop defaults JSON
#   @ingestJson@       - Ingest-stage overrides JSON
#   @prioritizeJson@   - Prioritize-stage overrides JSON
#   @executeJson@      - Execute-stage overrides JSON
#   @profilesJson@     - Merged built-in + custom profile catalog JSON
#   @projectIndexHelper@ - zk-backed project index helper path
set -euo pipefail

# Sanity check: Ensure required system utilities are available
for cmd in bash tr systemctl jq yq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

# Config values substituted by NixOS module via pkgs.replaceVars
NOTES_DIR="@notesDir@"    # only used for one-time migration
MAX_TASKS="@maxTasks@"
AGENT_NAME="@agentName@"
GITHUB_USERNAME="@githubUsername@"
FORGEJO_USERNAME="@forgejoUsername@"
TASK_LOOP_DEFAULTS_JSON=$(cat <<'EOF'
@defaultsJson@
EOF
)
TASK_LOOP_INGEST_JSON=$(cat <<'EOF'
@ingestJson@
EOF
)
TASK_LOOP_PRIORITIZE_JSON=$(cat <<'EOF'
@prioritizeJson@
EOF
)
TASK_LOOP_EXECUTE_JSON=$(cat <<'EOF'
@executeJson@
EOF
)
TASK_LOOP_PROFILES_JSON=$(cat <<'EOF'
@profilesJson@
EOF
)
PROJECT_INDEX_HELPER="@projectIndexHelper@/bin/keystone-project-index"

LOGS_DIR="$HOME/.local/state/agent-task-loop/logs"
TASK_LOGS_DIR="$LOGS_DIR/tasks"
STATE_DIR="$HOME/.local/state/agent-task-loop/state"
LOCKFILE="$STATE_DIR/task-loop.lock"
PAUSE_FILE="$STATE_DIR/paused"
PROMETHEUS_TEXTFILE_DIR="${PROMETHEUS_TEXTFILE_DIR:-}"

mkdir -p "$LOGS_DIR" "$TASK_LOGS_DIR" "$STATE_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOGS_DIR/$TIMESTAMP.log"
START_TIME=$(date +%s)
HOST_NAME=$(hostname)
UNIT_NAME="agent-${AGENT_NAME}-task-loop"
RUN_ID="${AGENT_NAME}-task-loop-${TIMESTAMP}"
METRIC_FILE=""
if [[ -n "$PROMETHEUS_TEXTFILE_DIR" ]]; then
  METRIC_FILE="${PROMETHEUS_TEXTFILE_DIR}/keystone-agent-task-loop-${AGENT_NAME}.prom"
fi

CURRENT_STEP="init"
CURRENT_TASK=""
RUN_STATUS="success"
TASKS_COMPLETED=0
TASKS_FAILED=0
TASKS_BLOCKED=0

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
  line+=$(append_log_field "step" "$CURRENT_STEP")
  if [[ -n "$CURRENT_TASK" ]]; then
    line+=$(append_log_field "task_name" "$CURRENT_TASK")
  fi

  while [[ $# -ge 2 ]]; do
    line+=$(append_log_field "$1" "$2")
    shift 2
  done

  echo "$line" | tee -a "$LOG_FILE" >&2
}

log() {
  emit_event "log" "$*"
}

extract_urls_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '[]\n'
    return
  fi

  grep -Eo 'https?://[^ )"'"'"']+' "$file" 2>/dev/null | sort -u | jq -R . | jq -s . || printf '[]\n'
}

extract_issue_urls_json() {
  local urls_json="$1"
  printf '%s\n' "$urls_json" | jq '[.[] | select(test("/issues/[0-9]+"))]'
}

extract_pr_urls_json() {
  local urls_json="$1"
  printf '%s\n' "$urls_json" | jq '[.[] | select(test("/pulls?/[0-9]+$"))]'
}

extract_token_total() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return
  fi

  local token_value
  token_value=$(grep -Eo '"(total_tokens|totalTokens)"[[:space:]]*:[[:space:]]*[0-9]+' "$file" 2>/dev/null | tail -n1 | grep -Eo '[0-9]+' | tail -n1 || true)
  if [[ -z "$token_value" ]]; then
    token_value=$(grep -Eo '[0-9]+([,][0-9]+)? tokens' "$file" 2>/dev/null | tail -n1 | grep -Eo '[0-9]+' | tr -d '\n' || true)
  fi
  printf '%s\n' "${token_value:-0}"
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
  tmp_file=$(mktemp "${PROMETHEUS_TEXTFILE_DIR}/.${AGENT_NAME}-task-loop.XXXXXX")
  cat > "$tmp_file" <<EOF
# HELP keystone_agent_task_loop_last_run_timestamp_seconds Unix timestamp of the last task-loop run.
# TYPE keystone_agent_task_loop_last_run_timestamp_seconds gauge
keystone_agent_task_loop_last_run_timestamp_seconds{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${now}
# HELP keystone_agent_task_loop_last_success_timestamp_seconds Unix timestamp of the last successful task-loop run.
# TYPE keystone_agent_task_loop_last_success_timestamp_seconds gauge
keystone_agent_task_loop_last_success_timestamp_seconds{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} $(if [[ "$exit_code" -eq 0 ]]; then printf '%s' "$now"; else printf '0'; fi)
# HELP keystone_agent_task_loop_last_exit_code Exit code of the last task-loop run.
# TYPE keystone_agent_task_loop_last_exit_code gauge
keystone_agent_task_loop_last_exit_code{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${exit_code}
# HELP keystone_agent_task_loop_last_duration_seconds Duration of the last task-loop run.
# TYPE keystone_agent_task_loop_last_duration_seconds gauge
keystone_agent_task_loop_last_duration_seconds{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${duration}
# HELP keystone_agent_task_loop_tasks_completed_total Number of tasks completed in the last task-loop run.
# TYPE keystone_agent_task_loop_tasks_completed_total gauge
keystone_agent_task_loop_tasks_completed_total{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${TASKS_COMPLETED}
# HELP keystone_agent_task_loop_tasks_failed_total Number of tasks failed in the last task-loop run.
# TYPE keystone_agent_task_loop_tasks_failed_total gauge
keystone_agent_task_loop_tasks_failed_total{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${TASKS_FAILED}
# HELP keystone_agent_task_loop_tasks_blocked_total Number of tasks blocked in the last task-loop run.
# TYPE keystone_agent_task_loop_tasks_blocked_total gauge
keystone_agent_task_loop_tasks_blocked_total{host="${HOST_NAME}",agent="${AGENT_NAME}",unit="${UNIT_NAME}"} ${TASKS_BLOCKED}
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

  CURRENT_STEP="summary"
  CURRENT_TASK=""
  emit_event "run_finish" "Task loop finished" \
    "status" "$RUN_STATUS" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "tasks_completed" "$TASKS_COMPLETED" \
    "tasks_failed" "$TASKS_FAILED" \
    "tasks_blocked" "$TASKS_BLOCKED"
  write_metrics "$exit_code" "$duration"
}

trap finish_run EXIT

stage_builtin_profile() {
  local stage_name="$1"
  case "$stage_name" in
    ingest|prioritize) printf '%s\n' "fast" ;;
    execute) printf '%s\n' "medium" ;;
    *) printf '%s\n' "" ;;
  esac
}

resolve_stage_runtime() {
  local stage_name="$1"
  local task_json="${2:-{}}"
  local built_in_profile stage_json

  built_in_profile=$(stage_builtin_profile "$stage_name")
  case "$stage_name" in
    ingest) stage_json="$TASK_LOOP_INGEST_JSON" ;;
    prioritize) stage_json="$TASK_LOOP_PRIORITIZE_JSON" ;;
    execute) stage_json="$TASK_LOOP_EXECUTE_JSON" ;;
    *)
      echo "ERROR: unknown stage '$stage_name'" >&2
      return 1
      ;;
  esac

  jq -cn \
    --arg built_in_profile "$built_in_profile" \
    --argjson defaults "$TASK_LOOP_DEFAULTS_JSON" \
    --argjson stage_cfg "$stage_json" \
    --argjson profiles "$TASK_LOOP_PROFILES_JSON" \
    --argjson task "$task_json" '
      def first_non_empty($values):
        ($values | map(select(. != null and . != "")) | .[0] // null);
      def profile_cfg($profiles; $profile; $provider):
        if $profile == null or $provider == null then
          {}
        else
          ($profiles[$profile][$provider] // {})
        end;

      .provider = first_non_empty([
        $task.provider?,
        $stage_cfg.provider?,
        $defaults.provider?,
        "claude"
      ]) |
      .profile = first_non_empty([
        $task.profile?,
        $stage_cfg.profile?,
        $defaults.profile?,
        $built_in_profile
      ]) |
      .profileConfig = profile_cfg($profiles; .profile; .provider) |
      .model = first_non_empty([
        $task.model?,
        $stage_cfg.model?,
        $defaults.model?,
        .profileConfig.model?
      ]) |
      .fallbackModel = first_non_empty([
        $task.fallback_model?,
        $stage_cfg.fallbackModel?,
        $defaults.fallbackModel?,
        .profileConfig.fallbackModel?
      ]) |
      .effort = first_non_empty([
        $task.effort?,
        $stage_cfg.effort?,
        $defaults.effort?,
        .profileConfig.effort?
      ]) |
      {
        provider,
        profile,
        model,
        fallbackModel,
        effort
      }
    '
}

run_provider_prompt() {
  local stage_name="$1"
  local runtime_json="$2"
  local prompt="$3"
  local command_json
  local -a task_command

  local provider profile model fallback_model effort
  provider=$(echo "$runtime_json" | jq -r '.provider // ""')
  profile=$(echo "$runtime_json" | jq -r '.profile // ""')
  model=$(echo "$runtime_json" | jq -r '.model // ""')
  fallback_model=$(echo "$runtime_json" | jq -r '.fallbackModel // ""')
  effort=$(echo "$runtime_json" | jq -r '.effort // ""')

  log "  Using provider=$provider profile=${profile:-none} model=${model:-provider-default} fallback=${fallback_model:-none} effort=${effort:-none}"

  case "$provider" in
    claude)
      command_json=$(jq -cn \
        --arg prompt "$prompt" \
        --arg model "$model" \
        --arg fallback_model "$fallback_model" \
        --arg effort "$effort" '
          [
            "claude",
            "--print",
            "--output-format",
            "json",
            "--dangerously-skip-permissions"
          ]
          + (if $model != "" then ["--model", $model] else [] end)
          + (if $fallback_model != "" then ["--fallback-model", $fallback_model] else [] end)
          + (if $effort != "" then ["--effort", $effort] else [] end)
          + [$prompt]
        ')
      ;;
    gemini)
      command_json=$(jq -cn \
        --arg prompt "$prompt" \
        --arg model "$model" '
          [
            "gemini",
            "--prompt",
            $prompt,
            "--yolo"
          ]
          + (if $model != "" then ["-m", $model] else [] end)
        ')
      ;;
    codex)
      command_json=$(jq -cn \
        --arg prompt "$prompt" \
        --arg model "$model" '
          [
            "codex",
            "exec",
            "--full-auto"
          ]
          + (if $model != "" then ["-m", $model] else [] end)
          + [$prompt]
        ')
      ;;
    *)
      log "  ERROR: unsupported provider '$provider' for stage '$stage_name'"
      return 1
      ;;
  esac

  mapfile -t task_command < <(echo "$command_json" | jq -r '.[]')
  "${task_command[@]}"
}

build_task_runtime_json() {
  local task_name="$1"
  local task_entry
  task_entry=$(yq -o=json "[.tasks[] | select(.name == \"$task_name\")] | .[0]" TASKS.yaml)
  printf '%s' "$task_entry" | jq -c '{profile: (.profile // ""), provider: (.provider // ""), model: (.model // ""), fallback_model: (.fallback_model // ""), effort: (.effort // "")}'
}

# Lock to prevent concurrent runs (flock auto-releases on process death, even SIGKILL)
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  echo "Task loop already running, skipping" >&2
  exit 0
fi

# -- Migrate queue files from notes repo to agent home (one-time) -------------
# ISSUE-REQ-5/20: queue and control files live in $HOME, not $NOTES_DIR.
for _mf in TASKS.yaml PROJECTS.yaml ISSUES.yaml SCHEDULES.yaml; do
  if [[ -f "$NOTES_DIR/$_mf" && ! -f "$HOME/$_mf" ]]; then
    cp "$NOTES_DIR/$_mf" "$HOME/$_mf"
    log "Migrated $_mf from $NOTES_DIR to $HOME"
  fi
done
unset _mf

cd "$HOME"
emit_event "run_start" "Starting agent task loop" "status" "started"

if [[ -f "$PAUSE_FILE" ]]; then
  RUN_STATUS="paused"
  CURRENT_STEP="paused"
  PAUSE_AT=$(sed -n 's/^paused_at=//p' "$PAUSE_FILE" | tail -n1)
  PAUSE_BY=$(sed -n 's/^paused_by=//p' "$PAUSE_FILE" | tail -n1)
  PAUSE_REASON=$(sed -n 's/^reason=//p' "$PAUSE_FILE" | tail -n1)
  emit_event "run_paused" "Task loop is paused, skipping run" \
    "paused_at" "${PAUSE_AT:-}" \
    "paused_by" "${PAUSE_BY:-}" \
    "reason" "${PAUSE_REASON:-}"
  exit 0
fi

# -- Step 1: Pre-fetch sources -----------------------------------------------
CURRENT_STEP="prefetch"
emit_event "stage_start" "Pre-fetching sources" "stage_name" "prefetch"
SOURCES_JSON="[]"

if command -v fetch-email-source &>/dev/null; then
  log "  Fetching source: email"
  EMAIL_OUTPUT=$(fetch-email-source 2>>"$LOG_FILE" || echo "[]")
  if [[ -n "$EMAIL_OUTPUT" && "$EMAIL_OUTPUT" != "[]" ]]; then
    SOURCES_JSON=$(echo "$SOURCES_JSON" | jq --argjson data "$EMAIL_OUTPUT" \
      '. + [{"source": "email", "data": $data}]')
  fi
else
  log "  Skipping email source: fetch-email-source not found"
fi

if [[ -n "$GITHUB_USERNAME" ]] && command -v fetch-github-sources &>/dev/null; then
  log "  Fetching source: github"
  GITHUB_OUTPUT=$(fetch-github-sources "$GITHUB_USERNAME" 2>>"$LOG_FILE" || echo "{}")
  if [[ -n "$GITHUB_OUTPUT" && "$GITHUB_OUTPUT" != "{}" ]]; then
    SOURCES_JSON=$(echo "$SOURCES_JSON" | jq --argjson data "$GITHUB_OUTPUT" \
      '. + [{"source": "github", "data": $data}]')
  fi
elif [[ -n "$GITHUB_USERNAME" ]]; then
  log "  Skipping github source: fetch-github-sources not found"
fi

if [[ -n "$FORGEJO_USERNAME" ]] && command -v fetch-forgejo-sources &>/dev/null; then
  log "  Fetching source: forgejo"
  FORGEJO_OUTPUT=$(fetch-forgejo-sources "$FORGEJO_USERNAME" 2>>"$LOG_FILE" || echo "{}")
  if [[ -n "$FORGEJO_OUTPUT" && "$FORGEJO_OUTPUT" != "{}" ]]; then
    SOURCES_JSON=$(echo "$SOURCES_JSON" | jq --argjson data "$FORGEJO_OUTPUT" \
      '. + [{"source": "forgejo", "data": $data}]')
  fi
elif [[ -n "$FORGEJO_USERNAME" ]]; then
  log "  Skipping forgejo source: fetch-forgejo-sources not found"
fi

if command -v calendula &>/dev/null; then
  log "  Fetching source: calendar"
  CALENDAR_OUTPUT=$(calendula --json events list default 2>>"$LOG_FILE" || echo "[]")
  if [[ -n "$CALENDAR_OUTPUT" && "$CALENDAR_OUTPUT" != "[]" ]]; then
    SOURCES_JSON=$(echo "$SOURCES_JSON" | jq --argjson data "$CALENDAR_OUTPUT" \
      '. + [{"source": "calendar", "data": $data}]')
  fi
else
  log "  Skipping calendar source: calendula not found"
fi

PROJECT_INDEX_JSON=$("$PROJECT_INDEX_HELPER" list 2>>"$LOG_FILE" || echo '{"projects":[]}')
SOURCE_COUNT=$(printf '%s\n' "$PROJECT_INDEX_JSON" | jq '[.projects[].sources[]?] | length' 2>/dev/null || echo "0")

if [[ "$SOURCE_COUNT" -gt 0 ]]; then
  while IFS= read -r source_entry; do
    SOURCE_NAME=$(printf '%s\n' "$source_entry" | jq -r '.name // empty')
    SOURCE_CMD=$(printf '%s\n' "$source_entry" | jq -r '.command // empty')

    if [[ -n "$SOURCE_NAME" && -n "$SOURCE_CMD" ]]; then
      log "  Fetching source: $SOURCE_NAME"
      SOURCE_OUTPUT=$(bash -c "$SOURCE_CMD" 2>>"$LOG_FILE" || echo "[]")
      if [[ -n "$SOURCE_OUTPUT" && "$SOURCE_OUTPUT" != "[]" ]]; then
        SOURCES_JSON=$(echo "$SOURCES_JSON" | jq --arg name "$SOURCE_NAME" --argjson data "$SOURCE_OUTPUT" \
          '. + [{"source": $name, "data": $data}]')
      fi
    fi
  done < <(printf '%s\n' "$PROJECT_INDEX_JSON" | jq -c '.projects[].sources[]?')
fi

emit_event "stage_finish" "Finished pre-fetching sources" \
  "stage_name" "prefetch" \
  "source_entries" "$(echo "$SOURCES_JSON" | jq 'length')"

# -- Step 2: Ingest -----------------------------------------------------------
CURRENT_STEP="ingest"
INGEST_RAN=false
if [[ "$(echo "$SOURCES_JSON" | jq '[.[].data | length] | add // 0')" -gt 0 ]]; then
  INGEST_HASH_FILE="$STATE_DIR/ingest-inputs.sha256"
  CURRENT_HASH=$(
    # Hash only the normalized pre-fetched source payload. TASKS.yaml is the
    # output of ingest, so including it here makes the cache key self-invalidating.
    printf '%s\n' "$SOURCES_JSON" | jq -cS . | sha256sum | head -c 64
  )

  PREVIOUS_HASH=""
  if [[ -f "$INGEST_HASH_FILE" ]]; then
    PREVIOUS_HASH=$(cat "$INGEST_HASH_FILE")
  fi

  if [[ -n "$CURRENT_HASH" && "$CURRENT_HASH" == "$PREVIOUS_HASH" ]]; then
    log "Step 2: Inputs unchanged, skipping ingest"
  else
    log "Step 2: Ingesting sources..."
    emit_event "stage_start" "Ingesting sources" "stage_name" "ingest"
    mkdir -p "$HOME/.deepwork"
    echo "$SOURCES_JSON" | jq '.' > "$HOME/.deepwork/sources.json"
    # Back up TASKS.yaml before LLM-driven ingest for corruption recovery
    if [[ -f TASKS.yaml ]]; then
      cp TASKS.yaml "$STATE_DIR/TASKS.yaml.pre-ingest"
    fi
    INGEST_RUNTIME=$(resolve_stage_runtime "ingest")
    set +o pipefail
    run_provider_prompt "ingest" "$INGEST_RUNTIME" "/deepwork task_loop ingest" 2>&1 | tee -a "$LOG_FILE" >&2
    INGEST_EXIT=${PIPESTATUS[0]}
    set -o pipefail
    if [[ "$INGEST_EXIT" -ne 0 ]]; then
      RUN_STATUS="degraded"
      log "  WARNING: Ingest step failed, continuing..."
    else
      INGEST_RAN=true
      echo -n "$CURRENT_HASH" > "$INGEST_HASH_FILE"
    fi

    if ! yq '.' TASKS.yaml >/dev/null 2>&1; then
      log "  ERROR: TASKS.yaml corrupted during ingest. Pausing task loop."
      if [[ -f "$STATE_DIR/TASKS.yaml.pre-ingest" ]]; then
        cp "$STATE_DIR/TASKS.yaml.pre-ingest" TASKS.yaml
      else
        printf 'tasks: []\n' > TASKS.yaml
      fi
      # Document corruption in ISSUES.yaml
      if [[ ! -f ISSUES.yaml ]]; then
        printf 'issues: []\n' > ISSUES.yaml
      fi
      CORRUPT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      yq -i ".issues += [{
        \"name\": \"tasks-yaml-corrupted-ingest-${TIMESTAMP}\",
        \"description\": \"TASKS.yaml was corrupted during the ingest stage and restored from backup.\",
        \"discovered_during\": \"task-loop-ingest\",
        \"status\": \"open\",
        \"created_at\": \"$CORRUPT_TS\"
      }]" ISSUES.yaml
      # Pause the task loop so an operator investigates
      mkdir -p "$(dirname "$PAUSE_FILE")"
      {
        printf "paused_at=%s\n" "$CORRUPT_TS"
        printf "paused_by=task-loop\n"
        printf "reason=TASKS.yaml corrupted during ingest stage\n"
      } > "$PAUSE_FILE"
      INGEST_RAN=false
      RUN_STATUS="error"
    fi
    emit_event "stage_finish" "Finished ingest stage" "stage_name" "ingest" "status" "$(if [[ "$RUN_STATUS" == "error" ]]; then printf 'error'; else printf 'ok'; fi)"
  fi
else
  log "  No source data to ingest, skipping"
fi

# -- Step 3: Prioritize -------------------------------------------------------
CURRENT_STEP="prioritize"
PENDING_COUNT=0
if [[ -f TASKS.yaml ]]; then
  PENDING_COUNT=$(yq '[.tasks[] | select(.status == "pending")] | length' TASKS.yaml 2>/dev/null || echo "0")
fi
if [[ "$INGEST_RAN" == "false" && "$PENDING_COUNT" == "0" ]]; then
  log "Step 3: Skipping prioritize (no new sources, no pending tasks)"
else
  PRIORITIZE_HASH_FILE="$STATE_DIR/prioritize-inputs.sha256"
  CURRENT_HASH=""
  PROJECT_INDEX_HASH_INPUT=$(printf '%s\n' "$PROJECT_INDEX_JSON" | jq -S . 2>/dev/null || printf '{"projects":[]}\n')
  if [[ -f TASKS.yaml ]]; then
    CURRENT_HASH=$(
      {
        cat TASKS.yaml
        printf '\n'
        printf '%s\n' "$PROJECT_INDEX_HASH_INPUT"
      } | sha256sum | head -c 64
    )
  fi

  PREVIOUS_HASH=""
  if [[ -f "$PRIORITIZE_HASH_FILE" ]]; then
    PREVIOUS_HASH=$(cat "$PRIORITIZE_HASH_FILE")
  fi

  if [[ -n "$CURRENT_HASH" && "$CURRENT_HASH" == "$PREVIOUS_HASH" ]]; then
    log "Step 3: Inputs unchanged, skipping prioritize"
  else
    log "Step 3: Prioritizing tasks..."
    emit_event "stage_start" "Prioritizing tasks" "stage_name" "prioritize"
    # Back up TASKS.yaml before LLM-driven prioritize for corruption recovery
    if [[ -f TASKS.yaml ]]; then
      cp TASKS.yaml "$STATE_DIR/TASKS.yaml.pre-prioritize"
    fi
    PRIORITIZE_RUNTIME=$(resolve_stage_runtime "prioritize")
    set +o pipefail
    run_provider_prompt "prioritize" "$PRIORITIZE_RUNTIME" "/deepwork task_loop prioritize" 2>&1 | tee -a "$LOG_FILE" >&2
    PRIORITIZE_EXIT=${PIPESTATUS[0]}
    set -o pipefail
    if [[ "$PRIORITIZE_EXIT" -ne 0 ]]; then
      RUN_STATUS="degraded"
      log "  WARNING: Prioritize step failed, continuing..."
    else
      if ! yq '.' TASKS.yaml >/dev/null 2>&1; then
        log "  ERROR: TASKS.yaml corrupted during prioritize. Pausing task loop."
        if [[ -f "$STATE_DIR/TASKS.yaml.pre-prioritize" ]]; then
          cp "$STATE_DIR/TASKS.yaml.pre-prioritize" TASKS.yaml
        else
          printf 'tasks: []\n' > TASKS.yaml
        fi
        # Document corruption in ISSUES.yaml
        if [[ ! -f ISSUES.yaml ]]; then
          printf 'issues: []\n' > ISSUES.yaml
        fi
        CORRUPT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        yq -i ".issues += [{
          \"name\": \"tasks-yaml-corrupted-prioritize-${TIMESTAMP}\",
          \"description\": \"TASKS.yaml was corrupted during the prioritize stage and restored from backup.\",
          \"discovered_during\": \"task-loop-prioritize\",
          \"status\": \"open\",
          \"created_at\": \"$CORRUPT_TS\"
        }]" ISSUES.yaml
        # Pause the task loop so an operator investigates
        mkdir -p "$(dirname "$PAUSE_FILE")"
        {
          printf "paused_at=%s\n" "$CORRUPT_TS"
          printf "paused_by=task-loop\n"
          printf "reason=TASKS.yaml corrupted during prioritize stage\n"
        } > "$PAUSE_FILE"
        RUN_STATUS="error"
      else
        echo -n "$CURRENT_HASH" > "$PRIORITIZE_HASH_FILE"
      fi
    fi
    emit_event "stage_finish" "Finished prioritize stage" "stage_name" "prioritize" "status" "$(if [[ "$PRIORITIZE_EXIT" -eq 0 ]]; then printf 'ok'; else printf 'error'; fi)"
  fi
fi

# -- Step 4: Execute pending tasks -------------------------------------------
if [[ ! -f TASKS.yaml ]] || \
   [[ "$(yq '[.tasks[] | select(.status == "pending")] | length' TASKS.yaml 2>/dev/null)" == "0" ]]; then
  log "No pending tasks after ingest, done"
  exit 0
fi

CURRENT_STEP="execute"
emit_event "stage_start" "Executing pending tasks" "stage_name" "execute" "max_tasks" "$MAX_TASKS"
TASK_COUNT=0
ATTEMPTED_TASKS=":"

while [[ $TASK_COUNT -lt "$MAX_TASKS" ]]; do
  TASK_NAME=$(yq '[.tasks[] | select(.status == "pending")] | .[0].name' TASKS.yaml 2>/dev/null || echo "null")

  if [[ "$TASK_NAME" == "null" || -z "$TASK_NAME" ]]; then
    log "  No more pending tasks"
    break
  fi

  if [[ "$ATTEMPTED_TASKS" == *":$TASK_NAME:"* ]]; then
    log "  Task $TASK_NAME already attempted in this run but still pending. Breaking to prevent infinite loop."
    break
  fi
  ATTEMPTED_TASKS="${ATTEMPTED_TASKS}${TASK_NAME}:"

  TASK_DESC=$(yq "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].description" TASKS.yaml)
  TASK_WORKFLOW=$(yq "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].workflow // \"\"" TASKS.yaml)
  TASK_NEEDS=$(yq "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].needs // []" TASKS.yaml)
  TASK_SOURCE=$(yq "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].source // \"\"" TASKS.yaml)
  TASK_SOURCE_REF=$(yq "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].source_ref // \"\"" TASKS.yaml)

  if [[ "$TASK_NEEDS" != "[]" && "$TASK_NEEDS" != "null" ]]; then
    NEEDS_MET=true
    for need in $(echo "$TASK_NEEDS" | jq -r '.[]' 2>/dev/null); do
      NEED_STATUS=$(yq "[.tasks[] | select(.name == \"$need\")] | .[0].status // \"pending\"" TASKS.yaml)
      if [[ "$NEED_STATUS" != "completed" ]]; then
        NEEDS_MET=false
        break
      fi
    done
    if [[ "$NEEDS_MET" == "false" ]]; then
      log "  Skipping $TASK_NAME (unmet dependencies)"
      yq -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"blocked\"" TASKS.yaml
      TASKS_BLOCKED=$((TASKS_BLOCKED + 1))
      emit_event "task_finish" "Task blocked by unmet dependencies" \
        "status" "blocked" \
        "workflow" "$TASK_WORKFLOW" \
        "source" "$TASK_SOURCE" \
        "source_ref" "$TASK_SOURCE_REF" \
        "duration_seconds" "0"
      continue
    fi
  fi

  TASK_COUNT=$((TASK_COUNT + 1))
  TASK_TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
  TASK_LOG="$TASK_LOGS_DIR/${TASK_TIMESTAMP}_${TASK_NAME}.log"
  TASK_START_TS=$(date +%s)

  CURRENT_TASK="$TASK_NAME"
  emit_event "task_start" "Executing task" \
    "workflow" "$TASK_WORKFLOW" \
    "source" "$TASK_SOURCE" \
    "source_ref" "$TASK_SOURCE_REF"

  TASK_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  yq -i "(.tasks[] | select(.name == \"$TASK_NAME\")).started_at = \"$TASK_STARTED_AT\"" TASKS.yaml
  yq -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"in_progress\"" TASKS.yaml

  if [[ -n "$TASK_WORKFLOW" && "$TASK_WORKFLOW" != "null" && "$TASK_WORKFLOW" != "" ]]; then
    PROMPT="/deepwork $TASK_WORKFLOW

Task: $TASK_NAME
Description: $TASK_DESC"
  else
    PROMPT="Execute this task.

Task: $TASK_NAME
Description: $TASK_DESC"
  fi

  TASK_RUNTIME_JSON=$(build_task_runtime_json "$TASK_NAME")
  if [[ -z "$TASK_RUNTIME_JSON" ]]; then
    TASK_RUNTIME_JSON="{}"
  fi
  EXECUTE_RUNTIME=$(resolve_stage_runtime "execute")
  TASK_PROVIDER=$(echo "$EXECUTE_RUNTIME" | jq -r '.provider // ""')
  TASK_PROFILE=$(echo "$EXECUTE_RUNTIME" | jq -r '.profile // ""')
  TASK_MODEL=$(echo "$EXECUTE_RUNTIME" | jq -r '.model // ""')

  set +o pipefail
  run_provider_prompt "execute" "$EXECUTE_RUNTIME" "$PROMPT" 2>&1 | tee "$TASK_LOG" >&2
  TASK_EXIT=${PIPESTATUS[0]}
  set -o pipefail

  TASK_END_TS=$(date +%s)
  TASK_DURATION=$((TASK_END_TS - TASK_START_TS))
  PARSED_URLS_JSON=$(extract_urls_json "$TASK_LOG")
  ISSUE_URLS_JSON=$(extract_issue_urls_json "$PARSED_URLS_JSON")
  PR_URLS_JSON=$(extract_pr_urls_json "$PARSED_URLS_JSON")
  TOKEN_TOTAL=$(extract_token_total "$TASK_LOG")

  if [[ "$TASK_EXIT" -eq 0 ]]; then
    TASK_COMPLETED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    yq -i "(.tasks[] | select(.name == \"$TASK_NAME\")).completed_at = \"$TASK_COMPLETED_AT\"" TASKS.yaml
    yq -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"completed\"" TASKS.yaml
    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
    log "  Task $TASK_NAME completed (log: $TASK_LOG)"
  else
    yq -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"error\"" TASKS.yaml
    RUN_STATUS="degraded"
    TASKS_FAILED=$((TASKS_FAILED + 1))
    log "  Task $TASK_NAME errored (exit $TASK_EXIT, log: $TASK_LOG)"
  fi

  emit_event "task_finish" "Finished task execution" \
    "status" "$(if [[ "$TASK_EXIT" -eq 0 ]]; then printf 'completed'; else printf 'error'; fi)" \
    "workflow" "$TASK_WORKFLOW" \
    "source" "$TASK_SOURCE" \
    "source_ref" "$TASK_SOURCE_REF" \
    "provider" "$TASK_PROVIDER" \
    "profile" "$TASK_PROFILE" \
    "model" "$TASK_MODEL" \
    "duration_seconds" "$TASK_DURATION" \
    "exit_code" "$TASK_EXIT" \
    "token_total" "$TOKEN_TOTAL" \
    "parsed_urls" "$(printf '%s\n' "$PARSED_URLS_JSON" | jq -c .)" \
    "issue_urls" "$(printf '%s\n' "$ISSUE_URLS_JSON" | jq -c .)" \
    "pr_urls" "$(printf '%s\n' "$PR_URLS_JSON" | jq -c .)" \
    "task_log_path" "$TASK_LOG"
done

# -- Rotate old logs (keep last 20) -------------------------------------------
COUNT=0
find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f | sort -r | while IFS= read -r file; do
  COUNT=$((COUNT + 1))
  if [[ "$COUNT" -gt 20 ]]; then
    rm -f "$file"
  fi
done
