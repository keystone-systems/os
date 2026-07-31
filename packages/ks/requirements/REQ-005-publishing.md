# REQ-005: Publishing

This document defines requirements for committing and publishing the
generated configuration.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Initial Publishing (dev machine)

**REQ-005.1** The TUI MUST initialize a git repository in the output
directory and create an initial commit with the generated files.

**REQ-005.2** The TUI SHOULD offer to create a private GitHub repository
via `gh repo create` and push the initial commit.

**REQ-005.3** The TUI MUST configure the git remote with SSH URL format
(`git@github.com:owner/repo.git`).

**REQ-005.4** The TUI MUST warn the user if any generated file contains a
plaintext password (`initialPassword`) and recommend switching to
`hashedPassword` before publishing.

**REQ-005.5** The TUI MUST NOT commit files that contain secrets (e.g.,
private keys, tokens). Age-encrypted secrets MAY be committed.

### Post-Install Commit (target machine, ISO install)

**REQ-005.6** During ISO install, after `disko` mounts the target system
and before `nixos-install` begins, the TUI MUST create a local git
commit in the writable install repo.

**REQ-005.7** That install-time commit MUST include the reconciled
`hosts/<hostname>/hardware.nix` and any install-time config mutations
required to boot the installed system and continue onboarding.

**REQ-005.8** The TUI MUST NOT attempt to push during ISO install. The
ISO does not contain private SSH keys and push would fail.

**REQ-005.9** After the user configures SSH keys on the installed system
(first-boot Stage 6), the TUI MUST prompt the user to push the pending
install commit to the remote repository.
