#!/usr/bin/env bash
# agentctl: unified CLI for managing agent services and mail.
# Dispatches to the per-agent Nix store helper via sudo (no SETENV needed).
# All defined agents are manageable via agentctl.

AGENTCTL_ENV_FILE="${AGENTCTL_ENV_FILE:-$HOME/.config/keystone/agentctl.env}"
if [ ! -f "$AGENTCTL_ENV_FILE" ]; then
  echo "Error: agentctl env file not found: $AGENTCTL_ENV_FILE" >&2
  echo "Rebuild the system or activate the development profile that provides it." >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$AGENTCTL_ENV_FILE"

LAUNCHER_STATE_NOTES_DIR="${NOTES_DIR:-$HOME/notes}"

launcher_state_json() {
  "$PROJECT_PREFS" launcher-state-json 2>/dev/null || printf '%s\n' '{"interactive_defaults":{"agents":{},"projects":{}}}'
}

effective_pref_json() {
  local agent_name="$1"
  local project_slug="${2:-}"
  local configured_host="${3:-}"

  launcher_state_json | jq -c \
    --arg agent_name "$agent_name" \
    --arg project_slug "$project_slug" \
    --arg configured_host "$configured_host" '
      (.interactive_defaults.agents[$agent_name] // {}) as $agent
      | (if $project_slug == "" then {} else (.interactive_defaults.projects[$project_slug] // {}) end) as $project
      | {
          host: ($project.host // $agent.host // $configured_host // ""),
          provider: ($project.provider // $agent.provider // ""),
          model: ($project.model // $agent.model // ""),
          fallback_model: ($project.fallback_model // $agent.fallback_model // "")
        }
    '
}

agent_pause_state_json() {
  local agent_name="$1"
  local output=""
  output=$(agentctl "$agent_name" paused 2>/dev/null || true)

  if printf '%s\n' "$output" | grep -q ': paused'; then
    jq -cn \
      --arg state "paused" \
      --arg paused_at "$(printf '%s\n' "$output" | sed -n 's/^paused_at: //p' | tail -n1)" \
      --arg paused_by "$(printf '%s\n' "$output" | sed -n 's/^paused_by: //p' | tail -n1)" \
      --arg reason "$(printf '%s\n' "$output" | sed -n 's/^reason: //p' | tail -n1)" \
      '{ state: $state, pausedAt: $paused_at, pausedBy: $paused_by, reason: $reason }'
  else
    jq -cn '{ state: "active", pausedAt: "", pausedBy: "", reason: "" }'
  fi
}

agent_pref_json() {
  local agent_name="$1"
  local project_slug="${2:-}"
  local configured_host="${3:-}"
  local pref_json

  pref_json=$(effective_pref_json "$agent_name" "$project_slug" "$configured_host" 2>/dev/null || printf '{}')

  printf '%s\n' "$pref_json"
}

agent_pref_set() {
  local agent_name="$1"
  local host="$2"
  local provider="$3"
  local model="$4"
  local fallback_model="${5:-}"
  local project_slug="${6:-}"

  if [[ -n "$project_slug" ]]; then
    local current_json effective_provider effective_model effective_fallback
    current_json=$("$PROJECT_PREFS" project-launch-json "$project_slug")
    effective_provider=$(printf '%s\n' "$current_json" | jq -r '.provider // ""')
    effective_model=$(printf '%s\n' "$current_json" | jq -r '.model // ""')
    effective_fallback=$(printf '%s\n' "$current_json" | jq -r '.fallbackModel // ""')

    if [[ -n "$provider" ]]; then
      effective_provider="$provider"
    fi
    if [[ -n "$model" ]]; then
      effective_model="$model"
    fi
    if [[ -n "$fallback_model" ]]; then
      effective_fallback="$fallback_model"
    fi

    "$PROJECT_PREFS" project-set-host "$project_slug" "$host" >/dev/null
    if [[ -n "$effective_provider" || -n "$effective_model" || -n "$effective_fallback" ]]; then
      "$PROJECT_PREFS" project-set-models \
        "$project_slug" \
        "${effective_provider:-claude}" \
        "$effective_model" \
        "${effective_fallback:-}" >/dev/null
    fi
    return 0
  fi

  "$PROJECT_PREFS" agent-set-pref "$agent_name" "$host" "$provider" "$model" "${fallback_model:-}"
}

agent_pref_clear() {
  local agent_name="$1"
  local project_slug="${2:-}"

  if [[ -n "$project_slug" ]]; then
    "$PROJECT_PREFS" project-clear-prefs "$project_slug"
    return 0
  fi

  "$PROJECT_PREFS" agent-clear-pref "$agent_name"
}

agent_show_json() {
  local agent_name="$1"
  local project_slug="${2:-}"

  if ! set_agent_helper "$agent_name"; then
    exit 1
  fi
  set_agent_notes_dir "$agent_name"
  VNC_PORT=""
  set_agent_vnc_port "$agent_name"
  AGENT_HOST=""
  set_agent_host "$agent_name"

  local pref_json pause_json preferred_host
  pref_json=$(agent_pref_json "$agent_name" "$project_slug" "$AGENT_HOST")
  pause_json=$(agent_pause_state_json "$agent_name")
  preferred_host=$(printf '%s\n' "$pref_json" | jq -r --arg configured_host "$AGENT_HOST" '
    .host // $configured_host // ""
  ')

  jq -cn \
    --arg agent "$agent_name" \
    --arg configured_host "${AGENT_HOST}" \
    --arg preferred_host "${preferred_host}" \
    --arg project "${project_slug}" \
    --arg vnc_port "${VNC_PORT}" \
    --argjson prefs "$pref_json" \
    --argjson pause "$pause_json" '
      {
        agent: $agent,
        configuredHost: $configured_host,
        preferredHost: $preferred_host,
        project: $project,
        provider: ($prefs.provider // ""),
        model: ($prefs.model // ""),
        fallbackModel: ($prefs.fallback_model // ""),
        vncPort: (if $vnc_port == "" then null else ($vnc_port | tonumber) end),
        pause: $pause
      }
    '
}

if [[ $# -ge 1 ]]; then
  case "$1" in
    list)
      shift
      if [[ "${1:-}" != "--json" ]]; then
        echo "Usage: agentctl list --json" >&2
        exit 1
      fi

      shift
      json_lines=""
      for agent_name in ${KNOWN_AGENTS//,/ }; do
        agent_name=$(printf '%s' "$agent_name" | xargs)
        [[ -z "$agent_name" ]] && continue
        json_lines+="$(agent_show_json "$agent_name")"$'\n'
      done
      printf '%s' "$json_lines" | jq -s '.'
      exit 0
      ;;
    show)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Usage: agentctl show <agent> [--project <slug>] --json" >&2
        exit 1
      fi

      show_agent="$1"
      shift
      show_project=""
      show_json=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --project) show_project="$2"; shift 2 ;;
          --json) show_json=true; shift ;;
          *) echo "error: unknown show option '$1'" >&2; exit 1 ;;
        esac
      done

      if [[ "$show_json" != true ]]; then
        echo "Usage: agentctl show <agent> [--project <slug>] --json" >&2
        exit 1
      fi

      agent_show_json "$show_agent" "$show_project"
      exit 0
      ;;
    prefs)
      shift
      subcmd="${1:-}"
      shift || true
      case "$subcmd" in
        get)
          agent_name="${1:-}"
          shift || true
          show_project=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --project) show_project="$2"; shift 2 ;;
              *) echo "error: unknown prefs get option '$1'" >&2; exit 1 ;;
            esac
          done
          [[ -n "$agent_name" ]] || { echo "Usage: agentctl prefs get <agent> [--project <slug>]" >&2; exit 1; }
          configured_host=""
          if set_agent_helper "$agent_name"; then
            set_agent_host "$agent_name"
            configured_host="$AGENT_HOST"
          fi
          agent_pref_json "$agent_name" "$show_project" "$configured_host"
          exit 0
          ;;
        set)
          agent_name="${1:-}"
          shift || true
          host=""
          provider=""
          model=""
          fallback_model=""
          project_slug=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --host) host="$2"; shift 2 ;;
              --provider) provider="$2"; shift 2 ;;
              --model) model="$2"; shift 2 ;;
              --fallback-model) fallback_model="$2"; shift 2 ;;
              --project) project_slug="$2"; shift 2 ;;
              *) echo "error: unknown prefs set option '$1'" >&2; exit 1 ;;
            esac
          done
          [[ -n "$agent_name" && -n "$host" ]] || { echo "Usage: agentctl prefs set <agent> --host <host> [--project <slug>] [--provider <provider>] [--model <model>] [--fallback-model <model>]" >&2; exit 1; }
          agent_pref_set "$agent_name" "$host" "$provider" "$model" "$fallback_model" "$project_slug"
          exit 0
          ;;
        clear)
          agent_name="${1:-}"
          shift || true
          project_slug=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --project) project_slug="$2"; shift 2 ;;
              *) echo "error: unknown prefs clear option '$1'" >&2; exit 1 ;;
            esac
          done
          [[ -n "$agent_name" ]] || { echo "Usage: agentctl prefs clear <agent> [--project <slug>]" >&2; exit 1; }
          agent_pref_clear "$agent_name" "$project_slug"
          exit 0
          ;;
        *)
          echo "Usage: agentctl prefs {get|set|clear} ..." >&2
          exit 1
          ;;
      esac
      ;;
  esac
