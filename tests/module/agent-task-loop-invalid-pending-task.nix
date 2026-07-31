{
  pkgs,
  lib,
}:
let
  emptyProjectIndexFixture = ../fixtures/task-loop/project-index-empty.json;
  defaultsJson = builtins.toJSON {
    profile = null;
    provider = "claude";
    model = null;
    fallbackModel = null;
    effort = null;
  };
  stageJson = builtins.toJSON {
    profile = null;
    provider = null;
    model = null;
    fallbackModel = null;
    effort = null;
  };
  profilesJson = builtins.toJSON {
    fast = {
      claude = {
        effort = "low";
        fallbackModel = "sonnet";
        model = "haiku";
      };
    };
    medium = {
      claude = {
        effort = "medium";
        fallbackModel = "opus";
        model = "sonnet";
      };
    };
  };
  projectIndexHelper = pkgs.writeShellScriptBin "keystone-project-index" ''
    cat ${emptyProjectIndexFixture}
  '';
  notesDir = "/tmp/task-loop-invalid-pending-notes";
  taskLoopScript = pkgs.replaceVars ../../modules/os/agents/scripts/task-loop.sh {
    notesDir = notesDir;
    maxTasks = "1";
    agentName = "test";
    githubUsername = "";
    forgejoUsername = "";
    defaultsJson = defaultsJson;
    ingestJson = stageJson;
    prioritizeJson = stageJson;
    executeJson = stageJson;
    profilesJson = profilesJson;
    projectIndexHelper = projectIndexHelper;
  };
in
pkgs.runCommand "test-agent-task-loop-invalid-pending-task"
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

        mkdir -p "$HOME" "$TASK_LOOP_TEST_STATE_DIR" "$PWD/stubs" ${notesDir}

        cat > ${notesDir}/TASKS.yaml <<'EOF'
    tasks:
      - name: ""
        description: "Malformed pending task"
        status: pending
        source: email
        source_ref: "email-empty-name@test"
      - name: "reply-pong-to-test"
        description: "Reply with pong to the ping email from test@ncrmro.com"
        status: pending
        source: email
        source_ref: "email-1-test@ncrmro.com"
    EOF

        mkdir -p ${notesDir}/.deepwork

        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/systemctl"
        chmod +x "$PWD/stubs/systemctl"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/git"
        chmod +x "$PWD/stubs/git"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' \"test-host\"" > "$PWD/stubs/hostname"
        chmod +x "$PWD/stubs/hostname"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\\n" "[]"' > "$PWD/stubs/fetch-email-source"
        chmod +x "$PWD/stubs/fetch-email-source"

        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\\n" "[]"' > "$PWD/stubs/calendula"
        chmod +x "$PWD/stubs/calendula"

        cat > "$PWD/stubs/claude" <<'STUBEOF'
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        args="$*"
        state_dir="''${TASK_LOOP_TEST_STATE_DIR:?}"

        if printf '%s' "$args" | grep -q "task_loop prioritize"; then
          printf '%s\n' "1" > "$state_dir/prioritize-count"
        else
          printf '%s\n' "1" > "$state_dir/execute-count"
          printf '%s\n' "$args" > "$state_dir/execute-args"
        fi

        printf '%s\n' '{"total_tokens":1}'
        STUBEOF
        chmod +x "$PWD/stubs/claude"

        bash "${taskLoopScript}"

        invalid_status="$(yq '[.tasks[] | select(.source_ref == "email-empty-name@test")] | .[0].status' ${notesDir}/TASKS.yaml)"
        if [[ "$invalid_status" != "error" ]]; then
          echo "FAIL: invalid pending task status is '$invalid_status', expected 'error'" >&2
          cat ${notesDir}/TASKS.yaml >&2
          exit 1
        fi
        echo "PASS: invalid pending task marked error"

        valid_status="$(yq '[.tasks[] | select(.source_ref == "email-1-test@ncrmro.com")] | .[0].status' ${notesDir}/TASKS.yaml)"
        if [[ "$valid_status" != "completed" ]]; then
          echo "FAIL: valid pending task status is '$valid_status', expected 'completed'" >&2
          cat ${notesDir}/TASKS.yaml >&2
          exit 1
        fi
        echo "PASS: valid pending task completed"

        if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/execute-count" ]]; then
          echo "FAIL: execute stage was not invoked" >&2
          exit 1
        fi
        echo "PASS: execute stage invoked"

        execute_args="$(cat "$TASK_LOOP_TEST_STATE_DIR/execute-args")"
        if ! printf '%s' "$execute_args" | grep -qi "reply-pong-to-test"; then
          echo "FAIL: execute stage did not receive the valid task name" >&2
          echo "  execute args: $execute_args" >&2
          exit 1
        fi
        echo "PASS: execute received valid task name"

        touch "$out"
  ''
