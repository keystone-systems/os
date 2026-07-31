# Keystone Host Registry
#
# Shared option declaring identity and connection metadata for all hosts in
# the infrastructure. Follows the same pattern as domain.nix and mail.nix —
# set once per infrastructure, consumed by multiple modules and deploy scripts.
#
# Usage:
#   keystone.hosts = {
#     ocean = {
#       hostname = "ocean";
#       sshTarget = "ocean.mercury";
#       fallbackIP = "192.168.1.10";
#       buildOnRemote = true;
#       hostPublicKey = "ssh-ed25519 AAAAC3...";
#     };
#   };
#
# Hosts with hostPublicKey are auto-added to /etc/ssh/ssh_known_hosts so that
# inter-host SSH (deploys, ZFS replication, etc.) works without manual keyscan.
#
# TODO: Auto-collect hostPublicKey during keystone install/setup (read from
# /etc/ssh/ssh_host_ed25519_key.pub and populate hosts.nix automatically).
#
# The `ks` CLI reads this data at runtime via: nix eval -f hosts.nix --json <host>
{ config, lib, ... }:
with lib;
let
  hsDomain = config.keystone.headscaleDomain;
  hostsWithKeys = filterAttrs (_: h: h.hostPublicKey != null) config.keystone.hosts;
in
{
  options.keystone.headscaleDomain = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Headscale MagicDNS base domain. When set, sshTarget defaults to hostname.domain for all hosts.";
    example = "mercury";
  };

  options.keystone.hosts = mkOption {
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            hostname = mkOption {
              type = types.str;
              description = "The networking.hostName of this host (may differ from flake config name).";
            };
            sshTarget = mkOption {
              type = types.nullOr types.str;
              default = if hsDomain != null then "${config.hostname}.${hsDomain}" else null;
              description = "SSH target for remote deploys. Auto-derived from hostname + headscaleDomain. Set to null for local-only hosts, or an IP for hosts without Tailscale.";
            };
            fallbackIP = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "LAN IP fallback when sshTarget is unreachable via Tailscale.";
            };
            tailscaleIP = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Stable Tailscale IPv4 address for this host when known.";
            };
            buildOnRemote = mkOption {
              type = types.bool;
              default = true;
              description = "Whether to pass --build-host for remote deploys (build on remote machine).";
            };
            role = mkOption {
              type = types.enum [
                "client"
                "server"
                "agent"
              ];
              description = "Tailscale network role for this host (mandatory).";
            };
            baremetal = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this host runs on physical hardware. False for VPS/cloud instances and VMs. Gates hardware-specific packages like lm_sensors.";
            };
            hostPublicKey = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "SSH host public key (/etc/ssh/ssh_host_ed25519_key.pub).";
            };
            journalRemote = mkOption {
              type = types.bool;
              default = false;
              description = "Whether this host is the centralized journal-remote server. Exactly one host should set this to true.";
            };
            zfs = mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    backups = mkOption {
                      type = types.attrsOf (
                        types.submodule {
                          options = {
                            targets = mkOption {
                              type = types.listOf types.str;
                              description = "Backup targets as 'host:pool' strings (e.g. 'maia:lake')";
                            };
                          };
                        }
                      );
                      default = { };
                      description = "Per-pool backup target declarations. Key is source pool name.";
                    };
                  };
                }
              );
              default = null;
              description = "ZFS backup topology for this host.";
            };
          };
        }
      )
    );
    default = { };
    description = ''
      Host identity and connection metadata for all NixOS hosts. Keys MUST match
      nixosConfigurations names in flake.nix. Consumed by the `ks` CLI (ks build, ks update).
    '';
  };

  # Populate /etc/ssh/ssh_known_hosts from hostPublicKey so inter-host SSH
  # (deploys, ZFS replication, etc.) verifies without manual ssh-keyscan.
  config.programs.ssh.knownHosts = mapAttrs' (
    name: hostCfg:
    nameValuePair name {
      publicKey = hostCfg.hostPublicKey;
      hostNames = filter (x: x != null) [
        hostCfg.hostname
        hostCfg.sshTarget
        hostCfg.tailscaleIP
        hostCfg.fallbackIP
      ];
    }
  ) hostsWithKeys;
}
