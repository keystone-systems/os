busctl_command="${KEYSTONE_POWER_BUSCTL:-busctl}"
systemctl_command="${KEYSTONE_POWER_SYSTEMCTL:-systemctl}"
settle_seconds="${KEYSTONE_POWER_SETTLE_SECONDS:-1}"

login1_property() {
  local property="$1"
  local value

  value="$(timeout 5s "$busctl_command" --system --timeout=2s get-property \
    org.freedesktop.login1 \
    /org/freedesktop/login1 \
    org.freedesktop.login1.Manager \
    "$property" 2>/dev/null)" || return 1

  case "$value" in
    "b true") printf 'true\n' ;;
    "b false") printf 'false\n' ;;
    *) return 1 ;;
  esac
}

sleep "$settle_seconds"

lid_closed="$(login1_property LidClosed)" || exit 0
[[ "$lid_closed" == true ]] || exit 0

# Hibernate only when undocked is positively confirmed. A failed dock query
# must not interrupt a closed-lid docked session.
docked="$(login1_property Docked)" || exit 0
[[ "$docked" == false ]] || exit 0

printf 'Lid remains closed and host is undocked after suspend-then-hibernate; hibernating.\n'
exec "$systemctl_command" hibernate