fi

if [ $# -lt 2 ]; then
  echo "Usage: agentctl <agent-name> <command> [args...]" >&2
  echo "" >&2
  echo "Known agents: $KNOWN_AGENTS" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  <systemctl-verb>  Run systemctl --user as the agent (status, start, stop, ...)" >&2
  echo "  logs              Run journalctl --user as the agent" >&2
  echo "  cron              List the agent's scheduled timers" >&2
  echo "  pause [reason]    Pause task-loop runs for the agent" >&2
  echo "  resume            Resume task-loop runs for the agent" >&2
  echo "  paused            Show whether the agent task loop is paused" >&2
  echo "  exec              Run an arbitrary command as the agent" >&2
  echo "  tasks             Show agent tasks in a table (pending/in_progress first)" >&2
  echo "  email             Show the agent's inbox (recent envelopes)" >&2
  echo "  shell             Open interactive shell as the agent (with SSH agent)" >&2
  echo "  claude            Start interactive Claude session (supports --project, --role, --roles)" >&2
  echo "  gemini            Start interactive Gemini session (supports --project, --role, --roles)" >&2
  echo "  codex             Start interactive Codex session (supports --project, --role, --roles)" >&2
  echo "  opencode          Start interactive OpenCode session (supports --project, --role, --roles)" >&2
  echo "  mail              Send structured email to the agent (via agent-mail)" >&2
  echo "  vnc               Open remote-viewer to the agent's VNC desktop" >&2
  echo "  provision         Generate SSH keypair, mail password, and agenix secrets" >&2
  echo "" >&2
  echo "Flags:" >&2
  echo "  -r, --role <mode>      Compose role-specific prompt via .agents/compose.sh" >&2
  echo "  --roles <role1,...>    Comma-separated extra roles appended after mode roles" >&2
  echo "  -p, --project <slug>   Run in project context with zellij session" >&2
  echo "  --local [model]        Use the configured Ollama server for claude/opencode" >&2
  echo "  --sandbox              Opt into Podman sandbox for this session (default: direct execution)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  agentctl drago status agent-drago-task-loop" >&2
  echo "  agentctl drago logs -u agent-drago-task-loop -n 20" >&2
  echo "  agentctl drago cron" >&2
  echo "  agentctl drago pause \"waiting for human input\"" >&2
  echo "  agentctl drago resume" >&2
  echo "  agentctl drago paused" >&2
  echo "  agentctl drago tasks" >&2
  echo "  agentctl drago email" >&2
  echo "  agentctl drago shell" >&2
  echo "  agentctl drago claude" >&2
  echo "  agentctl drago claude -r code-review" >&2
  echo "  agentctl drago claude --local" >&2
  echo "  agentctl drago claude --local qwen3:32b" >&2
  echo "  agentctl drago claude --roles software-engineer,code-reviewer" >&2
  echo "  agentctl drago claude -r implementation --roles software-engineer" >&2
  echo "  agentctl drago claude --project nixos-config fix-auth" >&2
  echo "  agentctl drago claude --project nixos-config              # list sessions" >&2
  echo "  agentctl drago gemini -r code-review" >&2
  echo "  agentctl drago gemini --project nixos-config fix-auth" >&2
  echo "  agentctl drago codex --project nixos-config fix-auth" >&2
  echo "  agentctl drago opencode --project nixos-config fix-auth" >&2
  echo "  agentctl drago opencode --local" >&2
  echo "  agentctl drago gemini" >&2
  echo "  agentctl drago codex" >&2
  echo "  agentctl drago opencode" >&2
  echo "  agentctl drago vnc" >&2
  echo "  agentctl drago mail task --subject \"Fix CI pipeline\"" >&2
  echo "  agentctl drago provision                     # full flow incl. hwrekey" >&2
  echo "  agentctl drago provision --skip-rekey        # skip hwrekey at end" >&2
  exit 1
fi
AGENT_NAME="$1"; shift

if ! set_agent_helper "$AGENT_NAME"; then
  exit 1
fi
set_agent_notes_dir "$AGENT_NAME"

# Static lookup — agent name -> VNC port (desktop agents only)
VNC_PORT=""
set_agent_vnc_port "$AGENT_NAME"

# Resolve agent's host for remote dispatch
AGENT_HOST=""
set_agent_host "$AGENT_NAME"

OLLAMA_ENABLED="false"
OLLAMA_HOST="http://localhost:11434"
OLLAMA_DEFAULT_MODEL=""
set_agent_ollama "$AGENT_NAME"

THIS_HOST="$(cat /etc/hostname)"

REQUESTED_PROJECT=""
if [[ $# -ge 2 ]]; then
  for ((i = 2; i <= $#; i++)); do
    if [[ "${!i}" == "--project" || "${!i}" == "-p" ]]; then
      next_index=$((i + 1))
      REQUESTED_PROJECT="${!next_index:-}"
      break
    fi
  done
fi

EFFECTIVE_PREFS=$(effective_pref_json "$AGENT_NAME" "$REQUESTED_PROJECT" "$AGENT_HOST")
EFFECTIVE_AGENT_HOST=$(printf '%s\n' "$EFFECTIVE_PREFS" | jq -r --arg configured_host "$AGENT_HOST" '
  .host // $configured_host // ""
')

# Remote dispatch: forward non-local commands via SSH over Tailscale.
# VNC is excluded — it runs locally and connects to the remote host directly.
# Provision is excluded — it modifies the local agenix-secrets repo.
if [ -n "$EFFECTIVE_AGENT_HOST" ] && [ "$EFFECTIVE_AGENT_HOST" != "$THIS_HOST" ]; then
  if [ "$1" != "vnc" ] && [ "$1" != "provision" ]; then
    exec "$OPENSSH"/bin/ssh -t "$EFFECTIVE_AGENT_HOST" agentctl "$AGENT_NAME" "$@"
  fi
fi

CMD="$1"; shift

# Parse agentctl-level flags (consumed here, not passed to harness)
ROLE=""
EXTRA_ROLES=""
PROJECT=""
SANDBOX=""
LOCAL_MODEL=""
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role) ROLE="$2"; shift 2 ;;
    --roles) EXTRA_ROLES="$2"; shift 2 ;;
    -p|--project) PROJECT="$2"; shift 2 ;;
    --local)
      shift
      if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
        LOCAL_MODEL="$1"; shift
      else
        LOCAL_MODEL="default"
      fi
      ;;
    --sandbox) SANDBOX=1; shift ;;
    *) REMAINING_ARGS+=("$1"); shift ;;
  esac
