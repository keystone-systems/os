{
  pkgs,
  lib,
}:
let
  calendulaEventsFixture = ../fixtures/task-loop/calendula-events.json;
  emptyProjectIndexFixture = ../fixtures/task-loop/project-index-empty.json;
  defaultsJson = builtins.toJSON {
    profile = "";
    provider = "";
    model = "";
    fallbackModel = "";
    effort = "";
  };
  profilesJson = builtins.toJSON {
    fast = {
      claude = { };
    };
    medium = {
      claude = { };
    };
  };
  projectIndexHelper = pkgs.writeShellScriptBin "keystone-project-index" ''
    cat ${emptyProjectIndexFixture}
  '';
  taskLoopScript = pkgs.replaceVars ../../modules/os/agents/scripts/task-loop.sh {
    notesDir = "/tmp/task-loop-hash-regression-notes";
    maxTasks = "1";
    agentName = "test";
    githubUsername = "";
    forgejoUsername = "";
    defaultsJson = defaultsJson;
    ingestJson = defaultsJson;
    prioritizeJson = defaultsJson;
    executeJson = defaultsJson;
    profilesJson = profilesJson;
    projectIndexHelper = projectIndexHelper;
  };
in
pkgs.runCommand "test-agent-task-loop-hash-regression"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      jq
      util-linux
      yq-go
    ];
  }
  ''
        set -euo pipefail

        export HOME="$PWD/home"
        export TASK_LOOP_TEST_STATE_DIR="$PWD/state"
        export PATH="$PWD/stubs:${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.util-linux
            pkgs.yq-go
          ]
        }"

        mkdir -p "$HOME" "$TASK_LOOP_TEST_STATE_DIR" "$PWD/stubs" /tmp/task-loop-hash-regression-notes

        # Queue files live in $HOME (agent home), not the notes dir
        printf '%s\n' 'tasks: []' > "$HOME/TASKS.yaml"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/systemctl"
        chmod +x "$PWD/stubs/systemctl"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/git"
        chmod +x "$PWD/stubs/git"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' \"test-host\"" > "$PWD/stubs/hostname"
        chmod +x "$PWD/stubs/hostname"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${calendulaEventsFixture}" > "$PWD/stubs/calendula"
        chmod +x "$PWD/stubs/calendula"

        cat > "$PWD/stubs/claude" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    args="$*"
    state_dir="''${TASK_LOOP_TEST_STATE_DIR:?}"

    if printf '%s' "$args" | grep -q "task_loop ingest"; then
      count_file="$state_dir/ingest-count"
      count=0
      if [[ -f "$count_file" ]]; then
        count=$(cat "$count_file")
      fi
      printf '%s\n' "$((count + 1))" > "$count_file"
      printf '%s\n' 'tasks: []' > TASKS.yaml
    elif printf '%s' "$args" | grep -q "task_loop prioritize"; then
      count_file="$state_dir/prioritize-count"
      count=0
      if [[ -f "$count_file" ]]; then
        count=$(cat "$count_file")
      fi
      printf '%s\n' "$((count + 1))" > "$count_file"
    else
      printf '%s\n' "unexpected claude args: $args" >&2
      exit 1
    fi

    printf '%s\n' '{"total_tokens":1}'
    EOF
        chmod +x "$PWD/stubs/claude"

        bash "${taskLoopScript}"
        bash "${taskLoopScript}"

        ingest_count="$(cat "$TASK_LOOP_TEST_STATE_DIR/ingest-count")"
        prioritize_count="$(cat "$TASK_LOOP_TEST_STATE_DIR/prioritize-count")"

        if [[ "$ingest_count" != "1" ]]; then
          echo "expected ingest to run once, got $ingest_count" >&2
          exit 1
        fi

        if [[ "$prioritize_count" != "1" ]]; then
          echo "expected prioritize to run once, got $prioritize_count" >&2
          exit 1
        fi

        touch "$out"
  ''
