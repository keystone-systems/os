# keystone-update-approve-flow — privilege-boundary contract for the
# Walker → Update path.
#
# The orchestrator that this file once tested lived in Rust
# (`cmd::update_approve`). The CLI is a shell script now, so the parts of
# the contract that greped Rust source are gone. What survives is the part
# that was always the security-critical half, and it is implementation
# independent:
#
#   - the privileged-approval allowlist grants `ks activate`, not a broad
#     `ks update` prefix (which would permit root fetch/lock/build/push);
#   - `ks activate` refuses any path outside /nix/store, so a misconfigured
#     allowlist still cannot activate /etc/passwd.
{
  pkgs,
  lib ? pkgs.lib,
  ks ? pkgs.keystone.ks,
}:
let
  privilegedApprovalNix = ../../modules/os/privileged-approval.nix;
in
pkgs.runCommand "test-keystone-update-approve-flow"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
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
    # The allowlist must contain the narrow `ks-activate` entry and must NOT
    # contain a top-level prefix-match entry for `ks update`. Leaving the old
    # `ks-update` entry in place would re-open the broad elevation hole.

    if ! grep -F 'name = "ks-activate";' ${privilegedApprovalNix} >/dev/null; then
      fail "privileged-approval.nix must declare an ks-activate command entry"
    fi

    # The substring `"ks-update"` is acceptable in a comment describing the
    # migration. The structural assignment `name = "ks-update";` is not.
    if grep -F 'name = "ks-update";' ${privilegedApprovalNix} >/dev/null; then
      fail "privileged-approval.nix still has the broad ks-update entry; expected it to be replaced by ks-activate"
    fi

    grep -F '"activate"' ${privilegedApprovalNix} >/dev/null \
      || fail "privileged-approval.nix ks-activate argv must contain \"activate\""

    # -- ks activate refuses paths outside the store -----------------------
    #
    # Defense in depth: this validation runs inside the privileged child.

    if ${ks}/bin/ks activate /etc/passwd > stdout.log 2>stderr.log; then
      fail "ks activate accepted a path outside /nix/store"
    fi
    grep -F '/nix/store' stderr.log >/dev/null \
      || fail "ks activate rejection message must name the /nix/store requirement"

    if ${ks}/bin/ks activate > stdout.log 2>stderr.log; then
      fail "ks activate accepted an empty store path"
    fi

    touch "$out"
  ''
