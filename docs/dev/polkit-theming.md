# Polkit theming smoke test

`bin/dev/test-polkit-theme.sh` exercises the end-to-end keystone polkit
dialog: theme JSON generation, `hyprpolkitagent` startup, QML render,
and `pkexec` round-trip. **It tests the theme files and
`write_polkit_theme()` from the current branch's working tree**, not
whatever the activated keystone happens to ship — so a developer can
iterate on a theming change and re-run the test without
`ks update --approve`.

Run it after any change that touches:

- `packages/hyprpolkitagent/` — the QML or its wrapper
- `modules/desktop/home/theming/default.nix` — the `write_polkit_theme`
  generator or theme-file copy maps
- `modules/os/privileged-approval.nix` — polkit policy / allowlist
- `modules/desktop/home/theming/themes/` — custom theme files
  (royal-green, etc.)
- `flake.lock` rev of upstream `omarchy` — colour values may shift

## Prerequisites

The test must run on a machine where keystone is already activated
(home-manager + system). It does not build keystone; it pokes the
already-installed agent and helper.

```sh
# Confirm the agent unit and helper exist
systemctl --user status hyprpolkitagent.service --no-pager
ls -l /run/current-system/sw/bin/keystone-approve-exec
```

If either is missing, finish a `ks update --approve` first.

## Theme source resolution

The script resolves theme files from the **branch's working tree**, not
the activated keystone. The search path, in order:

1. `$REPO_ROOT/modules/desktop/home/theming/themes/<name>/` — custom
   themes (royal-green, etc.) tracked in this repo.
2. `<branch-pinned-omarchy>/themes/<name>/` — omarchy themes resolved
   by `nix eval`-ing the branch's flake-locked `omarchy` input.

`$REPO_ROOT` is detected via `git rev-parse` from `$PWD`, or pass
`--repo PATH` (or `KEYSTONE_REPO=...`) to point at a different checkout.
Override the search path entirely with `--themes-dir DIR[:DIR]`
(or `KEYSTONE_THEMES_DIRS`).

The hyprpolkitagent that gets restarted is still the activated one —
QML changes need a real keystone build (e.g. `ks update --approve
--keystone path:$REPO_ROOT`) to land. This script is theme-only.

## Running

```sh
# From inside the keystone checkout, current theme, interactive
bin/dev/test-polkit-theme.sh

# Specific theme (resolved against the branch, not the activated keystone)
bin/dev/test-polkit-theme.sh --theme royal-green

# Cycle every theme the branch can produce — visually verify each
bin/dev/test-polkit-theme.sh --all

# CI-style: validate JSON + agent restart only, no dialog/password
bin/dev/test-polkit-theme.sh --headless --all

# Test a different keystone checkout without cd-ing into it
bin/dev/test-polkit-theme.sh --repo ~/repos/ncrmro/worktrees/keystone/feat/foo --all

# Recover after a killed run left the wrong polkit.json in place
bin/dev/test-polkit-theme.sh --reset
```

The script writes a snapshot to
`~/.config/keystone/current/polkit.json.test-snapshot` and restores it
in an `EXIT`/`INT`/`TERM` trap. If a run is killed before the trap fires,
`--reset` does the same restore manually.

## What it checks

| Stage | Pass criterion |
|---|---|
| `write_polkit_theme` | exits 0, produces parseable JSON |
| key coverage | all of `background`, `surface`, `border`, `accent`, `text`, `mutedText`, `placeholder`, `error`, `light` present |
| agent restart | `systemctl --user restart` returns 0 |
| journal scan (boot) | no `QQuickStyle`, no `qrc:/main.qml ... Error`, no XHR `forbidden`, no `ReferenceError` |
| `pkexec` round-trip | dialog appears; agent does not crash mid-dialog |
| visual confirmation | tester answers `y` to "did it render correctly?" |

`--headless` skips the last two and is what CI would run.

## Expected output (passing run, current theme)

