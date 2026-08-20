#!/usr/bin/env bash
# The age identity file lists every registered YubiKey. Offering all of them to
# sops makes it ask for a key that is not plugged in, which the operator then
# has to skip. Prove that only the connected key is offered, in both identity
# file formats.
set -euo pipefail

ks_sh="${1:-packages/ks/ks.sh}"
[[ -r "$ks_sh" ]] || {
  echo "ks-age-identity: cannot read $ks_sh" >&2
  exit 1
}

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/run"

# As written by modules/terminal/age-yubikey.nix.
cat >"$test_root/keystone-format.txt" <<'EOF'
# serial:11111111
AGE-PLUGIN-YUBIKEY-BLACKSTUB
# serial:22222222
AGE-PLUGIN-YUBIKEY-GREENSTUB
EOF

# As printed by `age-plugin-yubikey --list`.
cat >"$test_root/plugin-format.txt" <<'EOF'
#       Serial: 11111111, Slot: 1
#    Recipient: age1yubikey1black
AGE-PLUGIN-YUBIKEY-BLACKSTUB

#       Serial: 22222222, Slot: 2
#    Recipient: age1yubikey1green
AGE-PLUGIN-YUBIKEY-GREENSTUB
EOF

# /bin/sh, not /usr/bin/env: the Nix build sandbox provides the former and not
# the latter, and a mock that cannot exec reads as "no YubiKey connected".
cat >"$test_root/bin/ykman" <<'EOF'
#!/bin/sh
printf '%s\n' ${FAKE_SERIALS:-}
EOF
chmod +x "$test_root/bin/ykman"

# Run sops_age_identity with the surrounding script's helpers stubbed out.
select_for() {
  local serials="$1" identity="$2"
  PATH="$test_root/bin:$PATH" \
    FAKE_SERIALS="$serials" \
    XDG_RUNTIME_DIR="$test_root/run" \
    SOPS_AGE_KEY_FILE="$identity" \
    bash --noprofile --norc -c '
      note() { echo "note: $*" >&2; }
      die() { echo "$*" >&2; exit 1; }
      eval "$(awk "/^sops_identity_cleanup\\(\\) \\{/,/^\\}\$/" "'"$ks_sh"'")"
      eval "$(awk "/^sops_age_identity\\(\\) \\{/,/^\\}\$/" "'"$ks_sh"'")"
      sops_age_identity
      grep -c "^AGE-PLUGIN-YUBIKEY-" "$SOPS_AGE_KEY_FILE" 2>/dev/null || true
      grep -o "AGE-PLUGIN-YUBIKEY-[A-Z]*" "$SOPS_AGE_KEY_FILE" 2>/dev/null | tr "\n" " "
    '
}

expect() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" != *"$want"* ]]; then
    echo "FAIL: $label: wanted '$want', got '$got'" >&2
    exit 1
  fi
  echo "ok: $label"
}

for identity in keystone-format plugin-format; do
  file="$test_root/${identity}.txt"
  expect "$identity: only the connected black key" \
    "AGE-PLUGIN-YUBIKEY-BLACKSTUB" "$(select_for 11111111 "$file")"
  got="$(select_for 11111111 "$file")"
  [[ "$got" != *GREENSTUB* ]] || {
    echo "FAIL: $identity: offered the absent green key" >&2
    exit 1
  }
  expect "$identity: only the connected green key" \
    "AGE-PLUGIN-YUBIKEY-GREENSTUB" "$(select_for 22222222 "$file")"
  expect "$identity: both when both are connected" \
    "2" "$(select_for '11111111
22222222' "$file")"
done

# No key connected must not strip the file down to nothing: the operator gets
# the original list and a note, rather than "no identity matched".
got="$(select_for '' "$test_root/keystone-format.txt")"
expect "no key connected keeps every identity" "2" "$got"

echo "ks-age-identity tests passed"
