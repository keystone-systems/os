# REQ-021: cfait CalDAV Task Manager

Package cfait — a Rust-based terminal TUI for CalDAV task/TODO management — as
a Nix derivation and integrate it into the keystone terminal module. cfait
connects to the same Stalwart CalDAV backend already used by Calendula (events)
and Cardamum (contacts), completing the terminal PIM suite. Credentials
auto-inherit from the mail module so operators only need `enable = true`.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a Keystone operator, I want cfait packaged in the Nix flake and available as
a terminal module option, so that I can view and manage my CalDAV tasks visually
from the terminal without switching to a browser.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    keystone terminal module                      │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │ himalaya │  │calendula │  │ cardamum │  │    cfait      │   │
│  │  (mail)  │  │ (events) │  │(contacts)│  │   (tasks)     │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
│       │              │              │               │           │
│       │         credentials auto-inherit from mail  │           │
│       ▼              ▼              ▼               ▼           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              keystone.terminal.mail config               │   │
│  │     (host, login, passwordCommand, accountName)          │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            ▼
                ┌──────────────────────┐
                │   Stalwart Server    │
                │                      │
                │  IMAP  ──► himalaya  │
                │  SMTP  ──► himalaya  │
                │  CalDAV ──► calendula│
                │          ──► cfait   │
                │  CardDAV──► cardamum │
                └──────────────────────┘
```

## Affected Modules

- `flake.nix` — Add cfait as a Nix package (no upstream flake; build from crates.io or GitHub source)
- `modules/terminal/tasks.nix` — New module: cfait config generation + credential inheritance
- `modules/terminal/default.nix` — Import `tasks.nix`
- `modules/terminal/calendar.nix` — No changes (events remain separate from tasks)

## Requirements

### Packaging

**REQ-021.1** cfait MUST be packaged as a Nix derivation available at
`pkgs.keystone.cfait`.

**REQ-021.2** The package SHOULD be built from the upstream GitHub source
(`github:trougnouf/cfait`) using `rustPlatform.buildRustPackage` or equivalent
Rust builder.

**REQ-021.3** If the upstream repository provides a `flake.nix` in the future,
the packaging SHOULD migrate to a flake input following the Calendula pattern
(`inputs.nixpkgs.follows = "nixpkgs"`).

**REQ-021.4** The package MUST be added to the keystone overlay in `flake.nix`
alongside the existing pimalaya tools.

### Terminal Module

**REQ-021.5** A new module `modules/terminal/tasks.nix` MUST be created
following the same pattern as `calendar.nix`.

**REQ-021.6** The module MUST expose options at `keystone.terminal.tasks`.

**REQ-021.7** The module MUST be imported by `modules/terminal/default.nix`.

**REQ-021.8** When enabled, the module MUST add `pkgs.keystone.cfait` to
`home.packages`.

### Configuration

**REQ-021.9** The module MUST expose the following options with defaults
inherited from `keystone.terminal.mail`:

```nix
keystone.terminal.tasks = {
  enable = mkOption {
    type = types.bool;
    default = false;
    description = "Enable CalDAV task management TUI (cfait)";
  };

  host = mkOption {
    type = types.str;
    default = mailCfg.host;
    description = "CalDAV server hostname (defaults to mail host)";
  };

  login = mkOption {
    type = types.str;
    default = mailCfg.login;
    description = "CalDAV username (defaults to mail login)";
  };

  passwordCommand = mkOption {
    type = types.str;
    default = mailCfg.passwordCommand;
    description = "Command to retrieve the password (defaults to mail passwordCommand)";
  };

  url = mkOption {
    type = types.str;
    default = "";
    description = ''
      CalDAV endpoint URL. When empty, defaults to https://{host}/dav/cal
      (Stalwart). Set explicitly for external providers.
    '';
  };
};
```

**REQ-021.10** When `host` or `url` is configured, the module MUST generate
`~/.config/cfait/config.toml` via `xdg.configFile`.

**REQ-021.11** The generated config MUST include the CalDAV URL, username, and
password command in cfait's expected TOML format:

```toml
url = "https://{host}/dav/cal"
username = "{login}"
password = "{resolved-password}"
```

**REQ-021.12** The CalDAV URL derivation MUST follow the same pattern as
Calendula: use explicit `url` if set, otherwise build
`https://${cfg.host}/dav/cal` (Stalwart's direct path, bypassing
`/.well-known/caldav` discovery).

### Credential Inheritance

**REQ-021.13** All credential options (host, login, passwordCommand) MUST
default from `keystone.terminal.mail` so that Stalwart users need only
`enable = true`.

**REQ-021.14** Each credential option MAY be overridden individually for
non-Stalwart CalDAV providers (e.g., iCloud, Nextcloud).

### Password Handling

**REQ-021.15** cfait expects a plaintext password in its config, not a command.
The module MUST document this difference from Calendula's `password.command`
approach.

**REQ-021.16** If cfait supports a password command or environment variable
mechanism, the module SHOULD use that instead of writing plaintext passwords to
the config file.

**REQ-021.17** If cfait only supports plaintext passwords, the module SHOULD
use a wrapper script or activation hook that resolves the password command at
runtime and writes the config to a non-world-readable path.

### Integration

**REQ-021.18** cfait MUST coexist with Calendula without conflict — both
connect to the same CalDAV server but manage different resource types (VTODO vs
VEVENT).

**REQ-021.19** The module SHOULD follow the same guard pattern as calendar.nix:
`mkIf (config.keystone.terminal.enable && cfg.enable)`.

**REQ-021.20** Agent users with `terminal.enable = true` SHOULD be able to
enable cfait for CalDAV task management alongside their existing calendar and
contacts tools.

### Security

**REQ-021.21** The generated config file MUST NOT contain plaintext passwords
if cfait supports any alternative credential mechanism (command, keyring,
environment variable).

**REQ-021.22** If plaintext password is unavoidable, the config file MUST be
written with mode `0600` and the module MUST emit a warning explaining the
security implication.

## Edge Cases

- **No mail configured**: If `keystone.terminal.mail` is not enabled and no
  explicit credentials are provided, `host` defaults to `""` and no config file
  is generated (silent no-op, matching Calendula behavior).
- **iCloud**: Works with `url = "https://caldav.icloud.com"` and an
  App-Specific Password, same as Calendula.
- **Gmail**: NOT SUPPORTED — Google's CalDAV requires OAuth2, which cfait does
  not support via basic auth.
- **Stalwart PROPFIND issue**: Use direct path `/dav/cal` instead of discovery
  to avoid nginx 400 errors (same workaround as Calendula).

## Supersedes

This spec introduces a new module. It does not supersede any existing spec but
implements the "Package cfait TUI calendar client" user story from GitHub issue
#175 (Calendar Integration milestone).

## References

- GitHub issue #175 — Calendar Integration: User Stories for Review
- Milestone #3 — Calendar Integration
- [cfait upstream](https://github.com/trougnouf/cfait) — Rust CalDAV task manager
- [cfait on crates.io](https://crates.io/crates/cfait)
- `modules/terminal/calendar.nix` — Calendula integration (pattern to follow)
- `docs/specs/REQ-020-journal-remote.md` — Most recent spec for format reference
