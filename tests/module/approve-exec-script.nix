# approve-exec-script — regression test for the real approve-exec.sh helper.
#
# `tests/module/ks-approve.nix` covers `ks approve` end-to-end with a STUBBED
# helper, so it doesn't catch bugs in the script itself. This test exercises
# the real `modules/os/scripts/approve-exec.sh` against a fixture allowlist,
# in `--validate` mode (no root, no exec), and asserts the matched-entry
# JSON is produced.
#
# The bug this guards against: jq's `--args` consumes ALL following arguments
# as positionals — including what would otherwise be the filter. Writing
# `jq -cn --args "$@" '$ARGS.positional'` makes jq treat the filter as just
# another positional, leaving no filter, which it then tries to compile from
# the first positional ("ks") and dies with "ks/0 is not defined". The fix
# is `jq -cn '$ARGS.positional' --args "$@"`. This bug went undetected from
# 2026-03-31 to 2026-04-28 because every interactive caller has a tty and
# the stubbed helper is what unit tests saw.
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  scriptSrc = ../../modules/os/scripts/approve-exec.sh;

  # Fixture allowlist: minimal copy of the production schema with one
  # exact-match entry and one prefix-match entry. The script reads the
  # config path baked in at substitution time.
  fixtureConfig = pkgs.writeText "approve-exec-fixture.json" (
    builtins.toJSON {
      backend = "desktop-polkit";
      commands = [
        {
          name = "ks-update";
          displayName = "Run Keystone update";
          reason = "Run the Keystone update workflow for this host.";
          runAs = "root";
          approvalMethods = [ "password" ];
          match = "prefix";
          argv = [
            "ks"
            "update"
          ];
        }
        {
          name = "keystone-enroll-fido2-auto";
          displayName = "Enroll hardware key for disk unlock";
          reason = "Enroll a FIDO2 hardware key for disk unlock.";
          runAs = "root";
          approvalMethods = [ "password" ];
          match = "exact";
          argv = [
            "keystone-enroll-fido2"
            "--auto"
          ];
        }
      ];
    }
  );

  # Build the helper exactly the way privileged-approval.nix does: substitute
  # @configFile@ and @jq@, then make it executable. Keeps the test honest
  # about the production substitution path.
  helperScript = pkgs.runCommand "approve-exec-test-helper" { } ''
    cp ${
      pkgs.replaceVars scriptSrc {
        configFile = "${fixtureConfig}";
        jq = "${pkgs.jq}/bin/jq";
      }
    } $out
    chmod +x $out
  '';
in
pkgs.runCommand "test-approve-exec-script"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      jq
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "FAIL: $*" >&2
      exit 1
    }

    # -- Bug 1 regression: jq --args order in join_argv_json -----------------
    #
    # With the broken script `bash ${helperScript} --validate --reason X -- ks update`
    # exits non-zero because jq fails to compile the filter. With the fix it
    # MUST emit the matched ks-update entry as JSON.

    set +e
    output="$(bash ${helperScript} --validate --reason "regression test" -- ks update 2>&1)"
    rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
      echo "approve-exec.sh exited $rc when validating an allowlisted argv:" >&2
      echo "$output" >&2
      fail "approve-exec.sh --validate must succeed for allowlisted 'ks update'"
    fi

    if ! grep -F '"name":"ks-update"' <<<"$output" >/dev/null; then
      echo "Output: $output" >&2
      fail "approve-exec.sh --validate must return the matched 'ks-update' entry as JSON"
    fi

    # The Lua/Rust dispatch path consumes displayName + reason — make sure
    # those round-trip too.
    if ! grep -F '"displayName":"Run Keystone update"' <<<"$output" >/dev/null; then
      fail "matched-entry JSON must include displayName"
    fi

    # -- Prefix-match: extra args beyond the allowlisted prefix succeed -----
    #
    # `ks update --approve` is the actual shape ks-update.service uses. Make
    # sure the prefix matcher accepts it.

    output_prefix="$(bash ${helperScript} --validate --reason "regression test" -- ks update --approve)"
    if ! grep -F '"name":"ks-update"' <<<"$output_prefix" >/dev/null; then
      fail "approve-exec.sh --validate must accept 'ks update --approve' (prefix match)"
    fi

    # -- Exact-match: keystone-enroll-fido2 --auto -------------------------

    output_exact="$(bash ${helperScript} --validate --reason "regression test" -- keystone-enroll-fido2 --auto)"
    if ! grep -F '"name":"keystone-enroll-fido2-auto"' <<<"$output_exact" >/dev/null; then
      fail "approve-exec.sh --validate must accept the exact 'keystone-enroll-fido2 --auto' entry"
    fi

    # -- Negative: non-allowlisted argv MUST be rejected -------------------

    # Combine stdout+stderr because the script splits the rejection notice
    # across both streams (see comment in approve-exec.sh). The test asserts
    # rejection observably fires; tightening stream targeting is a separate
    # cleanup outside the scope of this regression.
    if bash ${helperScript} --validate --reason "should reject" -- /bin/echo nope \
        >"$PWD/reject.out" 2>&1; then
      fail "approve-exec.sh --validate must reject non-allowlisted argv"
    fi
    grep -F "Rejected command:" "$PWD/reject.out" >/dev/null \
      || fail "rejected output must include 'Rejected command:'"

    touch "$out"
  ''