```
[2026-…] ==> run started (themes: royal-green, headless=0)
[2026-…] ==> testing theme: royal-green (path: …/themes/royal-green)
[2026-…]   generated …/current/polkit.json
[2026-…]   json validated (all keys present)
  bg=rgb(0, 18, 12) surface=rgb(0, 18, 12) border=rgb(184, 162, 108) text=#B6BFBC
[2026-…]   agent restart clean (no QML/style errors in journal)

  >>> A polkit dialog should appear for theme 'royal-green'.
  …
[2026-…]   pkexec exited 0
  Did the dialog render correctly for 'royal-green'? [y/N] y
[2026-…] PASS [royal-green] (user-confirmed)
[2026-…] ==> run finished: 1 tested, 0 failed
```

## Common failures

**Black box, no text rendered.** QML loaded with the Material style and
fell back to defaults that paint over the theme. Check that the agent
wrapper sets `QT_QUICK_CONTROLS_STYLE=Basic` (or another non-Material
value). Confirm with `journalctl --user -u hyprpolkitagent | grep -i style`.

**Dialog appears but background looks wrong / too dark for theme.**
`write_polkit_theme` resolved the wrong source colour. The current
preference order is `hyprlock.conf $color` → `waybar.css @define-color
background` → `#111827` fallback. For themes where those two sources
disagree (royal-green, matte-black, osaka-jade), you'll want to confirm
which is the intended dialog brightness — hyprlock is tuned for a
full-screen lock and is darker; waybar is tuned for a panel and is
lighter.

**`pkexec exited 126/127`.** User cancelled or wrong password. Render
still happened; that's a pass for visual confirmation purposes.

**`pkexec exited 1`, dialog never appeared, terminal asks for password
instead.** No graphical session detected, or the polkit subject isn't
the calling shell. Make sure you're running from a Hyprland session,
not a tty / SSH.

**Journal shows `QML XMLHttpRequest: file:// access denied`.** The
agent wrapper isn't exporting `QML_XHR_ALLOW_FILE_READ=1`. Check
`packages/hyprpolkitagent/default.nix`.

**Journal shows `kvantum platformtheme`.** Harmless — Qt logs a notice
when kvantum is on `QT_QPA_PLATFORMTHEME` even though the agent
doesn't use it. The script's grep ignores this string.

## Adding a new theme

Theme directory layout (under
`modules/desktop/home/theming/themes/<name>/` for custom themes, or
omarchy's `themes/<name>/`):

| File | Used for | Required for polkit? |
|---|---|---|
| `hyprlock.conf` | `$color`, `$inner_color`, `$outer_color`, `$font_color`, `$placeholder_color` | yes |
| `waybar.css` | `@define-color foreground`, `@define-color gold`, `@define-color background` (fallback) | partial — fallback chain |
| `light.mode` | toggles `light: true` and the error red | no |

After adding the theme:

1. `bin/dev/test-polkit-theme.sh --theme <name>` from inside the branch
   checkout — no `ks update` needed; the script reads the new theme
   straight from the working tree.
2. `bin/dev/test-polkit-theme.sh --all` once before merging to confirm
   the addition didn't regress any sibling theme.

## Implementation note: single source of truth

The script builds and invokes `pkgs.keystone.write-polkit-theme` from
the branch's working tree. That's the same binary production uses
(both the home-manager activation hook and the `keystone-theme-switch`
wrapper call it), so the test exercises byte-for-byte what ships —
no in-script port to drift from the Nix definition.

The script does NOT shell out to the `keystone-theme-switch` wrapper
because that wrapper also restarts waybar, walker, mako, and reloads
hyprland on every theme switch — too noisy for a theme-only smoke
test. It only invokes the polkit-JSON binary directly.

## CI hookup (future)

`--headless --all` is the natural CI surface: it doesn't need a Wayland
session, doesn't prompt for a password, and exits non-zero on any
JSON or journal failure. The blocker for CI is that the test needs the
agent unit available, which today means a real keystone-activated
machine. Once we have a NixOS test VM that activates the desktop
profile, this script can run there.
