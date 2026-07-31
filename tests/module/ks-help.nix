{
  pkgs,
  ks ? pkgs.keystone.ks,
}:
pkgs.runCommand "ks-help-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    export PATH="${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ]
    }"

    KS_BIN="${ks}/bin/ks"
    TMP_DIR="$(mktemp -d)"

    cleanup() {
      local exit_code=$?
      rm -rf "$TMP_DIR"
      exit "$exit_code"
    }
    trap cleanup EXIT INT TERM

    run_capture() {
      local name="$1"
      shift

      local stdout_file="$TMP_DIR/$name.out"
      local stderr_file="$TMP_DIR/$name.err"
      local status_file="$TMP_DIR/$name.status"

      if "$KS_BIN" "$@" >"$stdout_file" 2>"$stderr_file"; then
        printf '0\n' >"$status_file"
      else
        printf '%s\n' "$?" >"$status_file"
      fi
    }

    assert_status() {
      local name="$1"
      local expected="$2"
      local actual
      actual="$(cat "$TMP_DIR/$name.status")"

      if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $name exited with $actual, expected $expected" >&2
        echo "--- stdout ---" >&2
        cat "$TMP_DIR/$name.out" >&2 || true
        echo "--- stderr ---" >&2
        cat "$TMP_DIR/$name.err" >&2 || true
        exit 1
      fi
    }

    assert_nonzero() {
      local name="$1"
      local actual
      actual="$(cat "$TMP_DIR/$name.status")"
      if [[ "$actual" == "0" ]]; then
        echo "FAIL: $name unexpectedly succeeded" >&2
        exit 1
      fi
    }

    assert_contains() {
      local name="$1"
      local pattern="$2"
      local combined="$TMP_DIR/$name.combined"

      cat "$TMP_DIR/$name.out" "$TMP_DIR/$name.err" >"$combined"
      if ! grep -Fq -- "$pattern" "$combined"; then
        echo "FAIL: $name missing pattern: $pattern" >&2
        echo "--- combined output ---" >&2
        cat "$combined" >&2 || true
        exit 1
      fi
    }

    run_capture main-long --help
    assert_status main-long 0
    assert_contains main-long "Usage: ks"
    assert_contains main-long "Commands:"
    assert_contains main-long "template"
    assert_contains main-long "build"
    assert_contains main-long "doctor"

    run_capture main-short -h
    assert_status main-short 0
    assert_contains main-short "Usage: ks"

    for command in template approve agents build update switch sync-agent-assets sync-host-keys agent doctor grafana docs photos screenshots print hardware-key; do
      run_capture "help-$command" help "$command"
      assert_status "help-$command" 0
      assert_contains "help-$command" "Usage: ks $command"

      run_capture "$command-long" "$command" --help
      assert_status "$command-long" 0
      assert_contains "$command-long" "Usage: ks $command"

      run_capture "$command-short" "$command" -h
      assert_status "$command-short" 0
      assert_contains "$command-short" "Usage: ks $command"
    done

    run_capture grafana-dashboards-help grafana dashboards --help
    assert_status grafana-dashboards-help 0
    assert_contains grafana-dashboards-help "Usage: ks grafana dashboards"

    run_capture hardware-key-doctor-help hardware-key doctor --help
    assert_status hardware-key-doctor-help 0
    assert_contains hardware-key-doctor-help "Usage: ks hardware-key doctor"

    run_capture hardware-key-secrets-help hardware-key secrets --help
    assert_status hardware-key-secrets-help 0
    assert_contains hardware-key-secrets-help "Usage: ks hardware-key secrets"

    run_capture unknown-command unknown-command
    assert_nonzero unknown-command
    assert_contains unknown-command "error:"

    run_capture build-bad-flag build --bad-flag
    assert_nonzero build-bad-flag
    assert_contains build-bad-flag "error:"

    run_capture help-unknown help unknown-topic
    assert_nonzero help-unknown
    assert_contains help-unknown "error:"

    touch "$out"
  ''
