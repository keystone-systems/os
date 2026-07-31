# SSH Keys Configuration Examples
#
# This file demonstrates various SSH key configuration patterns for Keystone servers.
# SSH public key authentication is the only supported authentication method for security.
#
# All examples use the same configuration structure:
#   users.users.root.openssh.authorizedKeys.keys = [ "key1" "key2" ... ];

{ config, pkgs, ... }:

{
  # Example 1: Single SSH Key (Development/Testing)
  # ================================================
  # Simplest configuration - one developer, one machine
  #
  # users.users.root.openssh.authorizedKeys.keys = [
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJlZ... developer@laptop"
  # ];

  # Example 2: Multiple Keys for One Person (Recommended)
  # ======================================================
  # Best practice: separate keys for different devices/purposes
  #
  # Benefits:
  # - Can revoke individual keys if a device is lost/stolen
  # - Audit logs show which device was used for access
  # - Can set different restrictions per key if needed
  #
  # users.users.root.openssh.authorizedKeys.keys = [
  #   # Workstation (primary)
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJlZ... alice@workstation"
  #
  #   # Laptop (secondary)
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNlY... alice@laptop"
  #
  #   # Emergency access (offline backup key)
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVtZ... alice@emergency"
  # ];

  # Example 3: Team Access (Small Team)
  # ====================================
  # Multiple team members with individual accountability
  #
  # Benefits:
  # - Each team member has their own key
  # - Can identify who accessed the system in logs
  # - Easy to revoke access when team members leave
  #
  users.users.root.openssh.authorizedKeys.keys = [
    # Alice (DevOps Lead)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFsaWNlIGRldm9wcyBsZWFkIGtleQ== alice@workstation"

    # Bob (Senior Engineer)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJvYiBzZW5pb3IgZW5naW5lZXIga2V5 bob@laptop"

    # Carol (SRE)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGNhcm9sIHNyZSBlbmdpbmVlciBrZXk= carol@workstation"
  ];

  # Example 4: Service Accounts and Automation
  # ===========================================
  # Add keys for automated systems and monitoring
  #
  # users.users.root.openssh.authorizedKeys.keys = [
  #   # Human administrators
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFkbWluIGh1bWFuIGtleQ== admin@workstation"
  #
  #   # Backup system (automated)
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJhY2t1cCBzeXN0ZW0ga2V5 backup@backup-server"
  #
  #   # Monitoring agent (read-only operations)
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGRhdGFkb2cgYWdlbnQga2V5 monitoring@datadog"
  #
  #   # CI/CD deployment (GitHub Actions)
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdpdGh1YiBhY3Rpb25zIGRlcGxveSBrZXk= deploy@github-actions"
  # ];

  # Example 5: Hardware Security Keys (YubiKey)
  # ============================================
  # Using hardware tokens for high-security environments
  #
  # Best practice: use two YubiKeys (primary + backup) with color stickers
  # to tell them apart. YubiKey sells sticker packs for this purpose.
  #
  # Generate resident SSH key on each YubiKey:
  #   ssh-keygen -t ed25519-sk -O resident -O application=ssh:alice-yubi-black -C "alice-yubi-black"
  #   ssh-keygen -t ed25519-sk -O resident -O application=ssh:alice-yubi-green -C "alice-yubi-green" -f ~/.ssh/id_ed25519_sk_yubi_green
  #
  # The -sk suffix indicates a security key (FIDO2/U2F)
  # The -C flag sets the comment to the key color name (not user@hostname)
  # The -O application=ssh:<name> namespaces the credential on the YubiKey
  #
  # users.users.root.openssh.authorizedKeys.keys = [
  #   # Primary YubiKey (black, daily carry)
  #   "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9w... alice-yubi-black"
  #
  #   # Backup YubiKey (green sticker, stored in safe)
  #   "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9w... alice-yubi-green"
  # ];

  # Example 6: Restricted Keys (Advanced)
  # ======================================
  # Apply restrictions to specific keys
  # NOTE: This requires additional configuration beyond authorizedKeys
  #
  # For command restrictions, use openssh's authorized_keys options:
  #
  # users.users.root.openssh.authorizedKeys.keys = [
  #   # Full access admin key
  #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFkbWluIGZ1bGwgYWNjZXNz admin@workstation"
  #
  #   # Restricted key - only allow specific command
  #   ''command="/usr/bin/backup-script.sh",no-pty ssh-ed25519 AAAAC3NzaC1... backup@server''
  #
  #   # Restricted key - from specific IP only
  #   ''from="192.168.1.100" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... monitoring@internal''
  # ];

  # SSH Key Management Best Practices
  # ==================================

  # 1. Key Generation:
  #    - Use ed25519 for new keys: ssh-keygen -t ed25519 -C "user@host"
  #    - Use strong passphrases for private keys
  #    - Store private keys securely (never commit to Git)
  #    - Consider hardware security keys for critical systems

  # 2. Key Rotation:
  #    - Rotate keys annually or after security incidents
  #    - Remove keys of departed team members immediately
  #    - Keep audit log of key changes in version control
  #    - Test new keys before removing old ones

  # 3. Key Organization:
  #    - Use descriptive comments: "user@hostname-purpose"
  #    - Group keys by purpose (humans, services, emergency)
  #    - Document key owners in team documentation
  #    - Maintain inventory of which keys access which systems

  # 4. Security:
  #    - Never share private keys between people or systems
  #    - Store private keys encrypted (ssh-agent, gpg-agent)
  #    - Use SSH certificates for large organizations
  #    - Enable SSH key signing where appropriate

  # 5. Emergency Access:
  #    - Maintain offline emergency access keys
  #    - Store emergency keys in secure vault (1Password, Vault, etc.)
  #    - Document emergency access procedures
  #    - Test emergency access quarterly

  # Common Mistakes to Avoid
  # =========================

  # ❌ DON'T: Use the same key everywhere
  # ✅ DO: Use different keys for different systems/purposes

  # ❌ DON'T: Share private keys via email/Slack
  # ✅ DO: Each person generates their own key pair

  # ❌ DON'T: Commit private keys to Git
  # ✅ DO: Only commit public keys (.pub files)

  # ❌ DON'T: Use keys without passphrases
  # ✅ DO: Protect private keys with strong passphrases

  # ❌ DON'T: Use RSA keys smaller than 4096 bits
  # ✅ DO: Use ed25519 for modern systems

  # ❌ DON'T: Forget to remove keys of departed team members
  # ✅ DO: Regular access audits and key cleanup

  # Testing SSH Key Access
  # =======================

  # After adding keys, verify they work:
  #
  # 1. Test connection:
  #    ssh root@server-ip
  #
  # 2. Verify which key was used:
  #    ssh -v root@server-ip 2>&1 | grep "Offering public key"
  #
  # 3. Test from specific key:
  #    ssh -i ~/.ssh/specific_key root@server-ip
  #
  # 4. Check authorized keys on server:
  #    cat /root/.ssh/authorized_keys

  # Troubleshooting
  # ===============

  # Connection refused:
  #   - Check SSH service: systemctl status sshd
  #   - Verify firewall: nft list ruleset | grep 22
  #   - Check network connectivity: ping server-ip

  # Permission denied:
  #   - Verify public key is in authorized_keys
  #   - Check file permissions on server (600 for authorized_keys)
  #   - Try verbose mode: ssh -vvv root@server-ip
  #   - Verify private key file permissions (600)

  # Wrong key being used:
  #   - Specify key explicitly: ssh -i ~/.ssh/correct_key root@server-ip
  #   - Check SSH agent: ssh-add -l
  #   - Remove unwanted keys from agent: ssh-add -d ~/.ssh/unwanted_key

  # Additional Configuration
  # ========================

  # For this example file to work in a real deployment,
  # you would also need the full Keystone configuration:

  networking.hostName = "ssh-example-server";

  keystone = {
    disko = {
      enable = true;
      device = "/dev/vda"; # Adjust for your environment
    };
    server.enable = true;
  };

  time.timeZone = "UTC";
  system.stateVersion = "24.11";
}

# How to Use This Example
# ========================
#
# 1. Choose the example that matches your use case
# 2. Copy the relevant users.users.root.openssh.authorizedKeys.keys section
# 3. Replace the example keys with your actual public keys
# 4. Add to your configuration (vms/*/configuration.nix or examples/*.nix)
# 5. Deploy with nixos-anywhere
#
# For generating your SSH key:
#   ssh-keygen -t ed25519 -C "your-email@example.com"
#
# Your public key will be in: ~/.ssh/id_ed25519.pub
# Copy the entire contents of that file into the configuration
