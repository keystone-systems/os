#!/usr/bin/env bash
# Keystone TPM Enrollment: Custom Password Method
# Replaces default "keystone" password with user-chosen secure password

set -euo pipefail

# Configuration (substituted by NixOS module)
CREDSTORE_DEVICE="@credstoreDevice@"
TPM_PCRS="@tpmPCRs@"
MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"

# Password validation constants
MIN_LENGTH=12
MAX_LENGTH=64

# Parse arguments
AUTO_MODE=false
for arg in "$@"; do
    case $arg in
        --auto)
            AUTO_MODE=true
            ;;
        --help|-h)
            cat <<EOF
Keystone TPM Enrollment: Custom Password Method

Usage: keystone-enroll-password [--auto]

Options:
  --auto    Automatically execute enrollment commands (prompts for password)
  --help    Show this help message

Without --auto, this script shows the commands that would be executed.
With --auto, you will be prompted for a custom password to replace "keystone".
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

echo "=== Keystone TPM Enrollment: Custom Password ==="
echo ""

# Run prerequisite checks
echo "[Prerequisites]"

if ! @bootctl@ status 2>/dev/null | grep -q "Secure Boot:.*enabled"; then
  echo "[ERROR] Secure Boot is not enabled"
  exit 1
fi
echo "[OK] Secure Boot enabled"

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

# Show commands (with placeholder for custom password)
cat <<EOF
[Commands to Execute]

  [1] Add custom password to LUKS:
      $ echo -n "<new-password>" | cryptsetup luksAddKey $CREDSTORE_DEVICE \\
          --key-file <(echo -n "keystone")

  [2] Enroll TPM + Remove default password:
      $ systemd-cryptenroll $CREDSTORE_DEVICE \\
          --tpm2-device=auto \\
          --tpm2-pcrs=$TPM_PCRS \\
          --wipe-slot=password \\
          --unlock-key-file=<(echo -n "<your-new-password>")

      PCRs (Platform Configuration Registers):
        PCR 1: Firmware config (BIOS settings, hardware changes)
        PCR 7: Secure Boot state (enrolled keys)

      Re-enrollment needed if:
        * Hardware changes (motherboard, RAM, CPU) - PCR 1
        * BIOS settings changed - PCR 1
        * Secure Boot keys changed - PCR 7
        * TPM replaced

      Firmware/kernel updates: No re-enrollment (signed by same keys)

  [3] Create enrollment marker:
      $ cat > /var/lib/keystone/tpm-enrollment-complete

EOF

# If not auto mode, exit with instructions
if [ "$AUTO_MODE" = false ]; then
    cat <<EOF
[Manual Execution]

To execute these commands manually, copy them from above.
To execute automatically (with password prompts), run:
  $ sudo keystone-enroll-password --auto

Password requirements:
  * Minimum ${MIN_LENGTH} characters
  * Maximum ${MAX_LENGTH} characters
  * Cannot be "keystone"

EOF
    exit 0
fi

echo "[Auto-Execution Mode]"
echo ""

# Password validation function
validate_password() {
    local password="$1"
    local length="${#password}"

    if [[ -z "${password// /}" ]]; then
        echo "ERROR: Password cannot be empty"
        return 1
    fi

    if (( length < MIN_LENGTH )); then
        echo "ERROR: Password must be at least ${MIN_LENGTH} characters (current: ${length})"
        return 1
    fi

    if (( length > MAX_LENGTH )); then
        echo "ERROR: Password exceeds maximum of ${MAX_LENGTH} characters (current: ${length})"
        return 1
    fi

    if [[ "${password,,}" == "keystone" ]]; then
        echo "ERROR: Password 'keystone' is not allowed (publicly known)"
        return 1
    fi

    return 0
}

# Get and validate password
echo "[Step 1/4] Setting up custom password..."
echo ""
echo "Password requirements:"
echo "  * Minimum ${MIN_LENGTH} characters"
echo "  * Maximum ${MAX_LENGTH} characters"
echo "  * Cannot be 'keystone'"
echo ""

while true; do
    read -rsp "Enter new LUKS password: " password1
    echo ""

    if ! validate_password "$password1"; then
        echo ""
        continue
    fi

    read -rsp "Confirm password: " password2
    echo ""

    if [[ "$password1" != "$password2" ]]; then
        echo "ERROR: Passwords do not match. Try again."
        echo ""
        continue
    fi

    echo "[OK] Password validated (${#password1} characters)"
    break
done

NEW_PASSWORD="$password1"
echo ""

echo "[Step 2/4] Adding custom password to LUKS..."
echo "$ echo -n \"<new-password>\" | cryptsetup luksAddKey --key-file <(echo -n \"keystone\")"

if ! echo -n "$NEW_PASSWORD" | @cryptsetup@ luksAddKey \
    "$CREDSTORE_DEVICE" \
    --key-file <(echo -n "keystone") \
    -; then
    echo "[ERROR] Failed to add password to LUKS"
    exit 4
fi
echo "[OK] Custom password added"
echo ""

echo "[Step 3/3] Enrolling TPM and removing default password..."
echo ""
echo "PCRs (Platform Configuration Registers):"
echo "  PCR 1: Firmware config (BIOS settings, hardware changes)"
echo "  PCR 7: Secure Boot state (enrolled keys)"
echo ""
echo "This command will:"
echo "  * Enroll TPM for automatic unlock (PCRs: $TPM_PCRS)"
echo "  * Remove the default \"keystone\" password"
echo ""
echo "Re-enrollment needed if:"
echo "  * Hardware changes (motherboard, RAM, CPU) - PCR 1"
echo "  * BIOS settings changed - PCR 1"
echo "  * Secure Boot keys changed - PCR 7"
echo "  * TPM replaced"
echo ""
echo "Firmware/kernel updates: No re-enrollment needed (signed by same keys)"
echo ""
echo "$ systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=$TPM_PCRS --wipe-slot=password --unlock-key-file=<(echo -n \"<your-password>\")"
echo ""

if ! @systemd_cryptenroll@ \
  "$CREDSTORE_DEVICE" \
  --tpm2-device=auto \
  --tpm2-pcrs="$TPM_PCRS" \
  --wipe-slot=password \
  --unlock-key-file=<(echo -n "$NEW_PASSWORD"); then
  echo "[ERROR] TPM enrollment and password removal failed"
  echo ""
  echo "Your custom password is enrolled, but TPM not configured."
  echo ""
  echo "To retry:"
  echo "  sudo keystone-enroll-password --auto"
  exit 5
fi
echo "[OK] TPM enrolled and default password removed"
echo ""

echo "Creating enrollment marker..."
mkdir -p "$(dirname "$MARKER_FILE")"
cat > "$MARKER_FILE" <<EOF
Enrollment completed: $(date -Iseconds)
Method: custom-password
SecureBoot: enabled
TPM PCRs: $TPM_PCRS
Password length: ${#NEW_PASSWORD} characters
EOF
echo "[OK] Enrollment complete"
echo ""

cat <<'EOF'
+-------------------------------------------------------------------------+
|  TPM ENROLLMENT COMPLETE                                                |
+-------------------------------------------------------------------------+
|                                                                         |
|  Your system will now unlock automatically during boot.                 |
|                                                                         |
|  If automatic unlock fails, you can unlock with your custom password.  |
|  Test with: sudo reboot                                                |
|                                                                         |
+-------------------------------------------------------------------------+

EOF

echo "Enrollment complete! Your system is now secured with TPM automatic unlock."
