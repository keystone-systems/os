#!/usr/bin/env bash
# Secure Boot Provisioning Script for NixOS Activation
# Generates and enrolls Secure Boot keys on first boot

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[SECURE BOOT]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[SECURE BOOT]${NC} $1"
}

log_error() {
    echo -e "${RED}[SECURE BOOT ERROR]${NC} $1" >&2
}

# Hardcoded configuration (no user options)
PKI_BUNDLE="/var/lib/sbctl"
INCLUDE_MS="false"  # Don't include Microsoft certificates
AUTO_ENROLL="true"  # Always auto-enroll

# Tool paths provided by activation script
SBCTL="${1:-sbctl}"  # Default to 'sbctl' if not provided
AWK="${2:-awk}"      # Default to 'awk' if not provided

# Setup Mode detection
check_setup_mode() {
    log_info "Checking UEFI Setup Mode status..."

    # Check if EFI variables are available
    if [ ! -d "/sys/firmware/efi/efivars" ]; then
        log_error "EFI variables not accessible - system may not be UEFI"
        return 2
    fi

    # Read SetupMode variable
    local setup_mode_var="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    if [ ! -f "$setup_mode_var" ]; then
        log_warn "SetupMode variable not found"
        return 1
    fi

    # Extract the value (last byte of the variable)
    local setup_mode_value
    setup_mode_value=$(od --address-radix=n --format=u1 "$setup_mode_var" 2>/dev/null | "$AWK" '{print $NF}')

    if [ "$setup_mode_value" = "1" ]; then
        log_info "System is in Setup Mode (ready for key enrollment)"
        return 0
    elif [ "$setup_mode_value" = "0" ]; then
        log_info "System is in User Mode (keys already enrolled)"
        return 1
    else
        log_warn "Unknown SetupMode value: $setup_mode_value"
        return 1
    fi
}

# Key generation function
generate_keys() {
    log_info "Generating Secure Boot keys..."

    # Check if keys already exist
    if [ -d "$PKI_BUNDLE/keys" ]; then
        log_info "Keys already exist at $PKI_BUNDLE/keys"
        return 0
    fi

    # Create PKI directory structure (sbctl will create subdirectories)
    log_info "Creating PKI directory at $PKI_BUNDLE"
    mkdir -p "$PKI_BUNDLE"

    # Generate keys using sbctl (keys are created in /var/lib/sbctl by default)
    log_info "Running sbctl to generate keys..."
    if ! "$SBCTL" create-keys; then
        log_error "Failed to generate keys with sbctl"
        return 1
    fi

    # Verify key generation
    local required_keys=("PK/PK.key" "PK/PK.pem" "KEK/KEK.key" "KEK/KEK.pem" "db/db.key" "db/db.pem")
    for key_file in "${required_keys[@]}"; do
        if [ ! -f "$PKI_BUNDLE/keys/$key_file" ]; then
            log_error "Missing required key file: $key_file"
            return 1
        fi
    done

    log_info "Successfully generated Secure Boot keys at $PKI_BUNDLE/keys"
    return 0
}

# Key enrollment function
enroll_keys() {
    log_info "Enrolling Secure Boot keys in UEFI firmware..."

    # Build enrollment command arguments
    local enroll_args="enroll-keys --yes-this-might-brick-my-machine"

    if [ "$INCLUDE_MS" = "true" ]; then
        enroll_args="$enroll_args --microsoft"
        log_info "Including Microsoft certificates for dual-boot compatibility"
    fi

    # Enroll the keys
    if ! "$SBCTL" $enroll_args; then
        log_error "Failed to enroll keys"
        return 1
    fi

    log_info "Successfully enrolled Secure Boot keys"
    return 0
}

# Main execution
main() {
    log_info "Starting Secure Boot provisioning"

    # Check if sbctl binary exists and is executable
    if [ ! -x "$SBCTL" ]; then
        log_error "sbctl not found or not executable at: $SBCTL"
        log_error "This is a configuration error - sbctl should be provided by the activation script"
        exit 2
    fi

    # Check if keys already exist and are valid
    if [ -d "$PKI_BUNDLE/keys" ] && [ -f "$PKI_BUNDLE/keys/db/db.pem" ]; then
        log_info "Secure Boot keys already exist, skipping generation"
        exit 0
    fi

    # Check Setup Mode status
    if ! check_setup_mode; then
        local setup_mode_status=$?
        if [ "$setup_mode_status" -eq 2 ]; then
            log_error "EFI system not detected - Secure Boot requires UEFI"
            log_error "This system cannot use Secure Boot"
            exit 3
        elif [ "$setup_mode_status" -eq 1 ]; then
            log_error "System not in Setup Mode but Secure Boot keys are missing!"
            log_error "This indicates a configuration problem:"
            log_error "  - Secure Boot was enabled but keys were never generated"
            log_error "  - Or firmware was reset after deployment"
            log_error ""
            log_error "To fix: Reset UEFI to Setup Mode and rebuild"
            exit 4
        fi
    fi

    # Generate keys
    if ! generate_keys; then
        log_error "Key generation failed - cannot continue"
        # Clean up partial state
        if [ -d "$PKI_BUNDLE" ] && [ ! -f "$PKI_BUNDLE/keys/db/db.pem" ]; then
            log_warn "Cleaning up incomplete PKI directory"
            rm -rf "$PKI_BUNDLE"
        fi
        exit 5
    fi

    # Enroll keys if auto-enrollment is enabled
    if [ "$AUTO_ENROLL" = "true" ]; then
        if ! enroll_keys; then
            log_error "Key enrollment failed"
            exit 6
        fi
    else
        log_info "Auto-enrollment disabled - keys generated but not enrolled"
        log_info "Run 'sbctl enroll-keys' manually to complete setup"
    fi

    log_info "Secure Boot provisioning completed successfully"
    log_info "Keys stored at: $PKI_BUNDLE/keys"
}

# Execute main function
main "$@"
