# Regression test: task-loop queue files live in $HOME, not notes dir.
# Verifies ISSUE-REQ-3 (no notes-repo dependency) and ISSUE-REQ-5 (queue in $HOME).
# Fails if the task loop writes TASKS.yaml or sources.json into the notes dir.
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
  notesDir = "/tmp/runtime-coherence-notes";
  taskLoopScript = pkgs.replaceVars ../../modules/os/agents/scripts/task-loop.sh {
    notesDir = notesDir;
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
pkgs.runCommand "test-agent-runtime-coherence"
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

    # Seed TASKS.yaml in $HOME (the new canonical location)
    printf '%s\n' 'tasks: []' > "$HOME/TASKS.yaml"

    # Do NOT seed TASKS.yaml in notes dir — the task loop must not need it there

    # Stubs
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
      printf '%s\n' 'tasks: []' > TASKS.yaml
    fi
    printf '%s\n' '{"total_tokens":1}'
    EOF
    chmod +x "$PWD/stubs/claude"

    # Run the task loop
    bash "${taskLoopScript}"

    # === Assertions ===

    # 1. TASKS.yaml must exist in $HOME
    if [[ ! -f "$HOME/TASKS.yaml" ]]; then
      echo "FAIL: TASKS.yaml not found in \$HOME" >&2
      exit 1
    fi
    echo "PASS: TASKS.yaml exists in \$HOME"

    # 2. TASKS.yaml must NOT have been created in notes dir by the task loop
    if [[ -f "${notesDir}/TASKS.yaml" ]]; then
      echo "FAIL: TASKS.yaml found in notes dir — task loop still writes to notes" >&2
      exit 1
    fi
    echo "PASS: TASKS.yaml not in notes dir"

    # 3. sources.json must be in $HOME/.deepwork/, not notes/.deepwork/
    if [[ -f "$HOME/.deepwork/sources.json" ]]; then
      echo "PASS: sources.json found in \$HOME/.deepwork/"
    else
      echo "FAIL: sources.json not found in \$HOME/.deepwork/" >&2
      exit 1
    fi

    if [[ -f "${notesDir}/.deepwork/sources.json" ]]; then
      echo "FAIL: sources.json found in notes dir — task loop still writes to notes" >&2
      exit 1
    fi
    echo "PASS: sources.json not in notes dir"

    echo ""
    echo "All runtime coherence assertions passed."
    touch "$out"
  ''
