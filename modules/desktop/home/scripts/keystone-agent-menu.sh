#!/usr/bin/env bash
# keystone-agent-menu — Alt+Escape agent control surface.

set -euo pipefail

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

prompt_input() {
  local placeholder="$1"
  printf '\n' \
    | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "$placeholder" 2>/dev/null \
    | tr -d '\r'
}

reopen_agents_menu() {
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-agents -p "Agents" >/dev/null 2>&1 &
}

cmd_agents_json() {
  if ! command -v agentctl >/dev/null 2>&1; then
    printf '[{"Text":"No agents configured","Subtext":"Enable keystone.os.agents to manage agents from this menu","Value":"","Icon":"dialog-information-symbolic"}]\n'
    return 0
  fi
  agentctl list --json | jq '
    map({
      Text: .agent,
      Subtext: (
        [
          (.preferredHost // .configuredHost // "unassigned"),
          (.pause.state // "active"),
          (
            if (.provider // "") != "" then
              .provider + (if (.model // "") != "" then "/" + .model else "" end)
            else
              "defaults"
            end
          )
        ] | join(" · ")
      ),
      Value: .agent,
      Icon: "computer-symbolic",
      SubMenu: "keystone-agent-actions",
      Preview: ("agentctl show " + (.agent | @sh) + " --json | jq -r '\''\"Agent: \\(.agent)\\nPreferred host: \\(.preferredHost // .configuredHost // \"\")\\nPause: \\(.pause.state)\\nProvider: \\(.provider // \"\")\\nModel: \\(.model // \"\")\\nFallback: \\(.fallbackModel // \"\")\"'\''"),
      PreviewType: "command"
    })
  '
}

cmd_agent_actions_json() {
  if ! command -v agentctl >/dev/null 2>&1; then
    printf '[]\n'
    return 0
  fi
  local agent_name="$1"
  local quoted_agent
  local state_json
  local preferred_host
  local pause_state
  local provider
  local launch_provider
  local model
  local fallback_model

  quoted_agent=$(shell_quote "$agent_name")
  state_json=$(agentctl show "$agent_name" --json)
  preferred_host=$(printf '%s\n' "$state_json" | jq -r '.preferredHost // .configuredHost // ""')
  pause_state=$(printf '%s\n' "$state_json" | jq -r '.pause.state // "active"')
  provider=$(printf '%s\n' "$state_json" | jq -r '.provider // ""')
  launch_provider="${provider:-codex}"
  if [[ -z "$launch_provider" ]]; then
    launch_provider="codex"
  fi
  model=$(printf '%s\n' "$state_json" | jq -r '.model // ""')
  fallback_model=$(printf '%s\n' "$state_json" | jq -r '.fallbackModel // ""')

  jq -cn \
    --arg agent "$agent_name" \
    --arg quoted "$quoted_agent" \
    --arg preferred_host "$preferred_host" \
    --arg pause_state "$pause_state" \
    --arg provider "$provider" \
    --arg launch_provider "$launch_provider" \
    --arg model "$model" \
    --arg fallback_model "$fallback_model" '
      [
        {
          Text: "Open interactive session",
          Subtext: ("Launch " + $launch_provider + " with the effective interactive defaults"),
          Value: ("open-interactive\t" + $agent + "\t" + $launch_provider),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Agent: \\(.agent)\\nPreferred host: \\(.preferredHost // .configuredHost // \"\")\"'\''"),
          PreviewType: "command"
        },
        {
          Text: (if $pause_state == "paused" then "Resume task loop" else "Pause task loop" end),
          Subtext: ("Current state: " + $pause_state),
          Value: ((if $pause_state == "paused" then "resume" else "pause" end) + "\t" + $agent),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Pause: \\(.pause.state)\\nReason: \\(.pause.reason // \"\")\"'\''"),
          PreviewType: "command"
        },
        {
          Text: "Preferred host",
          Subtext: (if $preferred_host == "" then "unset" else $preferred_host end),
          Value: ("set-host-menu\t" + $agent),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Preferred host: \\(.preferredHost // .configuredHost // \"\")\"'\''"),
          PreviewType: "command"
        },
        {
          Text: "Provider",
          Subtext: (if $provider == "" then "unset" else $provider end),
          Value: ("set-provider-menu\t" + $agent),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Provider: \\(.provider // \"\")\"'\''"),
          PreviewType: "command"
        },
        {
          Text: "Model",
          Subtext: (if $model == "" then "unset" else $model end),
          Value: ("set-model-menu\t" + $agent),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Model: \\(.model // \"\")\"'\''"),
          PreviewType: "command"
        },
        {
          Text: "Fallback model",
          Subtext: (if $fallback_model == "" then "unset" else $fallback_model end),
          Value: ("set-fallback-menu\t" + $agent),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Fallback: \\(.fallbackModel // \"\")\"'\''"),
          PreviewType: "command"
        },
        {
          Text: "Clear interactive defaults",
          Subtext: "Remove host and model overrides for this agent",
          Value: ("clear-prefs\t" + $agent),
          Preview: ("agentctl show " + $quoted + " --json | jq -r '\''\"Provider: \\(.provider // \"\")\\nModel: \\(.model // \"\")\\nFallback: \\(.fallbackModel // \"\")\"'\''"),
          PreviewType: "command"
        }
      ]
    '
}

cmd_dispatch() {
  if ! command -v agentctl >/dev/null 2>&1; then
    return 0
  fi
  local payload="${1:-}"
  local action=""
  local agent_name=""
  local value=""
  local current=""
  local host=""
  local provider=""
  local model=""
  local fallback=""
  local args=()

  IFS=$'\t' read -r action agent_name value <<<"$payload"

  case "$action" in
    open-interactive)
      if [[ -z "$value" ]]; then
        value=$(agentctl show "$agent_name" --json | jq -r '.provider // "codex"')
      fi
      if [[ -z "$value" ]]; then
        value="codex"
      fi
      "$(keystone_cmd keystone-detach)" ghostty -e agentctl "$agent_name" "$value"
      ;;
    pause)
      agentctl "$agent_name" pause "paused from keystone agent menu" >/dev/null
      reopen_agents_menu
      ;;
    resume)
      agentctl "$agent_name" resume >/dev/null
      reopen_agents_menu
      ;;
    set-host-menu)
      value=$(
        agentctl list --json | jq -r '[.[].configuredHost] | unique | .[] | select(. != "")' \
          | "$(keystone_cmd keystone-launch-walker)" --dmenu --placeholder "Preferred host" 2>/dev/null \
          | tr -d '\r'
      ) || true
      if [[ -z "$value" || "$value" == "CNCLD" ]]; then
        reopen_agents_menu
        return 0
      fi
      agentctl prefs set "$agent_name" --host "$value" >/dev/null
      reopen_agents_menu
      ;;
    set-provider-menu)
      value=$(
        printf 'claude\ngemini\ncodex\n' \
          | "$(keystone_cmd keystone-launch-walker)" --dmenu --placeholder "Provider" 2>/dev/null \
          | tr -d '\r'
      ) || true
      if [[ -z "$value" || "$value" == "CNCLD" ]]; then
        reopen_agents_menu
        return 0
      fi
      current=$(agentctl show "$agent_name" --json)
      host=$(printf '%s\n' "$current" | jq -r '.preferredHost // .configuredHost // ""')
      model=$(printf '%s\n' "$current" | jq -r '.model // ""')
      fallback=$(printf '%s\n' "$current" | jq -r '.fallbackModel // ""')
      args=(prefs set "$agent_name" --host "$host" --provider "$value" --model "$model")
      if [[ -n "$fallback" ]]; then
        args+=(--fallback-model "$fallback")
      fi
      agentctl "${args[@]}" >/dev/null
      reopen_agents_menu
      ;;
    set-model-menu)
      value=$(prompt_input "Model") || true
      if [[ "$value" == "CNCLD" ]]; then
        reopen_agents_menu
        return 0
      fi
      current=$(agentctl show "$agent_name" --json)
      host=$(printf '%s\n' "$current" | jq -r '.preferredHost // .configuredHost // ""')
      provider=$(printf '%s\n' "$current" | jq -r '.provider // "claude"')
      fallback=$(printf '%s\n' "$current" | jq -r '.fallbackModel // ""')
      args=(prefs set "$agent_name" --host "$host" --provider "$provider" --model "$value")
      if [[ -n "$fallback" ]]; then
        args+=(--fallback-model "$fallback")
      fi
      agentctl "${args[@]}" >/dev/null
      reopen_agents_menu
      ;;
    set-fallback-menu)
      value=$(prompt_input "Fallback model") || true
      if [[ "$value" == "CNCLD" ]]; then
        reopen_agents_menu
        return 0
      fi
      current=$(agentctl show "$agent_name" --json)
      host=$(printf '%s\n' "$current" | jq -r '.preferredHost // .configuredHost // ""')
      provider=$(printf '%s\n' "$current" | jq -r '.provider // "claude"')
      model=$(printf '%s\n' "$current" | jq -r '.model // ""')
      agentctl prefs set "$agent_name" --host "$host" --provider "$provider" --model "$model" --fallback-model "$value" >/dev/null
      reopen_agents_menu
      ;;
    clear-prefs)
      agentctl prefs clear "$agent_name" >/dev/null
      reopen_agents_menu
      ;;
    *)
      echo "Unknown agent action: $action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  agents-json)
    shift
    cmd_agents_json "$@"
    ;;
  agent-actions-json)
    shift
    cmd_agent_actions_json "$@"
    ;;
  dispatch)
    shift
    cmd_dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-agent-menu {agents-json|agent-actions-json|dispatch} ..." >&2
    exit 1
    ;;
esac
