{ pkgs }:
pkgs.runCommand "test-agentctl-regression"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gnugrep
      jq
      gnused
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export PATH="$PWD/bin:${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
      ]
    }"

    mkdir -p "$HOME" "$PWD/bin" "$PWD/logs"

    cat > "$PWD/bin/agentctl" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/os/agents/scripts/agentctl.sh" "$@"
    EOF
    chmod +x "$PWD/bin/agentctl"

    cat > "$PWD/bin/fake-project-prefs" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    state_file="$PWD/launcher-state.json"
    if [[ ! -f "$state_file" ]]; then
      cat > "$state_file" <<'JSON'
    {
      "interactive_defaults": {
        "agents": {},
        "projects": {}
      }
    }
    JSON
    fi

    cmd="''${1:-}"
    shift || true

    case "$cmd" in
      launcher-state-json)
        cat "$state_file"
        ;;
      project-launch-json)
        project_slug="''${1:-}"
        jq -cn --arg project "$project_slug" '
          {
            project: $project,
            provider: "",
            model: "",
            fallbackModel: ""
          }
        '
        ;;
      agent-set-pref)
        agent_name="''${1:-}"
        host="''${2:-}"
        provider="''${3:-}"
        model="''${4:-}"
        fallback="''${5:-}"
        tmp="$state_file.tmp"
        jq \
          --arg agent "$agent_name" \
          --arg host "$host" \
          --arg provider "$provider" \
          --arg model "$model" \
          --arg fallback_model "$fallback" \
          '
            .interactive_defaults.agents[$agent] = {
              host: $host,
              provider: $provider,
              model: $model,
              fallback_model: $fallback_model
            }
          ' "$state_file" > "$tmp"
        mv "$tmp" "$state_file"
        ;;
      agent-clear-pref)
        agent_name="''${1:-}"
        tmp="$state_file.tmp"
        jq --arg agent "$agent_name" 'del(.interactive_defaults.agents[$agent])' "$state_file" > "$tmp"
        mv "$tmp" "$state_file"
        ;;
      *)
        printf 'unexpected fake-project-prefs command: %s\n' "$cmd" >&2
        exit 1
        ;;
    esac
    EOF
    chmod +x "$PWD/bin/fake-project-prefs"

    cat > "$PWD/bin/helper" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exit 0
    EOF
    chmod +x "$PWD/bin/helper"

    cat > "$PWD/bin/project-index-helper" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "''${2:-}"
    EOF
    chmod +x "$PWD/bin/project-index-helper"

    cat > "$PWD/agentctl.env" <<'EOF'
    KNOWN_AGENTS="drago,luce"
    PROJECT_PREFS="$PWD/bin/fake-project-prefs"
    OPENSSH="${pkgs.openssh}"
    PROJECT_INDEX_HELPER="$PWD/bin/project-index-helper"
    HELPER="$PWD/bin/helper"
    NOTES_DIR="$HOME/notes"
    PYTHON3="${pkgs.python3}/bin/python3"
    TASKS_FORMATTER="$PWD/bin/tasks-formatter"

    set_agent_helper() {
      case "$1" in
        drago|luce) return 0 ;;
        *) echo "Unknown agent: $1" >&2; return 1 ;;
      esac
    }

    set_agent_notes_dir() {
      NOTES_DIR="$HOME/notes/$1"
      export NOTES_DIR
    }

    set_agent_vnc_port() {
      case "$1" in
        drago) VNC_PORT="5901" ;;
        luce) VNC_PORT="" ;;
      esac
      export VNC_PORT
    }

    set_agent_host() {
      case "$1" in
        drago) AGENT_HOST="workstation" ;;
        luce) AGENT_HOST="remote" ;;
      esac
      export AGENT_HOST
    }

    set_agent_ollama() {
      OLLAMA_ENABLED="false"
      OLLAMA_HOST="http://localhost:11434"
      OLLAMA_DEFAULT_MODEL=""
      export OLLAMA_ENABLED OLLAMA_HOST OLLAMA_DEFAULT_MODEL
    }
    EOF

    export AGENTCTL_ENV_FILE="$PWD/agentctl.env"

    list_json="$(agentctl list --json)"
    printf '%s\n' "$list_json" | jq -e '
      length == 2
      and any(.[]; .agent == "drago" and .configuredHost == "workstation" and .vncPort == 5901)
      and any(.[]; .agent == "luce" and .configuredHost == "remote" and .vncPort == null)
    ' >/dev/null

    show_json="$(agentctl show drago --json)"
    printf '%s\n' "$show_json" | jq -e '
      .agent == "drago"
      and .configuredHost == "workstation"
      and .preferredHost == "workstation"
      and .pause.state == "active"
    ' >/dev/null

    initial_prefs="$(agentctl prefs get drago)"
    printf '%s\n' "$initial_prefs" | jq -e '
      .host == "workstation"
      and .provider == ""
      and .model == ""
      and .fallback_model == ""
    ' >/dev/null

    agentctl prefs set drago --host remote --provider openai --model gpt-5.4 --fallback-model gpt-5.4-mini

    updated_prefs="$(agentctl prefs get drago)"
    printf '%s\n' "$updated_prefs" | jq -e '
      .host == "remote"
      and .provider == "openai"
      and .model == "gpt-5.4"
      and .fallback_model == "gpt-5.4-mini"
    ' >/dev/null

    agentctl prefs clear drago

    cleared_prefs="$(agentctl prefs get drago)"
    printf '%s\n' "$cleared_prefs" | jq -e '
      .host == "workstation"
      and .provider == ""
      and .model == ""
      and .fallback_model == ""
    ' >/dev/null

    touch "$out"
  ''
