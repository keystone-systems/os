# Regression test: one-time migration copies queue files from ~/notes to ~/ .
# Verifies ISSUE-REQ-20 (migration path from notes-based locations).
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
  notesDir = "/tmp/queue-migration-notes";
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
pkgs.runCommand "test-agent-queue-migration"
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

    mkdir -p "$HOME" "$PWD/stubs" ${notesDir}

    # Stubs
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/systemctl"
    chmod +x "$PWD/stubs/systemctl"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/git"
    chmod +x "$PWD/stubs/git"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' \"test-host\"" > "$PWD/stubs/hostname"
    chmod +x "$PWD/stubs/hostname"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' '[]'" > "$PWD/stubs/calendula"
    chmod +x "$PWD/stubs/calendula"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/claude"
    chmod +x "$PWD/stubs/claude"

    # Seed queue files in the OLD notes location (simulates pre-migration state)
    printf 'tasks:\n  - name: legacy-task\n    description: "Migrated from notes"\n    status: pending\n' > "${notesDir}/TASKS.yaml"
    printf 'projects:\n  - slug: legacy-project\n    name: "Legacy Project"\n' > "${notesDir}/PROJECTS.yaml"
    printf 'issues: []\n' > "${notesDir}/ISSUES.yaml"

    # $HOME should NOT have these files yet
    if [[ -f "$HOME/TASKS.yaml" ]]; then
      echo "FAIL: \$HOME/TASKS.yaml already exists before migration" >&2
      exit 1
    fi

    # Run the task loop — migration should happen automatically
    bash "${taskLoopScript}" || true

    # === Assertions ===

    # 1. TASKS.yaml migrated to $HOME
    if [[ ! -f "$HOME/TASKS.yaml" ]]; then
      echo "FAIL: TASKS.yaml not migrated to \$HOME" >&2
      exit 1
    fi
    echo "PASS: TASKS.yaml migrated to \$HOME"

    # 2. Migrated content preserved
    legacy_task=$(yq '[.tasks[] | select(.name == "legacy-task")] | length' "$HOME/TASKS.yaml" 2>/dev/null || echo "0")
    if [[ "$legacy_task" != "1" ]]; then
      echo "FAIL: legacy-task not found in migrated TASKS.yaml" >&2
      cat "$HOME/TASKS.yaml" >&2
      exit 1
    fi
    echo "PASS: legacy task content preserved"

    # 3. PROJECTS.yaml migrated
    if [[ ! -f "$HOME/PROJECTS.yaml" ]]; then
      echo "FAIL: PROJECTS.yaml not migrated to \$HOME" >&2
      exit 1
    fi
    echo "PASS: PROJECTS.yaml migrated"

    # 4. ISSUES.yaml migrated
    if [[ ! -f "$HOME/ISSUES.yaml" ]]; then
      echo "FAIL: ISSUES.yaml not migrated to \$HOME" >&2
      exit 1
    fi
    echo "PASS: ISSUES.yaml migrated"

    # 5. Migration is idempotent — does not overwrite existing home files
    printf 'tasks:\n  - name: home-task\n    description: "Already in home"\n    status: pending\n' > "$HOME/TASKS.yaml"
    bash "${taskLoopScript}" || true
    home_task=$(yq '[.tasks[] | select(.name == "home-task")] | length' "$HOME/TASKS.yaml" 2>/dev/null || echo "0")
    if [[ "$home_task" != "1" ]]; then
      echo "FAIL: migration overwrote existing \$HOME/TASKS.yaml" >&2
      cat "$HOME/TASKS.yaml" >&2
      exit 1
    fi
    echo "PASS: migration does not overwrite existing home files"

    echo ""
    echo "All queue migration assertions passed."
    touch "$out"
  ''
