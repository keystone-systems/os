# Keystone SSH Public Key Registry
#
# Single source of truth for all SSH public keys across users and agents.
#
# ## Host keys (software)
#
# Each user/agent has one ed25519 key per host, declared under `hosts.<hostname>`.
# These keys are generated locally on each machine and NEVER leave that host.
# The private key must be password-protected and loaded via ssh-agent — keystone's
# sshAutoLoad service handles this automatically using agenix-managed passphrases.
#
# ## Hardware keys
#
# FIDO2/YubiKey keys declared under `hardwareKeys.<name>`. These are portable
# physical tokens that work across any host — signing requires physical touch
# on the device. Hardware keys can also carry an age identity for agenix
# secrets encryption via age-plugin-yubikey.
#
# ## Consumers
#
# This registry feeds: authorized_keys, git signing, git allowed_signers,
# root SSH access, installer ISO keys, and Forgejo key registration.
#
{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.keystone.keys;
in
{
  options.keystone.keys = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }:
        {
          options = {
            allKeys = mkOption {
              type = types.listOf types.str;
              readOnly = true;
              description = "All SSH public keys for this user (host + hardware). Computed automatically.";
            };

            hostKeys = mkOption {
              type = types.listOf types.str;
              readOnly = true;
              description = "Software host SSH public keys for this user. Computed automatically.";
            };

            hwKeys = mkOption {
              type = types.listOf types.str;
              readOnly = true;
              description = "Hardware SSH public keys for this user. Computed automatically.";
            };

            hosts = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options.publicKey = mkOption {
                    type = types.str;
                    description = "SSH ed25519 public key for this host.";
                    example = "ssh-ed25519 AAAAC3... user@hostname";
                  };
                }
              );
              default = { };
              description = "Per-host software SSH keys. One key per host, password-protected, loaded via ssh-agent.";
            };

            hardwareKeys = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    publicKey = mkOption {
                      type = types.str;
                      description = "SSH public key (sk-ssh-ed25519 or sk-ecdsa-sha2-nistp256).";
                    };
                    description = mkOption {
                      type = types.str;
                      default = "";
                      description = "Human-readable description (e.g. color, form factor).";
                    };
                    ageIdentity = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "age-plugin-yubikey identity string for agenix secrets.";
                    };
                  };
                }
              );
              default = { };
              description = "Portable hardware keys (FIDO2/YubiKey). Work across all hosts, require physical touch.";
            };
          };

          config = {
            hostKeys = mapAttrsToList (_: h: h.publicKey) config.hosts;
            hwKeys = mapAttrsToList (_: h: h.publicKey) config.hardwareKeys;
            allKeys = config.hostKeys ++ config.hwKeys;
          };
        }
      )
    );
    default = { };
    description = "SSH public key registry. Declare keys once per user/agent, consume everywhere.";
  };

  config = {
    assertions =
      # Agents must have exactly one host key
      (concatLists (
        mapAttrsToList (
          name: u:
          optional (hasPrefix "agent-" name && length (attrNames u.hosts) != 1) {
            assertion = false;
            message = "Agent '${name}' must have exactly one host key in keystone.keys, found ${toString (length (attrNames u.hosts))}";
          }
        ) cfg
      ))
      ++
        # Agents should not have hardware keys
        (concatLists (
          mapAttrsToList (
            name: u:
            optional (hasPrefix "agent-" name && u.hardwareKeys != { }) {
              assertion = false;
              message = "Agent '${name}' should not have hardware keys in keystone.keys";
            }
          ) cfg
        ));
  };
}
