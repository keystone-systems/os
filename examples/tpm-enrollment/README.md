# TPM Enrollment Module Example

This directory contains example configurations for using the Keystone TPM enrollment module.

## Using TPM Enrollment in Your Flake

If you're consuming Keystone modules from an external flake:

```nix
# flake.nix
{
  description = "My NixOS configuration with Keystone TPM enrollment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    keystone = {
      url = "github:ncrmro/keystone";
      # Or use a specific version:
      # url = "github:ncrmro/keystone/v1.0.0";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, keystone, disko, ... }: {
    nixosConfigurations.mySystem = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        # Required: disko for disk management
        disko.nixosModules.disko

        # Required: Keystone modules
        keystone.nixosModules.diskoSingleDiskRoot
        keystone.nixosModules.secureBoot
        keystone.nixosModules.tpmEnrollment

        # Your configuration
        {
          # Enable Keystone disk encryption
          keystone.disko = {
            enable = true;
            device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_...";
            swapSize = "16G";
          };

          # Enable Secure Boot (prerequisite for TPM)
          keystone.secureBoot.enable = true;

          # Enable TPM enrollment
          keystone.tpmEnrollment = {
            enable = true;
            # Optional: Customize PCR list
            tpmPCRs = [ 1 7 ];  # Default
          };

          # System configuration
          networking.hostName = "mySystem";
          networking.hostId = "abcd1234";
          system.stateVersion = "25.05";
        }
      ];
    };
  };
}
```

## Deployment Workflow

### 1. Build Installation ISO

```bash
# From Keystone repository
$ nix build .#iso

# Or with SSH keys for remote installation
$ ./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

### 2. Deploy to Target System

```bash
# Boot target system with Keystone ISO
# Get IP address from installer: ip addr show

# Deploy from your development machine
$ nixos-anywhere --flake .#mySystem root@<installer-ip>
```

### 3. First Boot - Complete TPM Enrollment

```bash
# SSH into deployed system
$ ssh root@<system-ip>

# You will see the enrollment warning banner
┌──────────────────────────────────────────────────────────────┐
│ ⚠️  TPM ENROLLMENT NOT CONFIGURED                            │
└──────────────────────────────────────────────────────────────┘

# Choose enrollment method
$ sudo keystone-enroll-recovery
# OR
$ sudo keystone-enroll-password

# Save your recovery credential securely

# Test automatic unlock
$ sudo reboot
```

### 4. Verify Automatic Unlock

After reboot, the system should unlock automatically without password prompt.

**Check enrollment status**:

```bash
$ sudo systemd-cryptenroll /dev/zvol/rpool/credstore
SLOT TYPE
   1 recovery  # or "password" if you chose custom password
   2 tpm2

$ cat /var/lib/keystone/tpm-enrollment-complete
Enrollment completed: 2025-11-03T14:32:15Z
Method: recovery-key
SecureBoot: enabled
TPM PCRs: 1,7
```

## Module Options Reference

```nix
keystone.tpmEnrollment = {
  # Enable the TPM enrollment module (default: false)
  enable = true;

  # List of TPM PCRs to bind disk unlock to (default: [1 7])
  # PCR 1: Firmware configuration
  # PCR 7: Secure Boot certificates
  tpmPCRs = [ 1 7 ];

  # Path to credstore LUKS volume (default: "/dev/zvol/rpool/credstore")
  # Must match the disko module configuration
  credstoreDevice = "/dev/zvol/rpool/credstore";
};
```

## PCR Configuration Examples

### Maximum Update Resilience

```nix
keystone.tpmEnrollment = {
  enable = true;
  tpmPCRs = [ 7 ];  # Secure Boot only
};
```

**Use When**:

- Frequent firmware/BIOS updates
- Experimental hardware (firmware instability)
- Home server with physical security

**Trade-off**: Slightly less protection against firmware-level attacks

### Balanced (Default)

```nix
keystone.tpmEnrollment = {
  enable = true;
  tpmPCRs = [ 1 7 ];  # Firmware config + Secure Boot
};
```

**Use When**:

- Standard deployment scenario
- Moderate firmware update frequency
- Balance between security and convenience

**Trade-off**: May require re-enrollment after BIOS setting changes

### Maximum Security

```nix
keystone.tpmEnrollment = {
  enable = true;
  tpmPCRs = [ 0 1 7 ];  # Firmware code + config + Secure Boot
};
```

**Use When**:

- High-security requirements
- Rare firmware updates
- Server in locked data center

**Trade-off**: Frequent re-enrollment needed (firmware updates, BIOS changes)

## Integration with Other Keystone Modules

### Server Configuration

```nix
{
  imports = [
    keystone.nixosModules.server
    keystone.nixosModules.diskoSingleDiskRoot
    keystone.nixosModules.secureBoot
    keystone.nixosModules.tpmEnrollment
  ];

  keystone.server.enable = true;
  keystone.disko.enable = true;
  keystone.secureBoot.enable = true;
  keystone.tpmEnrollment.enable = true;
}
```

### Client (Desktop) Configuration

```nix
{
  imports = [
    keystone.nixosModules.client
    keystone.nixosModules.diskoSingleDiskRoot
    keystone.nixosModules.secureBoot
    keystone.nixosModules.tpmEnrollment
  ];

  keystone.client.enable = true;
  keystone.disko.enable = true;
  keystone.secureBoot.enable = true;
  keystone.tpmEnrollment.enable = true;
}
```

## Files Included

- `configuration.nix`: Complete example NixOS configuration
- `README.md`: This file - usage guide and flake examples

## Additional Resources

- **User Documentation**: `/usr/share/doc/keystone/tpm-enrollment.md` (after installation)
- **Module Source**: `modules/tpm-enrollment/default.nix`
- **Specification**: `docs/specs/REQ-006-tpm-enrollment.md` (history in git for the original `_archive/006-tpm-enrollment/spec.md`)
- **Implementation Plan**: `docs/specs/REQ-006-tpm-enrollment.md` (history in git for the original `_archive/006-tpm-enrollment/plan.md`)
