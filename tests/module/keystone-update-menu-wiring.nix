# keystone-update-menu-wiring — cross-file coupling check for the Walker
# update provider.
#
# The original `tests/module/keystone-update-menu.nix` integration test was
# removed alongside the bash backend — it stubbed `gh`/`git`/`nix`/`ghostty`
# to exercise shell logic that no longer exists. State discovery and
# rendering are now covered by Rust unit tests in `cmd::update_menu::tests`.
# What those unit tests can't see is the *wiring* between files:
#
#   - keystone-update.lua must call `ks menu update …`.
#   - update_menu.rs::start_update_session must spawn the update via the
#     graphical-session app launcher (`uwsm app -- systemd-inhibit …
#     systemd-cat -t ks-update ks update --approve`), not via a user
#     systemd unit. The unit-based path was retired because it lost the
#     graphical session env that pkexec needs to reach hyprpolkitagent.
#   - system-flake.nix must write `/run/current-system/keystone-update-channel`
#     from `keystone.update.channel` so detached session apps have a stable
#     channel source without depending on session env freshness.
#   - The activation tokens emitted by entries_json (in Rust) must be the
#     same tokens dispatch matches on (in Rust) and the same tokens the
#     Lua provider feeds into the Action.
#
# If anyone renames the subcommand, drops the launcher, or edits activation
# tokens without the corresponding other-file update, this test fails
# loudly instead of silently breaking the desktop flow.
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  luaFile = ../../modules/desktop/home/components/keystone-update.lua;
  updateMenuRs = ../../packages/ks/src/cmd/update_menu.rs;
  repoRs = ../../packages/ks/src/repo.rs;
  updateChannelOption = ../../modules/shared/update.nix;
  systemFlakeFile = ../../modules/shared/system-flake.nix;
  terminalDefault = ../../modules/terminal/default.nix;
  mainMenuShell = ../../modules/desktop/home/scripts/keystone-main-menu.sh;
