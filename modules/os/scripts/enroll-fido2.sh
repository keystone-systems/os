#!/usr/bin/env bash
# Keystone disk unlock enrollment: FIDO2 hardware key

set -euo pipefail

CREDSTORE_DEVICE="@credstoreDevice@"
STATUS_FILE="/var/lib/keystone/disk-unlock-status.json"

AUTO_MODE=false
for arg in "$@"; do
  case "$arg" in
    --auto)
      AUTO_MODE=true
      ;;
    --help|-h)
      cat <<'EOF'
Keystone disk unlock enrollment: FIDO2 hardware key

Usage: keystone-enroll-fido2 [--auto]

Options:
  --auto    Execute enrollment after the preflight checks
  --help    Show this help message
EOF
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

echo "=== Keystone disk unlock enrollment: FIDO2 hardware key ==="
echo ""

if ! @bootctl@ status 2>/dev/null | grep -q "Secure Boot:.*enabled.*user"; then
  echo "[ERROR] Secure Boot is not fully enabled in User Mode"
  exit 1
fi
echo "[OK] Secure Boot enabled (user mode)"

if ! @systemd_cryptenroll@ --tpm2-device=list >/dev/null 2>&1; then
  echo "[ERROR] No TPM2 device found"
  exit 2
fi
echo "[OK] TPM2 device detected"

if ! @systemd_cryptenroll@ --fido2-device=list 2>/dev/null | grep -q '^/dev/'; then
  echo "[ERROR] No FIDO2 hardware key detected"
  exit 3
fi
echo "[OK] FIDO2 hardware key detected"

if [[ ! -e "$CREDSTORE_DEVICE" ]]; then
  echo "[ERROR] Target disk unlock device not found: $CREDSTORE_DEVICE"
  exit 4
fi
echo "[OK] Target disk unlock device found: $CREDSTORE_DEVICE"
echo ""

echo "[Detected FIDO2 devices]"
@systemd_cryptenroll@ --fido2-device=list || true
echo ""

if [ "$AUTO_MODE" = false ]; then
  cat <<EOF
[Manual execution]

Run the following command to enroll the current FIDO2 hardware key:

  sudo keystone-enroll-fido2 --auto

You will be prompted for:
- your sudo password,
- your current LUKS password if needed, and
- any PIN or touch confirmation required by the hardware key.
EOF
  exit 0
fi

echo "[Step 1/2] Enrolling FIDO2 hardware key for disk unlock..."
echo ""
if ! @systemd_cryptenroll@ "$CREDSTORE_DEVICE" --fido2-device=auto; then
  echo "[ERROR] FIDO2 enrollment failed"
  exit 5
fi
echo "[OK] FIDO2 enrollment command completed"
echo ""

echo "[Step 2/2] Verifying token state..."
if ! @cryptsetup@ luksDump "$CREDSTORE_DEVICE" | grep -q "systemd-fido2"; then
  echo "[ERROR] systemd-fido2 token not found after enrollment"
  exit 6
fi
echo "[OK] FIDO2 token detected in LUKS header"

mkdir -p "$(dirname "$STATUS_FILE")"
cat > "$STATUS_FILE" <<EOF
{
  "checked_at": "$(date -Iseconds)",
  "device": "$CREDSTORE_DEVICE",
  "tpm_enrolled": $(if @cryptsetup@ luksDump "$CREDSTORE_DEVICE" | grep -q "systemd-tpm2"; then echo true; else echo false; fi),
  "fido2_enrolled": true
}
EOF
chmod 0644 "$STATUS_FILE"

echo ""
cat <<'EOF'
+-------------------------------------------------------------------------+
|  FIDO2 DISK UNLOCK ENROLLMENT COMPLETE                                  |
+-------------------------------------------------------------------------+
|                                                                         |
|  The current hardware key is now enrolled for disk unlock.              |
|                                                                         |
|  Test with: sudo reboot                                                 |
|                                                                         |
+-------------------------------------------------------------------------+
EOF
