# Convention: Privileged approval flow (process.privileged-approval)

Standards for requesting, approving, and executing privileged commands on
Keystone hosts. The canonical flow is terminal-first: a user or agent starts
the request from the terminal, then a local desktop approval prompt authorizes
the specific command.

This convention defines the policy and future module contract. It does not
require the approval broker to exist yet.

## Core flow

1. Privileged Keystone operations MUST use an approval-aware terminal flow,
   not an unstructured `sudo` prompt.
2. The canonical future entrypoint MUST be:
   ```bash
   ks approve --reason "<reason>" -- <command> [args...]
   ```
3. The approval flow MUST begin in the terminal or agent session that wants to
   run the command, even when the actual approval UI is desktop-visible.
4. When a graphical session is available, the system MUST show a desktop PAM or
   polkit-style approval popup for the request.
5. When no graphical session is available, the system SHOULD fall back to a
   terminal approval prompt while preserving the same command, host, and reason
   semantics.

## Dialog and execution requirements

1. The approval UI MUST show the exact command and argv that will run.
2. The approval UI MUST show the target host, or `local` when the command runs
   on the current machine.
3. The approval UI MUST show a short human-readable reason string.
4. Approval MUST be scoped to one explicit command entry. A successful approval
   MUST NOT grant broad shell access or a reusable root session.
5. The execution layer MUST reject commands that are not declared in the
   allowlist before any approval prompt is shown.

## Authentication methods

1. The approval flow MUST support password-based approval.
2. The approval flow MUST support hardware-key approval.
3. Hardware-key approval MAY require physical touch or equivalent presence
   confirmation.
4. The command policy MUST be identical regardless of whether the user approves
   with a password or a hardware key.

## Agent behavior

1. Agents MUST ask for permission in chat before requesting any privileged
   Keystone operation.
2. The request MUST include the exact command, target host, and reason.
3. Agents MUST treat `ks update`, `ks update --dev`, `ks switch`, and other
   host-mutating Keystone commands as approval-gated operations.
4. Agents MUST NOT run raw `sudo` as a substitute for the approval-aware flow
   once `ks approve` exists.
5. Until `ks approve` exists, agents MUST still ask the human before invoking
   privileged Keystone operations directly.

## Future Nix module contract

1. Keystone SHOULD expose the approval system under
   `keystone.security.privilegedApproval`.
2. The module MUST provide an `enable` option.
3. The module MUST provide a `backend` option. The initial documented backend
   SHOULD be `desktop-pam`.
4. The module MUST provide a `commands` option containing explicit allowlist
   entries.
5. Each allowlist entry MUST support these fields:
   - `name`
   - `command`
   - `displayName`
   - `reason`
   - `runAs`
   - `approvalMethods`
6. `command` MUST be an exact argv list or an explicit template, not a coarse
   per-binary grant.
7. `approvalMethods` MUST support `password` and `hardware-key`.

## Keystone command policy

1. Keystone host updates SHOULD be exposed through allowlisted commands rather
   than unrestricted shell access.
2. `ks update` MUST be treated as approval-gated.
3. `ks update --dev` MUST be treated as approval-gated.
4. `ks switch` MUST be treated as approval-gated.
5. `ks build` SHOULD remain the non-mutating verification path and SHOULD NOT
   require privileged approval by default.

## Future requirement

1. Keystone SHOULD add remote privileged approval backed by user-held secure
   hardware, such as Google Titan or Secure Enclave-backed credentials.
2. Remote approval is a TODO requirement for a future iteration and MUST NOT be
   assumed by the initial local approval design.