in
pkgs.runCommand "test-keystone-update-menu-wiring"
  {
    nativeBuildInputs = with pkgs; [
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "FAIL: $*" >&2
      exit 1
    }

    # -- Lua dispatches to `ks menu update` -------------------------------

    if ! grep -F 'ks") .. " menu update dispatch' ${luaFile} >/dev/null; then
      fail "keystone-update.lua must call 'ks menu update dispatch' on Action"
    fi
    if ! grep -F 'ks") .. " menu update entries' ${luaFile} >/dev/null; then
      fail "keystone-update.lua must call 'ks menu update entries' in GetEntries"
    fi

    # Guard against accidental regression to the legacy command name.
    if grep -F 'update-menu' ${luaFile} >/dev/null; then
      fail "keystone-update.lua still references the legacy 'update-menu' command"
    fi

    # -- update_menu.rs spawns the update as a session app, not a unit ----
    #
    # The retired `ks-update.service` path lost the graphical session env
    # pkexec needs to talk to hyprpolkitagent. start_update_session must
    # build a `uwsm app -- systemd-inhibit … systemd-cat -t ks-update
    # ks update --approve` argv so the update inherits DISPLAY /
    # WAYLAND_DISPLAY / DBUS_SESSION_BUS_ADDRESS from the session.

    if ! grep -F 'start_update_session' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must define start_update_session for the graphical-session app launch"
    fi
    if ! grep -F 'uwsm' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must launch the update via uwsm app -- … so it inherits the graphical session env"
    fi
    if ! grep -F -- '--identifier=ks-update' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must tag the session app with systemd-cat --identifier=ks-update for journal lookup"
    fi
    if ! grep -F 'systemd-inhibit' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must wrap the update in systemd-inhibit so suspend/shutdown can't wedge a switch"
    fi
    if ! grep -F '"--approve"' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs session-app argv must invoke ks update --approve"
    fi
    if ! grep -F 'KS_UPDATE_NOTIFY' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must set KS_UPDATE_NOTIFY=1 so ks main fires notify-send (replaces the retired ks-update-notify@ template)"
    fi

    # Guard against regression: the unit-based launcher is gone. If anyone
    # reintroduces `systemctl --user start ks-update.service` without first
    # solving the session-env problem, fail loudly.
    if grep -F 'ks-update.service' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must not reference ks-update.service — the unit was retired in favor of the uwsm session-app launcher"
    fi

    # -- Activation tokens defined in Rust match dispatch handling ---------
    #
    # The Lua provider's Action single-quotes %VALUE%, so every token
    # emitted by entries_json MUST be a stable string with no shell
    # metacharacters. These tokens are the entire shared vocabulary
    # between render_entries_json (producer) and dispatch (consumer).

    for tok in \
      '"noop"' \
      '"run-update"' \
      '"blocked-update-unavailable"' \
      '"blocked-keystone-unavailable"' \
      '"open-release-page"'; do
      if ! grep -F "$tok" ${updateMenuRs} >/dev/null; then
        fail "update_menu.rs is missing activation token $tok"
      fi
    done

    # -- Channel wiring ---------------------------------------------------
    #
    # The Rust backend resolves the channel from KS_UPDATE_CHANNEL first
    # (interactive shells / tests) and falls back to
    # /run/current-system/keystone-update-channel (detached session apps).
    # Three files have to agree:
    #
    #   - system-flake.nix writes the runtime pointer from
    #     config.keystone.update.channel so it is regenerated on every
    #     nixos-rebuild switch / boot.
    #   - terminal/default.nix exports KS_UPDATE_CHANNEL for interactive
    #     shells so `ks menu update status` from a terminal also tracks
    #     the declared channel.
    #   - update_menu.rs reads both paths via repo::read_system_update_channel
    #     plus an env lookup. Match the function so it can't be silently
    #     deleted.

    if ! grep -F 'keystone-update-channel' ${systemFlakeFile} >/dev/null; then
      fail "system-flake.nix must write /run/current-system/keystone-update-channel for runtime channel discovery"
    fi
    if ! grep -E 'config\.keystone\.update\.channel' ${systemFlakeFile} >/dev/null; then
      fail "system-flake.nix must source the runtime channel pointer from config.keystone.update.channel"
    fi

    # terminal/default.nix sets it as a home.sessionVariables attribute
    # whose value is `config.keystone.update.channel` (no string literal).
    if ! grep -E 'KS_UPDATE_CHANNEL[[:space:]]*=[[:space:]]*config\.keystone\.update\.channel' ${terminalDefault} >/dev/null; then
      fail "terminal/default.nix must set KS_UPDATE_CHANNEL = config.keystone.update.channel in home.sessionVariables"
    fi

    if ! grep -F 'KS_UPDATE_CHANNEL' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must read KS_UPDATE_CHANNEL for channel dispatch"
    fi
    if ! grep -F 'read_system_update_channel' ${updateMenuRs} >/dev/null; then
      fail "update_menu.rs must fall back to repo::read_system_update_channel when KS_UPDATE_CHANNEL is unset"
    fi
    if ! grep -F 'keystone-update-channel' ${repoRs} >/dev/null; then
      fail "repo.rs must read /run/current-system/keystone-update-channel as the runtime channel pointer"
    fi

    # -- Option exists somewhere under modules/ ---------------------------
    #
    # Pin the location: `modules/shared/update.nix` is the canonical
    # declaration file. If it moves, the test grep has to move too — the
    # failure explicitly tells maintainers which file to fix.

    if ! grep -F 'options.keystone.update' ${updateChannelOption} >/dev/null; then
      fail "modules/shared/update.nix must declare options.keystone.update (with .channel)"
    fi
    for tok in '"stable"' '"unstable"'; do
      if ! grep -F "$tok" ${updateChannelOption} >/dev/null; then
        fail "modules/shared/update.nix must list $tok in the channel enum"
      fi
    done

    # -- Top-level Walker menu delegates update to the dedicated submenu --
    #
    # CRITICAL: keystone-main-menu.sh emits a top-level "Update" entry that
    # parallels the dedicated keystone-update submenu's "Run update" action.
    # The top-level entry MUST delegate to `ks menu update dispatch`, NOT
    # spawn its own terminal — otherwise the two entry points diverge and
    # the top-level silently regresses to a terminal path while the
    # submenu uses the Lua→Rust dispatch. These greps are behavior-shaped:
    # they assert what the dispatch DOES, not just what tokens appear.

    # Strip comment-only lines before grepping, so the deprecation comment
    # documenting WHY this regression matters doesn't trip its own test.
    if grep -v '^[[:space:]]*#' ${mainMenuShell} | grep -E 'ghostty[[:space:]]+-e[[:space:]]+ks[[:space:]]+update' >/dev/null; then
      fail "keystone-main-menu.sh must not spawn a terminal for ks update — delegate to 'ks menu update dispatch'"
    fi
    if ! grep -F 'ks menu update dispatch' ${mainMenuShell} >/dev/null; then
      fail "keystone-main-menu.sh's run-update case must call 'ks menu update dispatch' to reuse the supervised flow"
    fi
    if grep -v '^[[:space:]]*#' ${mainMenuShell} | grep -F 'in a terminal' >/dev/null; then
      fail "keystone-main-menu.sh must not advertise 'in a terminal' in any subtext — Walker update path is silent + polkit"
    fi

    touch "$out"
  ''