done
set -- "${REMAINING_ARGS[@]}"

normalize_repo_url() {
  "$PROJECT_INDEX_HELPER" normalize-repo "$1"
}

resolve_repo_path() {
  local repo_id="$1"
  local repos_path="$HOME/repos/$repo_id"
  local legacy_keystone_path="$HOME/.keystone/repos/$repo_id"
  local code_path="$HOME/code/$repo_id"

  if [[ -d "$repos_path" ]]; then
    printf '%s\n' "$repos_path"
  elif [[ -d "$legacy_keystone_path" ]]; then
    printf '%s\n' "$legacy_keystone_path"
  elif [[ -d "$code_path" ]]; then
    printf '%s\n' "$code_path"
  fi
}

LOCAL_FLAG_ARGS=()
if [[ -n "$LOCAL_MODEL" ]]; then
  LOCAL_FLAG_ARGS+=(--local)
  if [[ "$LOCAL_MODEL" != "default" ]]; then
    LOCAL_FLAG_ARGS+=("$LOCAL_MODEL")
  fi
fi

TASK_LOOP_STATE_DIR_REL=".local/state/agent-task-loop/state"
TASK_LOOP_PAUSE_FILE_REL="${TASK_LOOP_STATE_DIR_REL}/paused"

case "$CMD" in
  pause)
    PAUSE_REASON="${*:-}"
    PAUSE_ACTOR="${SUDO_USER:-${USER:-unknown}}"
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -lc '
      state_dir="$HOME/'"$TASK_LOOP_STATE_DIR_REL"'"
      pause_file="$HOME/'"$TASK_LOOP_PAUSE_FILE_REL"'"
      reason="$1"
      actor="$2"

      mkdir -p "$state_dir"
      {
        printf "paused_at=%s\n" "$(date -Iseconds)"
        printf "paused_by=%s\n" "$actor"
        if [[ -n "$reason" ]]; then
          printf "reason=%s\n" "$reason"
        fi
      } > "$pause_file"
      echo "Paused task loop for '"$AGENT_NAME"'"
    ' -- "$PAUSE_REASON" "$PAUSE_ACTOR"
    ;;
  resume)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -lc '
      pause_file="$HOME/'"$TASK_LOOP_PAUSE_FILE_REL"'"
      if [[ -f "$pause_file" ]]; then
        rm -f "$pause_file"
        echo "Resumed task loop for '"$AGENT_NAME"'"
      else
        echo "Task loop for '"$AGENT_NAME"' is not paused"
      fi
    '
    ;;
  paused)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -lc '
      pause_file="$HOME/'"$TASK_LOOP_PAUSE_FILE_REL"'"
      if [[ ! -f "$pause_file" ]]; then
        echo "Task loop for '"$AGENT_NAME"': active"
        exit 0
      fi

      paused_at=$(sed -n "s/^paused_at=//p" "$pause_file" | tail -n1)
      paused_by=$(sed -n "s/^paused_by=//p" "$pause_file" | tail -n1)
      reason=$(sed -n "s/^reason=//p" "$pause_file" | tail -n1)

      echo "Task loop for '"$AGENT_NAME"': paused"
      if [[ -n "$paused_at" ]]; then
        echo "paused_at: $paused_at"
      fi
      if [[ -n "$paused_by" ]]; then
        echo "paused_by: $paused_by"
      fi
      if [[ -n "$reason" ]]; then
        echo "reason: $reason"
      fi
    '
    ;;
  tasks)
    AGENT_HOME="/home/agent-${AGENT_NAME}"
    TASKS_YAML=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec cat "$AGENT_HOME/TASKS.yaml" 2>/dev/null)
    if [ -z "$TASKS_YAML" ]; then
      echo "No TASKS.yaml found in $AGENT_HOME" >&2
      exit 1
    fi
    echo "$TASKS_YAML" | "$PYTHON3" "$TASKS_FORMATTER"
    ;;
  email)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec himalaya envelope list "$@"
    ;;
  shell)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -c "cd $NOTES_DIR && exec bash -l"
    ;;
  claude|gemini|codex|opencode)
    if [[ -n "$LOCAL_MODEL" ]]; then
      case "$CMD" in
        claude|opencode) ;;
        *)
          echo "Error: --local is only supported for 'claude' and 'opencode'." >&2
          echo "Received: $CMD" >&2
          exit 1
          ;;
      esac

      if [[ "$OLLAMA_ENABLED" != "true" ]]; then
        echo "Error: local model support is not enabled for agent '$AGENT_NAME'." >&2
        echo "Set keystone.terminal.ai.ollama.enable = true to use --local." >&2
        exit 1
      fi
    fi

    # --- Project + zellij session wrapping (all AI tools) ---
    if [ -n "$PROJECT" ]; then
      # Session slug is the first positional argument
      SESSION_SLUG="${1:-}"
      if [ -z "$SESSION_SLUG" ]; then
        echo "Usage: agentctl $AGENT_NAME $CMD --project <slug> <session-slug>" >&2
        echo "" >&2
        echo "Existing sessions for '$PROJECT':" >&2
        "$ZELLIJ" list-sessions -n 2>/dev/null | "$GNUGREP"/bin/grep "^${PROJECT}-" || echo "  (none)" >&2
        exit 1
      fi
      shift  # consume session slug

      PROJECT_JSON=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec \
        "$COREUTILS"/bin/env "NOTES_DIR=$NOTES_DIR" "$PROJECT_INDEX_HELPER" get "$PROJECT" 2>/dev/null || true)

      if [ -z "$PROJECT_JSON" ]; then
        echo "Error: project '$PROJECT' not found in zk project index" >&2
        echo "" >&2
        echo "Available projects:" >&2
        sudo -u "agent-${AGENT_NAME}" "$HELPER" exec \
          "$COREUTILS"/bin/env "NOTES_DIR=$NOTES_DIR" "$PROJECT_INDEX_HELPER" list 2>/dev/null \
          | jq -r '.projects[].slug' | "$GNUSED"/bin/sed 's/^/  /' >&2
        exit 1
      fi

      PROJECT_NAME=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.name // .slug')
      PROJECT_DESC=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.description // ""')
      PROJECT_PATH="/home/agent-${AGENT_NAME}"

      REPO_COUNT=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.repos | length')
      if [[ "$REPO_COUNT" == "1" ]]; then
        REPO_URL=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.repos[0]')
        REPO_ID=$(normalize_repo_url "$REPO_URL" 2>/dev/null || true)
        if [[ -n "$REPO_ID" ]]; then
          RESOLVED_REPO_PATH=$(resolve_repo_path "$REPO_ID" || true)
          if [[ -n "$RESOLVED_REPO_PATH" ]]; then
            PROJECT_PATH="$RESOLVED_REPO_PATH"
          fi
        fi
      fi

      SESSION_NAME="${PROJECT}-${SESSION_SLUG}"

      # Check if zellij session already exists → attach
      if "$ZELLIJ" list-sessions -s -n 2>/dev/null | "$GNUGREP"/bin/grep -q "^${SESSION_NAME}$"; then
        exec "$ZELLIJ" attach "$SESSION_NAME"
      fi

      # Create new zellij session, re-invoking self with env vars.
      # Env vars carry project context through zellij but are consumed before
      # sudo (no SETENV), so they're interpolated into the inner bash -c string.
      exec "$ZELLIJ" -s "$SESSION_NAME" -- \
        "$COREUTILS"/bin/env \
            "_AGENTCTL_PROJECT_PATH=$PROJECT_PATH" \
            "_AGENTCTL_PROJECT_NAME=$PROJECT_NAME" \
            "_AGENTCTL_PROJECT_DESC=$PROJECT_DESC" \
        agentctl "$AGENT_NAME" "$CMD" "${LOCAL_FLAG_ARGS[@]}" ${ROLE:+-r "$ROLE"} ${EXTRA_ROLES:+--roles "$EXTRA_ROLES"} "$@"
    fi

    # Determine working directory and project context (from zellij re-entry)
    # Default to agent home so queue files (TASKS.yaml etc.) are in CWD.
    WORK_DIR="/home/agent-${AGENT_NAME}"
    PROJECT_CONTEXT=""
    EFFECTIVE_PROVIDER=$(printf '%s\n' "$EFFECTIVE_PREFS" | jq -r '.provider // ""')
    EFFECTIVE_MODEL=$(printf '%s\n' "$EFFECTIVE_PREFS" | jq -r '.model // ""')
    EFFECTIVE_FALLBACK_MODEL=$(printf '%s\n' "$EFFECTIVE_PREFS" | jq -r '.fallback_model // ""')
    if [ -n "${_AGENTCTL_PROJECT_PATH:-}" ]; then
      WORK_DIR="$_AGENTCTL_PROJECT_PATH"
      PROJECT_CONTEXT="
