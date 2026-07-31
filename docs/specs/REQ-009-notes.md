# REQ-009: Notes Sync

Home Manager module (`keystone.notes`) for managing a user's notes repository
with automated git synchronization. Portable across NixOS and macOS.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Configuration

**REQ-009.1** The module MUST expose `keystone.notes.enable` (bool, default
`false`) to activate notes management.

**REQ-009.2** The module MUST expose `keystone.notes.repo` (string) for the
git remote URL. This option is REQUIRED when `enable` is `true`.

**REQ-009.3** The module MUST expose `keystone.notes.path` (path, default
`~/notes`) for the local checkout location.

**REQ-009.4** The module MUST expose `keystone.notes.syncInterval` (string,
default `*:0/5`) as a systemd `OnCalendar` expression controlling sync
frequency.

### Sync Script

**REQ-009.5** The sync script MUST clone `keystone.notes.repo` to
`keystone.notes.path` if the directory does not already exist, then proceed
with the normal sync sequence. This eliminates the need for a separate
first-boot service.

**REQ-009.6** The module MUST install the sync script as a Nix derivation
that performs the following sequence: clone if missing, fetch from remote,
detect local and upstream changes, stage and commit local changes, rebase
onto upstream, push.

**REQ-009.7** Automatic commits MUST use the message format
`vault sync: YYYY-MM-DD HH:MM:SS`.

**REQ-009.8** The sync script MUST detect rebase conflicts, abort the rebase
to leave the repository in a clean state, write a conflict marker file, and
exit with a non-zero status.

**REQ-009.9** The sync script MUST use atomic directory-based locking
(`mkdir`) to prevent concurrent runs. A stale lock (process no longer running)
SHOULD be automatically cleaned up.

**REQ-009.10** The sync script MUST write per-run log files and structured
JSON metadata (timestamp, exit code, duration) to a logs directory.

**REQ-009.11** The sync script MUST rotate logs, keeping only the last N runs
(default 10). Both the `.log` and `.json` files for a run MUST be rotated
together.

### Integration

**REQ-009.12** The sync script MUST be a standalone derivation so that both
human Home Manager profiles and OS agent profiles (see SPEC-007) can import
it without duplicating logic.

**REQ-009.13** SPEC-007 agent-space sync SHOULD adopt this shared sync script
in place of its current inline implementation.

### Portability

**REQ-009.14** The module MUST NOT depend on NixOS-specific features. It MUST
use Home Manager primitives (systemd user services on Linux, launchd on
macOS in the future).

**REQ-009.15** The module MAY provide launchd plist generation for macOS
support as a future extension.

### Daily note rollover

**REQ-009.16** The module MUST expose `keystone.notes.daily.enable` (bool,
default `false`) to opt into git-tracked daily note rollover.

**REQ-009.17** When `keystone.notes.daily.enable = true`, the notes sync path
MUST ensure the configured daily entrypoint (default `daily.md`) is a relative
symlink to a dated note under the configured journal directory (default
`journal/YYYY-MM-DD.md`) before the final sync pass commits and pushes changes.

**REQ-009.18** The module MUST create the dated target note if it does not yet
exist, so a day rollover can be committed even before the user manually edits
the new file.

**REQ-009.19** If the daily entrypoint already exists as a regular file on the
same day the feature is enabled, the module MUST migrate that content into the
dated target note before replacing the entrypoint with a symlink.

**REQ-009.20** On first run, when the notes repo is cloned by the sync path,
the module MUST perform an additional sync pass after daily rollover so the
newly-created symlink change is committed and pushed without waiting for the
next timer tick.

**REQ-009.21** `keystone.notes.daily.symlinkPath` and
`keystone.notes.daily.journalPath` MUST stay under `keystone.notes.path`. The
module MUST reject absolute paths and parent-directory traversal segments such
as `..`.

**REQ-009.22** The rollover helper MUST fail fast when the configured daily
entrypoint resolves to the same path as the derived dated target note, so it
cannot replace a real note with a symlink.
