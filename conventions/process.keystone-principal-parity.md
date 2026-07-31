# Convention: Keystone Principal Parity (process.keystone-principal-parity)

Keystone manages two types of principals: human users (`keystone.os.users`) and
agents (`keystone.os.agents`). Both are first-class citizens of the platform.
Infrastructure capabilities — Forgejo tokens, mail accounts, SSH keys, CLI
configs, provisioning scripts — MUST be designed for all principal types from the
start, not implemented for one and retrofitted for the other. This convention
prevents the pattern where agents get full automation while humans are left with
"add a token manually after first deploy."

See `process.enable-by-default` rules 9-11 for the policy-level commitment to
agent/human environment parity. This convention defines the implementation
discipline that enforces that policy.

## Shared Implementation

1. Provisioning scripts MUST be principal-agnostic: a single parameterized script
   (or shared Nix helper function) MUST serve both agents and humans, with
   variant behavior controlled by environment variables or function arguments.
2. Developers MUST NOT create parallel scripts that duplicate core logic for
   different principal types (e.g., `provision-agent-git.sh` alongside
   `provision-user-git.sh`). Shared logic MUST be factored into one
   implementation.
3. When a new infrastructure capability is added for agents, the same capability
   MUST be simultaneously available to human users — either via the same code
   path or by explicit design decision documented in the PR.
4. When a new infrastructure capability is added for human users, agents MUST
   also be able to use it unless the capability is inherently human-specific
   (e.g., interactive password change).

## Option Symmetry

5. Submodule options that exist for agents (e.g., `git.provision`,
   `mail.provision`) MUST have equivalent options for human users in the
   `keystone.os.users` submodule, using consistent naming.
6. Home-manager bridges that flow config from OS modules into terminal modules
   MUST work identically for both principal types. If an agent gets
   `forgejo.{enable,domain,sshPort,username}` bridged, human users MUST get
   the same bridge.
7. Option defaults SHOULD follow the same policy for both principal types
   unless there is a documented reason for divergence (e.g., agents default to
   `must-change-password=false` because they never use the web UI).

## Divergence Documentation

8. When behavior intentionally differs between principal types, the divergence
   MUST be documented in a code comment at the point of divergence, explaining
   why.
9. Acceptable divergences include: agents needing auto-created repos, agents
   needing SSH key provisioning from agenix secrets, humans requiring password
   change on first web login, and service-account-specific scoping.
10. The PR description MUST call out any intentional divergence from principal
    parity, with rationale.

## Code Review

11. Reviewers MUST check whether a PR that adds or modifies agent-specific
    provisioning also addresses the equivalent human user path.
12. Reviewers MUST check whether a PR that adds or modifies user-specific
    features also addresses the equivalent agent path.
13. A PR that introduces a new provisioning script SHOULD be flagged if it
    creates a separate script per principal type rather than parameterizing a
    shared one.

## Golden Example

Before this convention — Forgejo API token provisioning existed only for agents:

```
modules/os/git-server/
  scripts/
    provision-agent-git.sh    # agents get tokens, SSH keys, repos
                              # humans get nothing — "add a token manually"
```

After this convention — a single parameterized script serves both:

```
modules/os/git-server/
  scripts/
    provision-forgejo.sh      # shared script, behavior driven by env vars
```

The Nix module passes different parameters for each principal type:

```nix
# Shared helper function
mkProvisionService = { name, systemUser, systemGroup, username, email,
                       tokenPrefix, mustChangePass,
                       sshPubkey ? null, repoName ? null,
                       adminUsers ? [] }: { ... };

# Agents — full provisioning (user + token + SSH key + repo + collaborators)
mapAttrs' (name: agentCfg: mkProvisionService {
  name = "agent-${name}";
  systemUser = "agent-${name}";
  systemGroup = "agents";
  tokenPrefix = "api-agent-${name}";
  mustChangePass = false;
  sshPubkey = agentPublicKey name;     # agent-specific: SSH key from agenix
  repoName = agentCfg.git.repoName;   # agent-specific: auto-created repo
  adminUsers = cfg.adminUsers;         # agent-specific: human collaborators
  # ...
}) provisionAgents

# Humans — core provisioning (user + token)
mapAttrs' (username: userCfg: mkProvisionService {
  name = username;
  systemUser = username;
  systemGroup = "users";
  tokenPrefix = "api-${username}";
  mustChangePass = true;               # human-specific: set password on first login
  # sshPubkey, repoName, adminUsers omitted — not needed for humans
}) provisionUsers
```

The divergences (SSH key, repo creation, password policy) are documented at the
call site, not hidden inside separate scripts.