# Project Context
**Project:** ${_AGENTCTL_PROJECT_NAME}
**Description:** ${_AGENTCTL_PROJECT_DESC}
**Working Directory:** ${_AGENTCTL_PROJECT_PATH}"
    fi

    # Run as the agent, direct execution by default (REQ-013 sandbox scope).
    # --sandbox opts into Podman containerization.
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -c '
      cd "'"$WORK_DIR"'"

      # Export project context as standard environment variables for all tools
      if [ -n "'"${_AGENTCTL_PROJECT_PATH:-}"'" ]; then
        export PROJECT_NAME="'"${_AGENTCTL_PROJECT_NAME:-}"'"
        export PROJECT_PATH="'"${_AGENTCTL_PROJECT_PATH:-}"'"
      fi

      # Resolve default execution flags per tool.
      # Respect explicit codex approval/sandbox flags provided by the caller.
      TOOL_FLAGS=""
      case "'"$CMD"'" in
        claude) TOOL_FLAGS="--dangerously-skip-permissions" ;;
        gemini) TOOL_FLAGS="--yolo" ;;
        codex)
          CODEX_HAS_EXECUTION_MODE=0
          for arg in "$@"; do
            case "$arg" in
              --full-auto|--dangerously-bypass-approvals-and-sandbox|--ask-for-approval|--ask-for-approval=*|--sandbox|--sandbox=*)
                CODEX_HAS_EXECUTION_MODE=1
                break
                ;;
            esac
          done
          if [ "$CODEX_HAS_EXECUTION_MODE" -eq 0 ]; then
            TOOL_FLAGS="--full-auto"
          fi
          ;;
      esac

      if { [ -z "$EFFECTIVE_PROVIDER" ] || [ "$EFFECTIVE_PROVIDER" = "'"$CMD"'" ]; } && [ -n "$EFFECTIVE_MODEL" ]; then
        case "'"$CMD"'" in
          claude) TOOL_FLAGS="$TOOL_FLAGS --model $EFFECTIVE_MODEL" ;;
          gemini) TOOL_FLAGS="$TOOL_FLAGS --model $EFFECTIVE_MODEL" ;;
          codex) TOOL_FLAGS="$TOOL_FLAGS --model $EFFECTIVE_MODEL" ;;
        esac
      fi

      if [ "'"$CMD"'" = "claude" ] && { [ -z "$EFFECTIVE_PROVIDER" ] || [ "$EFFECTIVE_PROVIDER" = "claude" ]; } && [ -n "$EFFECTIVE_FALLBACK_MODEL" ]; then
        export AGENTCTL_INTERACTIVE_FALLBACK_MODEL="$EFFECTIVE_FALLBACK_MODEL"
      fi

      LOCAL_MODEL="'"$LOCAL_MODEL"'"
      OLLAMA_ENABLED="'"$OLLAMA_ENABLED"'"
      OLLAMA_HOST="'"$OLLAMA_HOST"'"
      OLLAMA_DEFAULT_MODEL="'"$OLLAMA_DEFAULT_MODEL"'"
      RESOLVED_LOCAL_MODEL=""
      if [ -n "$LOCAL_MODEL" ]; then
        if [ "$OLLAMA_ENABLED" != "true" ]; then
          echo "Error: local model support is not enabled for agent '"$AGENT_NAME"'." >&2
          exit 1
        fi
        if [ -n "$LOCAL_MODEL" ] && [ "$LOCAL_MODEL" != "default" ]; then
          RESOLVED_LOCAL_MODEL="$LOCAL_MODEL"
        elif [ -n "$OLLAMA_DEFAULT_MODEL" ]; then
          RESOLVED_LOCAL_MODEL="$OLLAMA_DEFAULT_MODEL"
        else
          echo "Error: no local model was provided and no default model is configured for agent '"$AGENT_NAME"'." >&2
          exit 1
        fi
      fi

      # Compose system prompt from AGENTS.md layers + role + project context
      # (applies to all AI tools; injection mechanism is per-tool below)
      # Loading order (REQ-017.6):
      #   1. System-wide conventions — loaded natively by each tool from its
      #      instruction file (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md, etc.)
      #      Generated by conventions.nix. NOT injected via SP_FLAGS.
      #   2. Notes-dir AGENTS.md (agent identity: SOUL.md, TEAM.md, SERVICES.md)
      #   3. Project AGENTS.md (project-specific context)
      #   4. Role composition via --role/--roles (appended)
      SP=""

      # 2. Agent identity from notes directory
      NOTES_AGENTS_MD="'"$NOTES_DIR"'/AGENTS.md"
      if [ -f "$NOTES_AGENTS_MD" ]; then
        if [ -n "$SP" ]; then
          SP="$SP

