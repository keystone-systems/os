# Keystone OS Agents Observability Module
#
# Provisions Grafana dashboards and alerting rules for monitoring agent health,
# task completion rates, and blocked tasks.
#
{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf (config.keystone.os.enable && config.keystone.os.agents != { }) {
    # Shared keystone dashboards are provisioned by the server-side Grafana
    # service module so they are available even when the Grafana host does not
    # run local agents.
  };
}
