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
    ingestPrompt = pkgs.writeText "test-task-loop-ingest.md" (
      builtins.readFile ../../modules/os/agents/prompts/task-loop-ingest.md
    );
    prioritizePrompt = pkgs.writeText "test-task-loop-prioritize.md" (
      builtins.readFile ../../modules/os/agents/prompts/task-loop-prioritize.md
    );
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

            cat > "$HOME/TASKS.yaml" <<'EOF'
        tasks:
          - name: ""
            description: "Malformed pending task"
            status: pending
            source: email
            source_ref: "email-empty-name@test"
          - name: "invalid-skill-route"
            description: "Reject an invalid skill route"
            status: pending
            source: manual
            source_ref: "manual-invalid-skill"
            workflow: "../escape"
          - name: "missing-skill-route"
            description: "Block a missing skill route"
            status: pending
            source: manual
            source_ref: "manual-missing-skill"
            workflow: "missing/skill"
          - name: "reply-pong-to-test"
            description: "Reply with pong to the ping email from test@ncrmro.com"
            status: pending
            source: email
            source_ref: "email-1-test@ncrmro.com"
            workflow: "ping/pong"
    EOF

            mkdir -p "$HOME/.keystone" "$HOME/.agents/skills/ping-pong"
            printf '%s\n' '# Ping Pong Skill' 'Read REFERENCE.md before acting.' 'VALID_SKILL_DISPATCH_MARKER' > "$HOME/.agents/skills/ping-pong/SKILL.md"
            printf '%s\n' 'COLOCATED_REFERENCE_MARKER' > "$HOME/.agents/skills/ping-pong/REFERENCE.md"

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

            if printf '%s' "$args" | grep -q "Stage: prioritize"; then
              printf '%s\n' "1" > "$state_dir/prioritize-count"
            else
              printf '%s\n' "1" > "$state_dir/execute-count"
              printf '%s\n' "$args" > "$state_dir/execute-args"
            fi

            printf '%s\n' '{"total_tokens":1}'
    STUBEOF
            chmod +x "$PWD/stubs/claude"

            bash "${taskLoopScript}"

            invalid_status="$(yq '[.tasks[] | select(.source_ref == "email-empty-name@test")] | .[0].status' "$HOME/TASKS.yaml")"
            if [[ "$invalid_status" != "error" ]]; then
              echo "FAIL: invalid pending task status is '$invalid_status', expected 'error'" >&2
              cat "$HOME/TASKS.yaml" >&2
              exit 1
            fi
            echo "PASS: invalid pending task marked error"

            valid_status="$(yq '[.tasks[] | select(.source_ref == "email-1-test@ncrmro.com")] | .[0].status' "$HOME/TASKS.yaml")"
            if [[ "$valid_status" != "completed" ]]; then
              echo "FAIL: valid pending task status is '$valid_status', expected 'completed'" >&2
              cat "$HOME/TASKS.yaml" >&2
              exit 1
            fi
            echo "PASS: valid pending task completed"

            invalid_route_status="$(yq '[.tasks[] | select(.source_ref == "manual-invalid-skill")] | .[0].status' "$HOME/TASKS.yaml")"
            missing_route_status="$(yq '[.tasks[] | select(.source_ref == "manual-missing-skill")] | .[0].status' "$HOME/TASKS.yaml")"
            if [[ "$invalid_route_status" != "blocked" || "$missing_route_status" != "blocked" ]]; then
              echo "FAIL: unavailable skill routes were not blocked" >&2
              cat "$HOME/TASKS.yaml" >&2
              exit 1
            fi
            if [[ "$(yq '.issues | length' "$HOME/ISSUES.yaml")" != "2" ]]; then
              echo "FAIL: unavailable skill routes did not create two issue records" >&2
              cat "$HOME/ISSUES.yaml" >&2
              exit 1
            fi
            echo "PASS: invalid and missing skill routes blocked with issue records"

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
            if ! printf '%s' "$execute_args" | grep -q "VALID_SKILL_DISPATCH_MARKER"; then
              echo "FAIL: installed skill content did not reach the provider" >&2
              echo "  execute args: $execute_args" >&2
              exit 1
            fi
            echo "PASS: installed skill route reached the provider"
            skill_dir="$HOME/.agents/skills/ping-pong"
            if ! printf '%s' "$execute_args" | grep -Fq "Resolve every relative file reference from $skill_dir"; then
              echo "FAIL: provider prompt lacks the installed skill base directory" >&2
              echo "  execute args: $execute_args" >&2
              exit 1
            fi
            test -f "$skill_dir/REFERENCE.md"
            echo "PASS: co-located skill references have a resolvable base directory"

            touch "$out"
  ''
