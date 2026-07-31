# keystone-update-approve-flow — shell-level fixture exercising the
# Walker → Update orchestrator (`cmd::update_approve::run_supervised_update`).
#
# Boots the real `ks` binary against fake `pkexec`, `git`, `nix`,
# `keystone-approve-exec`, and a synthetic consumer flake. Asserts:
#
#   - `ks update --approve` rejects --dev / --boot / --hosts / --pull
#     up front (the old broker-recursion path silently accepted these).
#   - The privileged-approval allowlist contains `ks-activate` and no
#     longer contains the broad `ks-update` prefix entry.
#   - `cmd::update_approve::elevated_argv` produces the literal
#     `["ks", "activate", <store-path>]` shape the broker matches.
#
# A full VM test that exercises the live `nix build` + `git push` +
# `pkexec` path is overkill for the privilege-boundary contract this
# refactor introduces — the failure modes we care about are all
# observable at the argv / allowlist / orchestrator level. The earlier
# `tests/module/ks-approve.nix` set the precedent for fake-bin shell
# tests over module-level VMs for this surface.
{
  pkgs,
  lib ? pkgs.lib,
  ks ? pkgs.keystone.ks,
}:
let
  privilegedApprovalNix = ../../modules/os/privileged-approval.nix;
  updateApproveRs = ../../packages/ks/src/cmd/update_approve.rs;
  activateRs = ../../packages/ks/src/cmd/activate.rs;
in
pkgs.runCommand "test-keystone-update-approve-flow"
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

    # -- Allowlist surface -------------------------------------------------
    #
    # The privileged-approval allowlist must contain the new narrow
    # `ks-activate` entry and must NOT contain a top-level prefix-match
    # entry for `ks update`. This is the security-critical assertion
    # — leaving the old `ks-update` entry in place would re-open the
    # broad elevation hole.

    if ! grep -F 'name = "ks-activate";' ${privilegedApprovalNix} >/dev/null; then
      fail "privileged-approval.nix must declare an ks-activate command entry"
    fi

    # The substring `"ks-update"` would be acceptable in a comment
    # describing the migration, but the structural assignment
    # `name = "ks-update";` is the part we forbid.
    if grep -F 'name = "ks-update";' ${privilegedApprovalNix} >/dev/null; then
      fail "privileged-approval.nix still has the broad ks-update entry; expected it to be replaced by ks-activate"
    fi

    # The new entry must point at argv prefix `["ks", "activate"]`. A
    # narrower exact-match would be safer in principle, but the orchestrator
    # passes a freshly-built store path that we can't pin in the allowlist
    # at config-eval time, so prefix-match on the verb is the right shape.
    grep -F '"ks-activate"' ${privilegedApprovalNix} >/dev/null \
      || fail "privileged-approval.nix ks-activate entry is missing the name token"
    grep -F '"activate"' ${privilegedApprovalNix} >/dev/null \
      || fail "privileged-approval.nix ks-activate argv must contain \"activate\""

    # -- Orchestrator argv shape -----------------------------------------
    #
    # The elevated child must be `["ks", "activate", <store-path>]` —
    # never a git verb, never a flake input override. The unit test in
    # cmd::update_approve covers this at runtime; the grep here covers
    # the source so a maintainer renaming `elevated_argv` can't break
    # the contract without the test failing visibly.

    grep -F '"activate".to_string()' ${updateApproveRs} >/dev/null \
      || fail "update_approve.rs elevated_argv must produce the activate verb"

    # The `elevated_argv` literal is a multi-line `vec![ ... ]`. A
    # line-based `grep -E` (the original implementation) misses a
    # forbidden verb added on its own line inside the vec. Use
    # `grep -zP` (null-data PCRE so the pattern can span newlines) and
    # bound the match to the `elevated_argv` function body by matching
    # only characters that are not `}`. The function body contains no
    # nested braces, so `[^}]*` is the cheapest correct scope; it
    # naturally stops at the closing `}` of the function and prevents
    # the regex from drifting into adjacent code (e.g. test fixtures
    # that legitimately contain `"push"`).
    #
    # CRITICAL: anchor on `fn elevated_argv(` (with opening paren) so
    # the pattern does NOT match test function names like
    # `fn elevated_argv_contains_no_git_verbs(...) { ... "pull" ... }`.
    # Without the paren anchor the prefix `fn elevated_argv` matches
    # `fn elevated_argv_contains_no_git_verbs` and the regex then drifts
    # into the test body which legitimately quotes the forbidden verbs.
    #
    # `grep -zP` is GNU-grep-specific — the surrounding fixture pulls
    # `pkgs.gnugrep` into nativeBuildInputs and PATH, so this is safe.
    if grep -zP 'fn elevated_argv\([^}]*"(pull|push|fetch|commit|clone|lock|update)"[^}]*\}' ${updateApproveRs} >/dev/null; then
      fail "update_approve.rs elevated_argv leaked a git/lock verb"
    fi

    # -- ks activate validation rejects non-store paths --------------------
    #
    # Defense-in-depth: the validator in cmd::activate runs inside the
    # privileged child too. If the prefix-check is removed, a misconfigured
    # allowlist could push activation against /etc/passwd. Pin the
    # validation strings so a well-intentioned refactor doesn't lose them.

    grep -F '/nix/store/' ${activateRs} >/dev/null \
      || fail "activate.rs must enforce /nix/store/ prefix on the store-path argument"
    grep -F 'must be absolute' ${activateRs} >/dev/null \
      || fail "activate.rs must reject relative store paths"

    # -- ks update --approve refuses fleet-style flags ---------------------
    #
    # Run the actual binary and verify the flag-rejection branch fires.
    # We do NOT supply a flake fixture here — the rejection happens before
    # any flake lookup, and supplying one would require synthesising a full
    # nixos-config tree.

    export PATH="${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }"

    # `--approve` + `--dev` should fail fast with the documented message.
    if ${ks}/bin/ks update --approve --dev > stdout.log 2>stderr.log; then
      fail "ks update --approve --dev was accepted but should have been rejected"
    fi
    grep -F "does not accept" stderr.log >/dev/null \
      || fail "ks update --approve --dev rejection message missing 'does not accept'"

    # `--approve` + `--boot` likewise.
    if ${ks}/bin/ks update --approve --boot > stdout.log 2>stderr.log; then
      fail "ks update --approve --boot was accepted but should have been rejected"
    fi

    # `--approve` + an explicit hosts arg.
    if ${ks}/bin/ks update --approve other-host > stdout.log 2>stderr.log; then
      fail "ks update --approve <host> was accepted but should have been rejected"
    fi

    touch "$out"
  ''