$(cat "$NOTES_AGENTS_MD")"
        else
          SP="$(cat "$NOTES_AGENTS_MD")"
        fi
      fi

      # 3. Project-local AGENTS.md (if working in a project directory)
      if [ "'"$WORK_DIR"'" != "'"$NOTES_DIR"'" ] && [ -f AGENTS.md ]; then
        if [ -n "$SP" ]; then
          SP="$SP

$(cat AGENTS.md)"
        else
          SP="$(cat AGENTS.md)"
        fi
      fi

      # Append project context
      PROJECT_CTX="'"$PROJECT_CONTEXT"'"
      if [ -n "$PROJECT_CTX" ]; then
        if [ -n "$SP" ]; then
          SP="$SP$PROJECT_CTX"
        else
          SP="$PROJECT_CTX"
        fi
      fi

      ROLE="'"$ROLE"'"
      EXTRA_ROLES="'"$EXTRA_ROLES"'"
      if [ -n "$ROLE" ] || [ -n "$EXTRA_ROLES" ]; then
        if [ -x .agents/compose.sh ] && [ -f manifests/modes.yaml ]; then
          COMPOSE_EXTRA=""
          if [ -n "$EXTRA_ROLES" ]; then
            COMPOSE_EXTRA="--roles $EXTRA_ROLES"
          fi
          ROLE_PROMPT="$(PATH="'"$YQ_BIN"':$PATH" .agents/compose.sh manifests/modes.yaml "$ROLE" $COMPOSE_EXTRA)"
          if [ -n "$SP" ]; then
            SP="$SP

