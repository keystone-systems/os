{
  pkgs,
  lib,
}:
let
  emailPingFixture = ../fixtures/task-loop/email-ping-source.json;
  calendulaEventsFixture = ../fixtures/task-loop/calendula-events.json;
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
  notesDir = "/tmp/task-loop-ping-pong-notes";
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
pkgs.runCommand "test-agent-task-loop-ping-pong"
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

    # Queue files live in $HOME (agent home), not the notes dir
    printf '%s\n' 'tasks: []' > "$HOME/TASKS.yaml"
    mkdir -p "$HOME/.deepwork"

    # Stub: systemctl (no-op)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/systemctl"
    chmod +x "$PWD/stubs/systemctl"

    # Stub: git (no-op)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/git"
    chmod +x "$PWD/stubs/git"

    # Stub: hostname
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' \"test-host\"" > "$PWD/stubs/hostname"
    chmod +x "$PWD/stubs/hostname"

    # Stub: fetch-email-source — returns ping email fixture with body
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${emailPingFixture}" > "$PWD/stubs/fetch-email-source"
    chmod +x "$PWD/stubs/fetch-email-source"

    # Stub: calendula — returns events fixture
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${calendulaEventsFixture}" > "$PWD/stubs/calendula"
    chmod +x "$PWD/stubs/calendula"

    # Stub: himalaya — captures sent messages to a sink file so we can assert
    # the ping/pong contract is honored end-to-end. On `message send`, stdin
    # is appended to the sink; any other args are a no-op.
    printf '%s\n' \
      '#!${pkgs.bash}/bin/bash' \
      'set -euo pipefail' \
      'sink="''${TASK_LOOP_TEST_STATE_DIR:?}/himalaya-sent.eml"' \
      'if [[ "''${1:-}" == "message" && "''${2:-}" == "send" ]]; then' \
      '  cat >> "$sink"' \
      '  printf "\n--- END MESSAGE ---\n" >> "$sink"' \
      'fi' \
      'exit 0' \
      > "$PWD/stubs/himalaya"
    chmod +x "$PWD/stubs/himalaya"

    # Stub: claude — handles ingest, prioritize, and execute stages. The
    # execute stub simulates an agent obeying the parse_sources Ping/Pong
    # contract (subject `Re: [pong] <tag>`, body `pong`) by piping the reply
    # through the himalaya stub. If the contract in job.yml drifts from the
    # pong-subject/pong-body convention, the assertions below fail.
    cat > "$PWD/stubs/claude" <<'STUBEOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    args="$*"
    state_dir="''${TASK_LOOP_TEST_STATE_DIR:?}"
    agent_home="''${HOME:?}"

    if printf '%s' "$args" | grep -q "task_loop ingest"; then
      printf '%s\n' "1" > "$state_dir/ingest-count"
      printf 'tasks:\n  - name: reply-pong-to-test\n    description: "Reply to the [ping] e2e-test email with subject '"'"'Re: [pong] e2e-test'"'"' and body '"'"'pong'"'"' per the task_loop Ping/Pong core rule."\n    status: pending\n    source: email\n    source_ref: "email-1-test@ncrmro.com"\n' > "$agent_home/TASKS.yaml"

    elif printf '%s' "$args" | grep -q "task_loop prioritize"; then
      printf '%s\n' "1" > "$state_dir/prioritize-count"
      yq -i '(.tasks[] | select(.name == "reply-pong-to-test")).model = "haiku"' "$agent_home/TASKS.yaml"

    else
      # Execute stage: simulate an agent obeying the contract by sending a
      # pong reply through the himalaya stub.
      printf '%s\n' "1" > "$state_dir/execute-count"
      printf '%s\n' "$args" > "$state_dir/execute-args"
      printf 'From: agent-test@ncrmro.com\nTo: test@ncrmro.com\nSubject: Re: [pong] e2e-test\nMIME-Version: 1.0\nContent-Type: text/plain; charset=utf-8\n\npong\n' | himalaya message send
    fi

    printf '%s\n' '{"total_tokens":1}'
    STUBEOF
    chmod +x "$PWD/stubs/claude"

    # Run the task loop
    bash "${taskLoopScript}"

    # === Assertions ===

    # 1. Ingest was invoked
    if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/ingest-count" ]]; then
      echo "FAIL: ingest stage was not invoked" >&2
      exit 1
    fi
    echo "PASS: ingest stage invoked"

    # 2. Prioritize was invoked
    if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/prioritize-count" ]]; then
      echo "FAIL: prioritize stage was not invoked" >&2
      exit 1
    fi
    echo "PASS: prioritize stage invoked"

    # 3. Execute was invoked
    if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/execute-count" ]]; then
      echo "FAIL: execute stage was not invoked" >&2
      cat "$HOME/TASKS.yaml" >&2
      exit 1
    fi
    echo "PASS: execute stage invoked"

    # 4. Execute received the pong task
    execute_args="$(cat "$TASK_LOOP_TEST_STATE_DIR/execute-args")"
    if ! printf '%s' "$execute_args" | grep -qi "reply-pong-to-test"; then
      echo "FAIL: execute stage did not receive pong task name" >&2
      echo "  execute args: $execute_args" >&2
      exit 1
    fi
    echo "PASS: execute received pong task name"

    # 5. Task marked completed after successful execute
    pong_status="$(yq '[.tasks[] | select(.name == "reply-pong-to-test")] | .[0].status' "$HOME/TASKS.yaml")"
    if [[ "$pong_status" != "completed" ]]; then
      echo "FAIL: pong task status is '$pong_status', expected 'completed'" >&2
      cat "$HOME/TASKS.yaml" >&2
      exit 1
    fi
    echo "PASS: pong task completed"

    # 6. Contract enforcement: the simulated reply in the himalaya sink MUST
    #    contain the pong subject flip and a pong body per the parse_sources
    #    core rule. Drift in that contract fails CI here.
    sink="$TASK_LOOP_TEST_STATE_DIR/himalaya-sent.eml"
    if [[ ! -f "$sink" ]]; then
      echo "FAIL: no outbound message was captured — execute stage did not send a reply" >&2
      exit 1
    fi
    if ! grep -q '^Subject: Re: \[pong\] ' "$sink"; then
      echo "FAIL: sent reply subject does not match the Ping/Pong contract (expected 'Re: [pong] <tag>')" >&2
      cat "$sink" >&2
      exit 1
    fi
    if ! grep -qi '^pong$' "$sink"; then
      echo "FAIL: sent reply body does not contain 'pong' per the Ping/Pong contract" >&2
      cat "$sink" >&2
      exit 1
    fi
    echo "PASS: outbound reply honors the Ping/Pong contract (subject + body)"

    echo ""
    echo "All ping-pong pipeline assertions passed."
    touch "$out"
  ''
