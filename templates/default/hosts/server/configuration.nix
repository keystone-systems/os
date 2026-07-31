{ ... }:
{
  # Optional server-specific overrides.
  #
  # This file is the right place for per-server firewall rules, backup agents,
  # monitoring, or service-specific tuning that should not affect other hosts.
  #
  # Keystone's terminal module already ships git, helix, and the core CLI
  # environment — no need to add them here.

  # Example:
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
