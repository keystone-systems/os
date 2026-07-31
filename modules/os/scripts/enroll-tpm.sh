#!/usr/bin/env bash
# Keystone TPM Enrollment: Standalone TPM Enrollment
# For advanced users who have already configured recovery credentials manually

set -euo pipefail

# Configuration (substituted by NixOS module)
CREDSTORE_DEVICE="@credstoreDevice@"
TPM_PCRS="@tpmPCRs@"
MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"

# Parse arguments
AUTO_MODE=false
for arg in "$@"; do
    case $arg in
        --auto)
            AUTO_MODE=true
            ;;
        --help|-h)
            cat <<EOF
Keystone TPM Enrollment: Standalone TPM Configuration

Usage: keystone-enroll-tpm [--auto]

Options:
  --auto    Automatically execute TPM enrollment
  --help    Show this help message

This is for advanced users who have manually configured recovery credentials.
Most users should use keystone-enroll-recovery or keystone-enroll-password instead.

Without --auto, shows commands that would be executed.
With --auto, enrolls TPM automatically (assumes non-default password exists).
EOF
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== Keystone TPM Enrollment: Standalone TPM Configuration ==="
echo ""
echo "[!] WARNING: This assumes you have ALREADY replaced the default"
echo "    \"keystone\" password with your own recovery credential."
echo ""

# Run prerequisite checks
echo "[Prerequisites]"

if ! @bootctl@ status 2>/dev/null | grep -q "Secure Boot:.*enabled.*user"; then
  echo "[ERROR] Secure Boot is not fully enabled in User Mode"
  exit 1
fi
echo "[OK] Secure Boot enabled (user mode)"

if ! @systemd_cryptenroll@ --tpm2-device=list &>/dev/null; then
  echo "[ERROR] No TPM2 device found"
  exit 2
fi
echo "[OK] TPM2 device detected"

if [[ ! -b "$CREDSTORE_DEVICE" ]]; then
  echo "[ERROR] Credstore volume not found: $CREDSTORE_DEVICE"
  exit 3
fi
echo "[OK] Credstore volume found: $CREDSTORE_DEVICE"

echo ""

# Show commands
cat <<EOF
[Commands to Execute]

  [1] Enroll TPM (PCRs: $TPM_PCRS):
      $ systemd-cryptenroll $CREDSTORE_DEVICE \\
          --tpm2-device=auto \\
          --tpm2-pcrs=$TPM_PCRS \\
          --wipe-slot=empty \\
          --unlock-key-file=<(echo -n "<your-password>")

      Note: Replace <your-password> with your current LUKS password (NOT "keystone").

  [2] Verify enrollment:
      $ cryptsetup luksDump $CREDSTORE_DEVICE | grep systemd-tpm2

  [3] Create enrollment marker:
      $ cat > /var/lib/keystone/tpm-enrollment-complete

EOF

# If not auto mode, exit with instructions
if [ "$AUTO_MODE" = false ]; then
    cat <<EOF
[Manual Execution]

To execute these commands manually, copy them from above.
To execute automatically, run:
  $ sudo keystone-enroll-tpm --auto

Note: You will be prompted for your current LUKS password (not "keystone").

EOF
    exit 0
fi

# Check if default password still active
if @systemd_cryptenroll@ "$CREDSTORE_DEVICE" 2>/dev/null | grep -qE "^\s*0\s+password"; then
  echo "[!] WARNING: Keyslot 0 (usually default password) is still active"
  echo ""
  echo "This may mean the default \"keystone\" password has not been replaced."
  echo ""
  read -rp "Continue anyway? (y/N): " -n 1 force_continue
  echo ""
  if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
    echo "Enrollment cancelled."
    echo ""
    echo "Recommended: Use keystone-enroll-recovery or keystone-enroll-password"
    exit 0
  fi
  echo ""
fi

echo "[Auto-Execution Mode]"
echo ""

echo "[Step 1/3] Enrolling TPM with PCRs: $TPM_PCRS..."
echo "$ systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=$TPM_PCRS --wipe-slot=empty"
echo ""
echo "Note: You will be prompted for your LUKS password (the one that replaced \"keystone\")"
echo ""

# Let systemd-cryptenroll prompt for password interactively
if ! @systemd_cryptenroll@ \
  "$CREDSTORE_DEVICE" \
  --tpm2-device=auto \
  --tpm2-pcrs="$TPM_PCRS" \
  --wipe-slot=empty; then
  echo "[ERROR] TPM enrollment failed"
  exit 4
fi
echo "[OK] TPM enrolled successfully"
echo ""

echo "[Step 2/3] Verifying TPM enrollment..."

if ! @cryptsetup@ luksDump "$CREDSTORE_DEVICE" | grep -q "systemd-tpm2"; then
  echo "[ERROR] TPM token not found in LUKS header after enrollment"
  exit 5
fi

echo "TPM configuration:"
@cryptsetup@ luksDump "$CREDSTORE_DEVICE" | grep -A 4 "systemd-tpm2" | sed 's/^/  /'
echo "[OK] TPM enrollment verified"
echo ""

echo "[Step 3/3] Creating enrollment marker..."
mkdir -p "$(dirname "$MARKER_FILE")"
cat > "$MARKER_FILE" <<EOF
Enrollment completed: $(date -Iseconds)
Method: standalone-tpm
SecureBoot: enabled
TPM PCRs: $TPM_PCRS
Note: Manual enrollment via keystone-enroll-tpm
EOF
echo "[OK] Enrollment marker created"
echo ""

cat <<'EOF'
+-------------------------------------------------------------------------+
|  TPM ENROLLMENT COMPLETE                                                |
+-------------------------------------------------------------------------+
|                                                                         |
|  Your system will now unlock automatically during boot when TPM         |
|  measurements match the enrolled PCR values.                            |
|                                                                         |
|  Test with: sudo reboot                                                |
|                                                                         |
+-------------------------------------------------------------------------+

EOF

echo "TPM automatic unlock is now configured."
