# Keystone OS Agents Module
#
# Creates agent users with:
# - NixOS user accounts in the agents group (no sudo, no wheel)
# - UIDs from the 4000+ reserved range
# - Home directories at /home/agent-{name} (ZFS dataset or ext4)
# - chmod 700 isolation between agents
# - Headless Wayland desktop (labwc + wayvnc) for remote viewing
# - Terminal environment (zsh, helix, zellij, git)
# - Chromium browser with remote debugging + Chrome DevTools MCP
# - Stalwart mail account with himalaya CLI
# - Vaultwarden/Bitwarden integration with per-agent collections
# - Per-agent Tailscale instances with UID-based routing
# - SSH key management via agenix (ssh-agent + git signing)
#
# Usage:
#   keystone.domain = "ks.systems";
#   keystone.os.agents.researcher = {
#     fullName = "Research Agent";
#     email = "researcher@ks.systems";
#     # SSH public key declared in keystone.keys."agent-researcher"
#   };
#
# Fleet-wide declaration:
#   Consumer flakes using `mkSystemFlake` can declare agents once via
#   `shared.agents`; the template injects them into every host's
#   `keystone.os.agents`. Per-host `keystone.os.agents.<name>` entries merge
#   with the fleet set (module-system attrset merge), so hosts can add
#   host-only agents without losing the shared identities.
#
# Host filtering:
#   Agent identities are shared across all hosts (via `shared.agents` in
#   `mkSystemFlake`, or a common import like agent-identities.nix), but the
#   `host` field controls WHERE feature-specific resources are created:
#
#   ALWAYS created on every importing host (uses `cfg`, the full agent set):
#   - OS user/group accounts (agents need accounts for SSH access everywhere)
#   - Home directories
#   - User services guarded by ConditionUser (won't run unless logged in)
#
#   ONLY created on the agent's designated host (uses `localAgents`, filtered
#   by host == networking.hostName):
#   - SSH secrets + ssh-agent service (agenix assertions for private key/passphrase)
#   - Desktop environment (labwc, wayvnc)
#   - Mail client config (himalaya, mail-password assertion)
#   - Home Manager terminal environment
#
#   Created on SERVER hosts independently of `host` (mail.nix, git-server.nix):
#   - Mail account provisioning (where Stalwart runs, filtered by mail.provision)
#   - Git account provisioning (where Forgejo runs, filtered by git.provision)
#
#   Agenix implication: secrets like agent-{name}-mail-password may need
#   recipients on BOTH the agent's host (for himalaya) AND the server host
#   (for Stalwart provisioning). See agenix-secrets/secrets.nix.
#
# SSH: Each agent gets an ssh-agent systemd service that auto-loads its
# private key from agenix using the passphrase secret. Git is configured
# to sign commits with the SSH key. The agent's public key is added to
# its own ~/.ssh/authorized_keys for sandbox access.
#
# Security: VNC binds to 0.0.0.0 by default. Set desktop.vncBind = "127.0.0.1"
# for localhost-only. Use firewall rules or Tailscale ACLs to restrict access.
# wayvnc supports TLS but it is not yet configured here.
#
# CRITICAL: docs/agents.md documents the human-side tooling (agentctl, mail
# templates) for this module. Keep it in sync with any changes here.
#
{
  lib,
  config,
  ...
}:
with lib;
let
  typesLib = import ./types.nix { inherit lib config; };
in
{
  imports = [
    ./base.nix
    ./agentctl.nix
    ./desktop.nix
    ./chrome.nix
    ./dbus.nix
    ./mail-client.nix
    ./tailscale.nix
    ./ssh.nix
    ./notes.nix
    ./home-manager.nix
    ./observability.nix
    ./perception.nix
  ];

  options.keystone.os.agents = mkOption {
    type = types.attrsOf typesLib.agentSubmodule;
    default = { };
    description = ''
      Agent users with automatic NixOS user creation and home directory isolation.
      Agents are non-interactive users (no password login, no sudo) designed for
      LLM-driven autonomous operation.
    '';
    example = literalExpression ''
      {
        researcher = {
          fullName = "Research Agent";
          email = "researcher@ks.systems";
          # SSH public key declared in keystone.keys."agent-researcher"
        };
      }
    '';
  };
}
