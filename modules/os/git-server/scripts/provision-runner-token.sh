#!/usr/bin/env bash
set -euo pipefail

# Provision Forgejo Actions runner registration token.
#
# Environment variables expected:
#   FORGEJO_USER: System user running Forgejo (e.g. forgejo)
#   STATE_DIR: Forgejo state directory
#   API_URL: Forgejo API URL
#   TOKEN_FILE: Path to write the registration token (EnvironmentFile format)

# Idempotent: skip if token env-file already exists
if [ -f "${TOKEN_FILE}" ]; then
  echo "provision-runner-token: runner token already exists, skipping"
  exit 0
fi

FORGEJO_CMD="sudo -u ${FORGEJO_USER} forgejo --work-path ${STATE_DIR} admin"
API="${API_URL}"

# Auto-discover the first Forgejo admin user.
# --admin filters to admin accounts only; NR==2 skips the header row.
ADMIN_USER=$($FORGEJO_CMD user list --admin 2>/dev/null | awk 'NR==2{print $2}')

if [ -z "$ADMIN_USER" ]; then
  echo "provision-runner-token: ERROR — no admin user found in Forgejo"
  exit 1
fi

echo "provision-runner-token: using admin user '$ADMIN_USER'"

TEMP_TOKEN_NAME="provision-runner-temp-$(date +%s)-$$"
if ! ADMIN_TOKEN=$($FORGEJO_CMD user generate-access-token \
  --username "$ADMIN_USER" \
  --token-name "$TEMP_TOKEN_NAME" \
  --scopes "all" \
  --raw 2>&1); then
  echo "provision-runner-token: ERROR — could not generate admin API token"
  printf '%s\n' "$ADMIN_TOKEN" >&2
  exit 1
fi

AUTH="Authorization: token $ADMIN_TOKEN"

# Delete the short-lived admin token on exit (success or failure)
cleanup_token() {
  curl -svf -X DELETE -H "$AUTH" \
    "$API/users/$ADMIN_USER/tokens/$TEMP_TOKEN_NAME" || true
}
trap cleanup_token EXIT

if ! RUNNER_TOKEN_RESPONSE=$(curl -sf -H "$AUTH" \
  -X GET "$API/admin/runners/registration-token" 2>&1); then
  echo "provision-runner-token: ERROR — could not fetch runner registration token"
  printf '%s\n' "$RUNNER_TOKEN_RESPONSE" >&2
  exit 1
fi

RUNNER_TOKEN=$(printf '%s\n' "$RUNNER_TOKEN_RESPONSE" | jq -r '.token')
if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" = "null" ]; then
  echo "provision-runner-token: ERROR — could not fetch runner registration token"
  exit 1
fi

# Write as systemd EnvironmentFile (KEY=VALUE format) so the runner
# service can load it via EnvironmentFile=
echo "TOKEN=$RUNNER_TOKEN" > "${TOKEN_FILE}"
chmod 0600 "${TOKEN_FILE}"
echo "provision-runner-token: token written to ${TOKEN_FILE}"
