# Convention: Stalwart Mail Server (tool.stalwart)

Configuration and provisioning requirements for the Stalwart mail server within a
keystone fleet. Covers observability (Prometheus metrics), per-agent CalDAV calendar
and CardDAV addressbook provisioning, and team-shared DAV resources. All requirements
here are implemented by the keystone `modules/os/mail.nix` module — agents rely on
these guarantees without manual setup. Agent provisioning via `keystone.os.agents`
is a prerequisite for DAV provisioning (see `process.agentic-team`).

## Prometheus Metrics

1. The Stalwart service MUST expose Prometheus metrics on a dedicated HTTP listener at
   `127.0.0.1:9010` (Tailscale-only, not open to the public internet).

2. The Prometheus tracer MUST be enabled in Stalwart settings:

   ```nix
   services.stalwart-mail.settings = {
     tracer.prometheus = {
       type = "prometheus";
       enable = true;
     };
     server.listener.prometheus = {
       protocol = "http";
       bind = [ "127.0.0.1:9010" ];
     };
   };
   ```

3. The Grafana Alloy configuration on the mail host MUST scrape `http://127.0.0.1:9010/metrics`
   and forward to the fleet Prometheus instance.

4. Stalwart Prometheus metrics MUST be enabled by default in `modules/os/mail.nix` — no
   per-host `enable = true` is needed (see `process.enable-by-default` rules 1–2).

## Per-Agent CalDAV Calendar Provisioning

5. For every agent with `mail.provision = true`, a personal CalDAV calendar collection
   MUST be created at `/dav/cal/{agent-username}/personal/` on the mail server.
   Provisioning runs at system activation time — before user-session timers fire —
   so calendars are guaranteed present when the agent task loop pre-fetches sources
   (see `process.agent-cronjobs`, Task Loop section).

6. Calendar provisioning MUST be idempotent — the systemd provisioning service MUST
   check `PROPFIND /dav/cal/{user}/personal/` and skip creation if the calendar already
   exists (HTTP 207 = exists, HTTP 404 = needs creation).

7. Calendar creation MUST use the WebDAV `MKCALENDAR` method authenticated as the agent:

   ```bash
   # Check if calendar exists (207 = exists, 404 = needs creation)
   STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
     -X PROPFIND -u "${username}:${password}" \
     "http://127.0.0.1:${jmap_port}/dav/cal/${username}/personal/")

   if [ "$STATUS" = "404" ]; then
     curl -sf -X MKCALENDAR \
       -u "${username}:${password}" \
       -H "Content-Type: application/xml" \
       -d '<A:mkcalendar xmlns:D="DAV:" xmlns:A="urn:ietf:params:xml:ns:caldav">
             <D:set><D:prop><D:displayname>Personal</D:displayname></D:prop></D:set>
           </A:mkcalendar>' \
       "http://127.0.0.1:${jmap_port}/dav/cal/${username}/personal/"
   fi
   ```

8. The calendar provisioning service MUST authenticate as the agent user (not admin) —
   Stalwart's CalDAV namespace is per-user; admin auth is not valid for MKCALENDAR.

## Per-Agent CardDAV Addressbook Provisioning

9. For every agent with `mail.provision = true`, a personal CardDAV addressbook collection
   MUST be created at `/dav/card/{agent-username}/personal/` on the mail server.
   Like CalDAV provisioning, this runs at system activation before user-session timers
   (see `process.agent-cronjobs`, Task Loop section).

10. Addressbook provisioning MUST be idempotent — check existence via `PROPFIND` before
    issuing `MKCOL`.

11. Addressbook creation MUST use `MKCOL` with a `resourcetype` body declaring the
    `carddav:addressbook` type:
    ```bash
    curl -sf -X MKCOL \
      -u "${username}:${password}" \
      -H "Content-Type: application/xml" \
      -d '<?xml version="1.0" encoding="utf-8"?>
          <D:mkcol xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
            <D:set>
              <D:prop>
                <D:resourcetype><D:collection/><C:addressbook/></D:resourcetype>
                <D:displayname>Personal</D:displayname>
              </D:prop>
            </D:set>
          </D:mkcol>' \
      "http://127.0.0.1:${jmap_port}/dav/card/${username}/personal/"
    ```