$ROLE_PROMPT"
          else
            SP="$ROLE_PROMPT"
          fi
        else
          echo "Warning: role/--roles requested but .agents/compose.sh or manifests/modes.yaml not found" >&2
        fi
      fi

      # Per-tool prompt injection using each tool'\''s native mechanism
      SP_FLAGS=()
      CODEX_MODEL_INSTRUCTIONS_FILE=""
      if [ -n "$SP" ]; then
        case "'"$CMD"'" in
          claude)
            SP_FLAGS=("--append-system-prompt" "$SP")
            ;;
          codex)
            # Codex CLI does not accept --instructions. Feed the composed
            # prompt through its supported model_instructions_file config key.
            CODEX_MODEL_INSTRUCTIONS_FILE="$(mktemp)"
            printf "%s\n" "$SP" > "$CODEX_MODEL_INSTRUCTIONS_FILE"
            SP_FLAGS=("-c" "model_instructions_file=\"$CODEX_MODEL_INSTRUCTIONS_FILE\"")
            ;;
          opencode)
            # opencode reads AGENTS.md natively from the working directory
            ;;
        esac
      fi

      if [ -n "$LOCAL_MODEL" ]; then
        case "'"$CMD"'" in
          claude)
            export ANTHROPIC_BASE_URL="$OLLAMA_HOST"
            export ANTHROPIC_AUTH_TOKEN="ollama"
            TOOL_FLAGS="$TOOL_FLAGS --model $RESOLVED_LOCAL_MODEL"
            ;;
          opencode)
            export OPENCODE_PROVIDER="ollama"
            export OPENCODE_MODEL="$RESOLVED_LOCAL_MODEL"
            export OLLAMA_HOST="$OLLAMA_HOST"
            ;;
        esac
      fi

      if [ -n "'"$SANDBOX"'" ]; then
        # --sandbox: opt-in Podman sandboxing for interactive sessions.
        # podman-agent adds auto-approve flags and handles mounts, SSH, cache volumes.
        if [ "'"$CMD"'" = "codex" ] && [ -n "$CODEX_MODEL_INSTRUCTIONS_FILE" ]; then
          "'"$PODMAN_AGENT"'" "'"$CMD"'" "${SP_FLAGS[@]}" "$@"
          status=$?
          rm -f "$CODEX_MODEL_INSTRUCTIONS_FILE"
          exit $status
        fi
        exec "'"$PODMAN_AGENT"'" "'"$CMD"'" "${SP_FLAGS[@]}" "$@"
      else
        # Default: direct execution as the agent user (REQ-013 sandbox scope).
        # Interactive agentctl sessions run without Podman since the human
        # operator is present and agents have OS-level user isolation.
        if [ -f flake.nix ]; then
          FLAKE_REF="."
          if [ -f .gitmodules ]; then
            FLAKE_REF="git+file:.?submodules=1"
          fi
          if [ "'"$CMD"'" = "codex" ] && [ -n "$CODEX_MODEL_INSTRUCTIONS_FILE" ]; then
            nix develop "$FLAKE_REF" --no-update-lock-file --accept-flake-config \
              --command "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
            status=$?
            rm -f "$CODEX_MODEL_INSTRUCTIONS_FILE"
            exit $status
          fi
          exec nix develop "$FLAKE_REF" --no-update-lock-file --accept-flake-config \
            --command "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
        else
          if [ "'"$CMD"'" = "codex" ] && [ -n "$CODEX_MODEL_INSTRUCTIONS_FILE" ]; then
            "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
            status=$?
            rm -f "$CODEX_MODEL_INSTRUCTIONS_FILE"
            exit $status
          fi
          exec "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
        fi
      fi
    ' -- "$@"
    ;;
  mail)
    exec agent-mail "$@" --to "${AGENT_NAME}@${TOP_DOMAIN}"
    ;;
  provision)
    # Resolve provision metadata (compiled-in)
    PROVISION_AGENT_HOST=""
    MAIL_PROVISION=false
    set_agent_provision "$AGENT_NAME"

    # Parse flags
    SKIP_REKEY=false
    for arg in "$@"; do
      case "$arg" in
        --skip-rekey) SKIP_REKEY=true ;;
        *) echo "Error: unknown provision flag '$arg'" >&2; exit 1 ;;
      esac
    done

    USERNAME="agent-${AGENT_NAME}"

    # Find secrets directory — read from the system flake pointer file.
    _system_flake=""
    if [ -r /run/current-system/keystone-system-flake ]; then
      _system_flake="$(tr -d '\n' < /run/current-system/keystone-system-flake 2>/dev/null || true)"
    fi
    if [ -z "$_system_flake" ]; then
      echo "Error: /run/current-system/keystone-system-flake not found." >&2
      echo "Ensure keystone.systemFlake.path is set in your NixOS config." >&2
      exit 1
    fi
    SECRETS_DIR="$_system_flake/agenix-secrets"
    if [ ! -d "$SECRETS_DIR" ]; then
      echo "Error: secrets directory not found: $SECRETS_DIR" >&2
      exit 1
    fi

    TMPDIR=$("$COREUTILS"/bin/mktemp -d)
    trap '"$COREUTILS"/bin/rm -rf "$TMPDIR"' EXIT

    echo "==> Provisioning secrets for $USERNAME"

    # --- Step 1: Generate SSH keypair ---
    SSH_KEY="$TMPDIR/ssh-key"
    SSH_PASSPHRASE=$("$OPENSSL"/bin/openssl rand -base64 32)
    echo -n "$SSH_PASSPHRASE" > "$TMPDIR/ssh-passphrase"
    "$OPENSSH"/bin/ssh-keygen -t ed25519 -C "$USERNAME" \
      -f "$SSH_KEY" -N "$SSH_PASSPHRASE" -q
    echo "==> Generated SSH keypair"
    echo "    Public key: $(cat "$SSH_KEY.pub")"

    # --- Step 2: Generate mail password (if mail.provision) ---
    if [ "$MAIL_PROVISION" = "true" ]; then
      MAIL_PASSWORD=$("$OPENSSL"/bin/openssl rand -base64 24)
      echo -n "$MAIL_PASSWORD" > "$TMPDIR/mail-password"
      echo "==> Generated mail password"
    fi

    # --- Step 2b: Generate Bitwarden/Vaultwarden password ---
    BW_PASSWORD=$("$OPENSSL"/bin/openssl rand -base64 24)
    echo -n "$BW_PASSWORD" > "$TMPDIR/bitwarden-password"
    echo "==> Generated Bitwarden password"

    # --- Step 3: Insert entries into secrets.nix ---
    SECRETS_NIX="$SECRETS_DIR/secrets.nix"
    if [ ! -f "$SECRETS_NIX" ]; then
      echo "Error: $SECRETS_NIX not found" >&2
      exit 1
    fi

    # Helper: add entry before the final closing brace if not already present
    add_secret() {
      local SECRET_NAME="$1"
      local RECIPIENTS="$2"
      if "$GNUGREP"/bin/grep -q "\"$SECRET_NAME\"" "$SECRETS_NIX"; then
        echo "    $SECRET_NAME already exists in secrets.nix, skipping"
      else
        # Insert before the last closing brace
        "$GNUSED"/bin/sed -i "/^}$/i\\\\  \"$SECRET_NAME\".publicKeys = $RECIPIENTS;" "$SECRETS_NIX"
        echo "    Added $SECRET_NAME to secrets.nix"
      fi
    }

    # Determine recipient expression pieces
    # Agent host system key (for himalaya client / ssh-agent)
    AGENT_HOST_EXPR="systems.${PROVISION_AGENT_HOST}"
    # Mail server host system key (for Stalwart provisioning)
    MAIL_HOST_EXPR=""
    if [ -n "$MAIL_HOST" ] && [ "$MAIL_HOST" != "$PROVISION_AGENT_HOST" ]; then
      MAIL_HOST_EXPR="systems.${MAIL_HOST}"
    fi

    # SSH key secret: needs admin keys + agent's host
    add_secret "secrets/$USERNAME-ssh-key.age" \
      "adminKeys ++ [ $AGENT_HOST_EXPR ]"

    # SSH passphrase: same recipients as SSH key
    add_secret "secrets/$USERNAME-ssh-passphrase.age" \
      "adminKeys ++ [ $AGENT_HOST_EXPR ]"

    # Mail password: needs admin keys + agent's host + mail server host
    if [ "$MAIL_PROVISION" = "true" ]; then
      if [ -n "$MAIL_HOST_EXPR" ]; then
        add_secret "secrets/$USERNAME-mail-password.age" \
          "adminKeys ++ [ $AGENT_HOST_EXPR $MAIL_HOST_EXPR ]"
      else
        add_secret "secrets/$USERNAME-mail-password.age" \
          "adminKeys ++ [ $AGENT_HOST_EXPR ]"
      fi
    fi

    # Bitwarden password: needs admin keys + agent's host
    add_secret "secrets/$USERNAME-bitwarden-password.age" \
      "adminKeys ++ [ $AGENT_HOST_EXPR ]"

    # --- Step 4: Validate secrets.nix ---
    echo "==> Validating secrets.nix..."
    if ! "$NIX"/bin/nix eval --file "$SECRETS_NIX" --json > /dev/null 2>&1; then
      echo "Error: secrets.nix is invalid after modification!" >&2
      echo "Please fix manually: $SECRETS_NIX" >&2
      exit 1
    fi
    echo "    secrets.nix is valid"

    # --- Step 5: Create .age files ---
    echo "==> Creating .age secret files..."
    cd "$SECRETS_DIR"

    create_age_secret() {
      local SECRET_PATH="$1"
      local VALUE_FILE="$2"
      if [ -f "$SECRET_PATH" ]; then
        echo "    $SECRET_PATH already exists, skipping"
      else
        EDITOR="cp $VALUE_FILE" agenix -e "$SECRET_PATH"
        echo "    Created $SECRET_PATH"
      fi
    }

    create_age_secret "secrets/$USERNAME-ssh-key.age" "$SSH_KEY"
    create_age_secret "secrets/$USERNAME-ssh-passphrase.age" "$TMPDIR/ssh-passphrase"
    if [ "$MAIL_PROVISION" = "true" ]; then
      create_age_secret "secrets/$USERNAME-mail-password.age" "$TMPDIR/mail-password"
    fi
    create_age_secret "secrets/$USERNAME-bitwarden-password.age" "$TMPDIR/bitwarden-password"

    # --- Step 6: Print snippets for nixos-config ---
    echo ""
    echo "==> SSH public key (add to keystone.keys in modules/keystone.nix):"
    echo "    keystone.keys.\"$USERNAME\".hosts.<hostname>.publicKey = \"$(cat "$SSH_KEY.pub")\";"
    echo ""
    echo "==> Agenix declarations (add to host config):"
    echo "    age.secrets.$USERNAME-ssh-key = {"
    echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-ssh-key.age\";"
    echo "      owner = \"$USERNAME\";"
    echo "      mode = \"0400\";"
    echo "    };"
    echo "    age.secrets.$USERNAME-ssh-passphrase = {"
    echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-ssh-passphrase.age\";"
    echo "      owner = \"$USERNAME\";"
    echo "      mode = \"0400\";"
    echo "    };"
    if [ "$MAIL_PROVISION" = "true" ]; then
      echo "    age.secrets.$USERNAME-mail-password = {"
      echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-mail-password.age\";"
      echo "      owner = \"$USERNAME\";"
      echo "      mode = \"0400\";"
      echo "    };"
    fi
    echo "    age.secrets.$USERNAME-bitwarden-password = {"
    echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-bitwarden-password.age\";"
    echo "      owner = \"$USERNAME\";"
    echo "      mode = \"0400\";"
    echo "    };"

    # --- Step 7: hwrekey (unless --skip-rekey) ---
    if [ "$SKIP_REKEY" = "true" ]; then
      echo ""
      echo "==> Skipping hwrekey (--skip-rekey). Run manually:"
      echo "    hwrekey -m \"provision: create $USERNAME secrets\""
    else
      echo ""
      echo "==> Running hwrekey..."
      hwrekey -m "provision: create $USERNAME secrets"
    fi

    echo ""
    echo "==> Provisioning complete for $USERNAME"
    ;;
  vnc)
    if [ -z "$VNC_PORT" ]; then
      echo "Error: agent '$AGENT_NAME' has no desktop (VNC not available)" >&2
      exit 1
    fi
    # Use agent's host for remote agents, localhost for local ones
    VNC_HOST="localhost"
    if [ -n "$AGENT_HOST" ] && [ "$AGENT_HOST" != "$THIS_HOST" ]; then
      VNC_HOST="$AGENT_HOST"
    fi
    exec "$VIRT_VIEWER"/bin/remote-viewer "vnc://$VNC_HOST:$VNC_PORT" "$@"
    ;;
  logs|journalctl)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" journalctl -e "$@"
    ;;
  cron)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" list-timers "$@"
    ;;
  *)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" "$CMD" "$@"
    ;;
esac
