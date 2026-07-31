# Convention: Headscale ACL generation (os.headscale-acl)

Standards for auto-generating Headscale ACL rules from keystone service
topology. ACL rules, tag ownership, and service tags are derived
declaratively from `keystone.services` and `keystone.hosts`.

## Tag naming

1. Service tags MUST follow the pattern `tag:svc-{service}` for server
   roles and `tag:svc-{service}-{role}` for specialized workers (e.g.,
   `tag:svc-immich`, `tag:svc-immich-ml`).
2. Infrastructure tags (`tag:server`, `tag:agent`, `tag:ocean-ingress`)
   remain manually assigned in static ACL config.
3. Service tags MUST be auto-registered by the service module via
   `keystone.os.tailscale.tags`.

## Identity model

4. In Headscale, a node is either **user-owned** (e.g., `ncrmro@`) or
   **tag-owned**. Adding tags converts a node from user-owned to
   tag-owned, which strips the user identity.
5. Client-role hosts (`keystone.hosts.*.role == "client"`) MUST NOT
   receive service tags. Tags would strip their user identity and break
   admin access rules like `ncrmro@ -> *:*`.
6. Server-role and agent-role hosts MAY receive service tags because they
   are already tag-based (`tagged-devices` user in Headscale).
7. ACL destinations for client-role workers MUST use `{primaryUser}@:{port}`
   instead of `tag:svc-*:{port}`.

## Tag application (pre-auth key vs user-owned)

8. Headscale 0.28+ processes `--advertise-tags` differently depending on
   how the node was registered:
   - **Pre-auth key nodes** (servers, agents — registered as
     `tagged-devices`): tags are locked at registration time. The client
     `tailscale up --advertise-tags` flag is **ignored**.
   - **User-owned nodes** (clients — registered as `ncrmro`): tags can
     be changed via `tailscale up --advertise-tags` if `tagOwners`
     permits.
9. Tags on pre-auth key nodes MUST be set via `headscale nodes tag` on
   the headscale host (mercury), not via `tailscale up` on the node.
10. After changing tags via `headscale nodes tag`, the headscale service
    MUST be restarted for ACL rules to take effect.
11. The `keystone.os.tailscale.tags` option in NixOS modules sets
    `extraUpFlags` which only works for user-owned nodes. For pre-auth
    key nodes, the declared tags serve as documentation of intent — the
    actual application requires the headscale CLI.

### Applying tags to a pre-auth key node

```bash
# On mercury (headscale host):
# 1. Find the node ID
sudo headscale nodes list

# 2. Set tags (replaces all existing tags)
sudo headscale nodes tag -i <NODE_ID> \
  -t tag:server,tag:ocean-email,tag:ocean-ingress,tag:svc-immich

# 3. Restart headscale to apply ACL changes
sudo systemctl restart headscale
```

## Auto-generation flow

12. Service modules (e.g., `immich.nix`) MUST register their tailscale
    tags on server/agent hosts via `keystone.os.tailscale.tags`.
13. `keystone.services.generatedACLRules` and
    `keystone.services.generatedTagOwners` MUST be populated in
    `modules/services.nix` based on the service topology.
14. The headscale host (mercury) consumes these via
    `keystone.headscale.aclRules` and
    `keystone.headscale.generatedTagOwners`, which are merged with
    static rules by the `headscale-acl` import module.
15. Tag owners for auto-generated tags MUST be set to `{primaryUser}@`,
    derived from the first key in `keystone.os.users`.
16. Ports in ACL rules MUST be derived from the service definition, not
    hardcoded in the ACL generation logic.

## Golden example

Given this service topology:

```nix
keystone.services = {
  immich.host = "ocean";            # role = "server" -> gets tag:svc-immich
  immich.workers = [ "workstation" ]; # role = "client" -> stays user-owned
};
```

The generated ACL rule is:

```json
{
  "src": ["tag:svc-immich"],
  "dst": ["ncrmro@:3003"]
}
```

If the worker were a server-role host instead:

```json
{
  "src": ["tag:svc-immich"],
  "dst": ["tag:svc-immich-ml:3003"]
}
```