## Team Calendar and Addressbook

12. A shared `team` principal MUST be provisioned in Stalwart to host fleet-wide shared
    resources. The team account MUST be created as an `individual` type with no email
    address and no mail role.

13. A team CalDAV calendar MUST exist at `/dav/cal/team/shared/` and a team CardDAV
    addressbook MUST exist at `/dav/card/team/shared/`.

14. All agents with `mail.provision = true` MUST be granted read-write access to the
    team calendar and team addressbook via CalDAV/CardDAV ACLs at provisioning time.

15. The team account password MUST be managed as an agenix secret (`stalwart-team-password`)
    with recipients including the mail server host key.

16. The team resources MUST be provisioned once by `modules/os/mail.nix` during system
    activation — the team account is fleet-wide, not per-agent.

## Agent Integration

17. After provisioning, agents MUST be able to list their personal calendar via
    `calendula calendars list` with no additional configuration — credentials are
    auto-derived from `keystone.terminal.mail` (see `os.requirements`).

18. Agents MUST be able to list their personal contacts via `cardamum addressbooks list`
    with no additional configuration (see `os.requirements`).

19. The team calendar URL MUST be surfaced as an environment variable
    (`KEYSTONE_TEAM_CALENDAR_URL`) so agents can subscribe to it without hardcoding paths.

20. Provisioning failures MUST NOT silently pass — the systemd provisioning service MUST
    exit with a non-zero status if any CalDAV/CardDAV creation step fails, causing the
    unit to appear in `systemctl --failed` and `ks doctor` output. Treat failed
    provisioning units as blockers (see `process.blocker`).

## Golden Example

End-to-end provisioning for agent `drago` on Stalwart at `mail.ncrmro.com`:

```bash
# 1. Variables (baked in at provisioning time by keystone)
USERNAME="agent-drago"
AGENT_PASS=$(cat /run/agenix/agent-drago-mail-password)
API="http://127.0.0.1:8082"

# 2. Personal calendar (check-then-create, idempotent)
CAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PROPFIND -u "$USERNAME:$AGENT_PASS" \
  "$API/dav/cal/$USERNAME/personal/")
if [ "$CAL_STATUS" = "404" ]; then
  curl -sf -X MKCALENDAR -u "$USERNAME:$AGENT_PASS" \
    -H "Content-Type: application/xml" \
    -d '<A:mkcalendar xmlns:D="DAV:" xmlns:A="urn:ietf:params:xml:ns:caldav">
          <D:set><D:prop><D:displayname>Personal</D:displayname></D:prop></D:set>
        </A:mkcalendar>' \
    "$API/dav/cal/$USERNAME/personal/"
  echo "$USERNAME: CalDAV calendar created"
fi

# 3. Personal addressbook (check-then-create, idempotent)
CARD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PROPFIND -u "$USERNAME:$AGENT_PASS" \
  "$API/dav/card/$USERNAME/personal/")
if [ "$CARD_STATUS" = "404" ]; then
  curl -sf -X MKCOL -u "$USERNAME:$AGENT_PASS" \
    -H "Content-Type: application/xml" \
    -d '<?xml version="1.0" encoding="utf-8"?>
        <D:mkcol xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
          <D:set><D:prop>
            <D:resourcetype><D:collection/><C:addressbook/></D:resourcetype>
            <D:displayname>Personal</D:displayname>
          </D:prop></D:set>
        </D:mkcol>' \
    "$API/dav/card/$USERNAME/personal/"
  echo "$USERNAME: CardDAV addressbook created"
fi

# 4. Verify with agent's tools
agentctl drago exec bash -c 'cd /tmp && calendula calendars list'
# → table showing the "Personal" calendar

agentctl drago exec bash -c 'cd /tmp && cardamum addressbooks list'
# → table showing the "Personal" addressbook
```

After provisioning completes, `calendula calendars list` returns a populated calendar
table and `cardamum addressbooks list` shows the personal addressbook — both without
any manual agent-side configuration beyond what keystone provides via home-manager.
