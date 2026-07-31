# Production Server Deployment Example
#
# This configuration demonstrates best practices for deploying a Keystone server
# to production hardware with stable device identifiers and secure configuration.
#
# Key differences from test configurations:
# - Uses /dev/disk/by-id/ paths for stable device identification
# - Multiple SSH keys for team access
# - Production-appropriate swap sizing
# - Timezone configuration
# - Additional security hardening options

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # System Identity
  # Use a descriptive hostname that identifies the system's purpose and location
  networking.hostName = "prod-server-01";
  networking.hostId = "deadbeef"; # Required for ZFS - generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '

  # Keystone OS Module
  # Enables OS-level services: storage, secure boot, TPM, SSH, mDNS, firewall
  keystone.os = {
    enable = true;

    # Storage Configuration
    storage = {
      type = "zfs";

      # CRITICAL: Use stable /dev/disk/by-id/ paths in production
      # Never use /dev/sda, /dev/nvme0n1, etc. as these can change on reboot
      #
      # To find your disk ID:
      #   ls -l /dev/disk/by-id/
      #
      # Look for entries like:
      #   ata-Samsung_SSD_870_EVO_2TB_S62ANL0W123456
      #   nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V
      #
      # Example NVMe disk:
      devices = [ "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V" ];

      # Example SATA SSD disk:
      # devices = ["/dev/disk/by-id/ata-Samsung_SSD_870_EVO_2TB_S62ANL0W123456"];

      # Example multiple disk mirrored scenario:
      # devices = [
      #   "/dev/disk/by-id/nvme-disk1"
      #   "/dev/disk/by-id/nvme-disk2"
      # ];
      # mode = "mirror";

      # Encrypted swap configuration
      # Swap size guideline:
      #   - 64G: Systems with 32GB RAM
      #   - 128G: Systems with 64GB+ RAM
      #   - Consider disabling for systems with abundant RAM (>128GB)
      swap.size = "64G";

      # EFI System Partition size
      # 1G is sufficient for most use cases
      # Only increase if using multiple boot entries or custom kernels
      esp.size = "1G";
    };

    # Enable Secure Boot with lanzaboote
    secureBoot.enable = true;

    # Enable TPM-based automatic disk unlock
    tpm = {
      enable = true;
      pcrs = [
        1
        7
      ]; # Firmware config + Secure Boot
    };
  };

  # SSH Access Configuration
  # SECURITY: Only use public key authentication
  # Multiple keys enable team access while maintaining individual accountability
  users.users.root.openssh.authorizedKeys.keys = [
    # Primary administrator
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJlZiVkZXYwMSBwcm9kLWFkbWluLTAxQGV4YW1wbGUuY29t admin-01@workstation"

    # Secondary administrator (on-call)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNlY29uZGFyeSBhZG1pbiBrZXkgZm9yIG9uLWNhbGwgYWNjZXNz admin-02@laptop"

    # Backup automation system
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJhY2t1cCBzeXN0ZW0gYXV0b21hdGVkIGFjY2Vzcw== backup-system@backup-01"

    # Monitoring system
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGRhdGFkb2cgbW9uaXRvcmluZyBhZ2VudCBhY2Nlc3M= monitoring@datadog"
  ];

  # System Configuration

  # Timezone - Set to your server's physical location or datacenter timezone
  time.timeZone = "America/New_York";
  # Other common timezones:
  # - "UTC" (recommended for distributed systems)
  # - "America/Los_Angeles"
  # - "Europe/London"
  # - "Asia/Tokyo"

  # Locale settings
  i18n.defaultLocale = "en_US.UTF-8";

  # Automatic security updates (optional but recommended)
  # The server module enables automatic-timers by default, which includes:
  # - Automatic garbage collection
  # - System optimization
  #
  # For production, consider enabling automatic system updates:
  # system.autoUpgrade = {
  #   enable = true;
  #   dates = "weekly";  # or "daily", "monthly"
  #   allowReboot = false;  # Set to true for automatic reboots (use with caution)
  #   channel = "https://nixos.org/channels/nixos-24.11";
  # };

  # Additional production hardening (optional)
  # security.sudo.wheelNeedsPassword = true;  # Require password for sudo
  # services.fail2ban.enable = true;  # Intrusion prevention

  # Network configuration
  # The server module configures firewall to allow only SSH by default
  # Add additional ports as needed:
  # networking.firewall.allowedTCPPorts = [ 80 443 ];  # HTTP/HTTPS
  # networking.firewall.allowedUDPPorts = [ 53 ];      # DNS

  # Resource limits (for systems with constrained resources)
  # nix.settings.max-jobs = 2;  # Limit concurrent builds
  # nix.settings.cores = 4;     # Cores per build job

  # Monitoring and logging
  # services.journald.extraConfig = ''
  #   SystemMaxUse=1G
  #   MaxRetentionSec=1week
  # '';

  # Description (appears in /etc/nixos/configuration.nix)
  system.stateVersion = "24.11"; # Don't change this after initial deployment
}

# Deployment Instructions
# ======================
#
# 1. Add this configuration to your flake.nix:
#
#    nixosConfigurations.prod-server-01 = nixpkgs.lib.nixosSystem {
#      system = "x86_64-linux";
#      modules = [
#        keystone.nixosModules.operating-system
#        ./examples/production-server.nix
#      ];
#    };
#
# 2. Verify configuration builds:
#
#    nix build .#nixosConfigurations.prod-server-01.config.system.build.toplevel
#
# 3. Boot target system from Keystone ISO
#
# 4. Deploy using nixos-anywhere:
#
#    nixos-anywhere --flake .#prod-server-01 root@<server-ip>
#
# 5. After deployment, verify with:
#
#    ./scripts/verify-deployment.sh prod-server-01 <server-ip>
#
# 6. On first boot (systems without TPM2):
#    - Enter a strong passphrase at the credstore unlock prompt
#    - Store this passphrase securely (password manager, vault, etc.)
#    - Document the passphrase location in your runbook
#
# Post-Deployment Security Checklist
# ==================================
#
# [ ] Verify SSH access works with authorized keys
# [ ] Confirm password authentication is disabled
# [ ] Test firewall rules (only required ports open)
# [ ] Verify ZFS pool is healthy: zpool status
# [ ] Confirm encryption is active: zfs get encryption rpool/crypt
# [ ] Set up monitoring and alerting
# [ ] Configure backup system
# [ ] Document server in infrastructure inventory
# [ ] Test disaster recovery procedure
# [ ] Schedule regular maintenance window
#
# Production Best Practices
# =========================
#
# 1. Configuration Management:
#    - Store configuration in version control
#    - Use feature branches for changes
#    - Test changes in staging environment first
#    - Document all customizations
#
# 2. Access Control:
#    - Use individual SSH keys (never shared keys)
#    - Rotate keys annually or when team members leave
#    - Use hardware security keys (YubiKey) for critical systems
#    - Enable 2FA for Git repository access
#
# 3. Backup Strategy:
#    - Regular ZFS snapshots (automated)
#    - Off-site backup replication
#    - Test restoration procedure quarterly
#    - Document recovery time objectives (RTO)
#
# 4. Monitoring:
#    - System health metrics (CPU, RAM, disk, network)
#    - ZFS pool health checks
#    - Service availability monitoring
#    - Log aggregation and analysis
#
# 5. Maintenance:
#    - Apply security updates promptly
#    - Monitor security advisories
#    - Regular configuration audits
#    - Capacity planning reviews
#
# 6. Disaster Recovery:
#    - Document recovery procedures
#    - Maintain offline copies of credentials
#    - Test DR procedures annually
#    - Keep hardware spare parts available
