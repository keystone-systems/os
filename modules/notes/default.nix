# Keystone Notes — Home Manager module  [EXPERIMENTAL]
#
# EXPERIMENTAL: This module is not part of the stable v1 surface.
# It may change significantly or be restructured in future releases.
#
# Syncs a git-backed notes repository on a timer using repo-sync.
# Optionally initializes a zk Zettelkasten notebook structure.
# Used by both human users and agents.
#
# See conventions/tool.zk.md
# See conventions/process.knowledge-management.md
# Implements REQ-009
# See docs/specs/REQ-018-repo-management.md
#
# Usage:
#   keystone.notes = {
#     enable = true;
#     repo = "git@github.com:user/notes.git";
#     zk.enable = true;
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.keystone.notes;
  pathHasParentTraversal = path: builtins.elem ".." (lib.splitString "/" path);
  sshAuthSock =
    if
      lib.hasAttrByPath [
        "keystone"
        "terminal"
        "ssh"
        "authSock"
      ] config
    then
      config.keystone.terminal.ssh.authSock
    else
      "%t/ssh-agent";

  # Canonical .zk/config.toml content for the Zettelkasten notebook.
  # This is written to the notes repo (not /nix/store) so it travels with git.
  zkConfigToml = ''
    [note]
    id = "{{format-date now '%Y%m%d%H%M'}}"
    filename = "{{id}} {{slug title}}"
    extension = "md"

    [format.markdown]
    link-format = "wiki"
    hashtags = true

    [group.fleeting]
    paths = ["inbox"]
    [group.fleeting.note]
    template = "fleeting.md"

    [group.literature]
    paths = ["literature"]
    [group.literature.note]
    template = "literature.md"

    [group.permanent]
    paths = ["notes"]
    [group.permanent.note]
    template = "permanent.md"

    [group.decision]
    paths = ["decisions"]
    [group.decision.note]
    template = "decision.md"

    [group.index]
    paths = ["index"]
    [group.index.note]
    template = "index.md"

    [lsp.diagnostics]
    wiki-title = "hint"
    dead-link = "error"
  '';

  notesGitignore = ''
    # zk local index state
    .zk/notebook.db
    .zk/notebook.db-journal

    # Local shell and environment state
    .direnv/
    .env
    .env.local
    .venv/
    __pycache__/

    # Nix local outputs
    result
    result-*

    # OS/editor junk
    .DS_Store
    Thumbs.db
  '';

  # Template: fleeting note
  templateFleeting = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: fleeting
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    tags: []
    ---

    # {{title}}

    {{content}}
  '';

  # Template: literature note
  templateLiterature = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: literature
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    source: ""
    source_url: ""
    tags: []
    ---

    # {{title}}

    ## Summary



    ## Key Points

    -

    ## Links

    -
  '';

  # Template: permanent note
  templatePermanent = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: permanent
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    tags: []
    ---

    # {{title}}



    ## Links

    -
  '';

  # Template: decision record
  templateDecision = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: decision
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    status: proposed
    supersedes: ""
    tags: [decision]
    ---

    # {{title}}

    ## Context



    ## Decision



    ## Consequences



    ## Links

    -
  '';

  # Template: index note (Map of Content)
  templateIndex = ''
    ---
    id: "{{id}}"
    title: "{{title}}"
    type: index
    created: {{format-date now '%Y-%m-%dT%H:%M:%S%z'}}
    author: {{env.USER}}
    tags: [index]
    ---

    # {{title}}

    ## Notes

    -
  '';

  # Scaffold script: creates .zk/ structure if absent
  zkScaffoldScript = pkgs.writeShellScript "zk-scaffold" ''
    NOTES_PATH="${cfg.path}"

    if [ ! -d "$NOTES_PATH/.zk" ]; then
      echo "Scaffolding zk notebook at $NOTES_PATH"

      # Initialize zk (creates .zk/ directory)
      ${pkgs.zk}/bin/zk init --no-input "$NOTES_PATH"

      # Write canonical config
      cat > "$NOTES_PATH/.zk/config.toml" << 'ZKEOF'
    ${zkConfigToml}
    ZKEOF

      cat > "$NOTES_PATH/.gitignore" << 'IGNOREEOF'
    ${notesGitignore}
    IGNOREEOF

      # Create template directory and files
      mkdir -p "$NOTES_PATH/.zk/templates"

      cat > "$NOTES_PATH/.zk/templates/fleeting.md" << 'TPLEOF'
    ${templateFleeting}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/literature.md" << 'TPLEOF'
    ${templateLiterature}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/permanent.md" << 'TPLEOF'
    ${templatePermanent}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/decision.md" << 'TPLEOF'
    ${templateDecision}
    TPLEOF

      cat > "$NOTES_PATH/.zk/templates/index.md" << 'TPLEOF'
    ${templateIndex}
    TPLEOF

      # Create note directories with .gitkeep
      for dir in inbox literature notes decisions index; do
        mkdir -p "$NOTES_PATH/$dir"
        touch "$NOTES_PATH/$dir/.gitkeep"
      done

      echo "zk notebook scaffolded successfully"
    else
      echo "zk notebook already exists at $NOTES_PATH/.zk — skipping scaffold"
    fi

    # Fix permissions for agent-admins group access (setgid + group-writable)
    if [ -d "$NOTES_PATH/.zk" ]; then
      chmod -R g+w "$NOTES_PATH/.zk"
      chmod g+s "$NOTES_PATH/.zk"
    fi
  '';

  dailyRolloverScript = pkgs.writeShellScript "keystone-notes-daily-rollover" ''
    set -euo pipefail

    NOTES_PATH=${lib.escapeShellArg cfg.path}
    DAILY_REL=${lib.escapeShellArg cfg.daily.symlinkPath}
    JOURNAL_REL=${lib.escapeShellArg cfg.daily.journalPath}
    TODAY_FILE_NAME="$(date +${lib.escapeShellArg cfg.daily.dateFormat}).md"

    DAILY_PATH="$NOTES_PATH/$DAILY_REL"
    JOURNAL_PATH="$NOTES_PATH/$JOURNAL_REL"
    TARGET_REL="$JOURNAL_REL/$TODAY_FILE_NAME"
    TARGET_PATH="$NOTES_PATH/$TARGET_REL"

    if [[ ! -d "$NOTES_PATH/.git" ]]; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/mkdir -p \
      "$JOURNAL_PATH" \
      "$(${pkgs.coreutils}/bin/dirname "$DAILY_PATH")"

    # Use -ms (no-symlinks) so this guard only catches lexical aliasing
    # of the configured paths (a real misconfiguration). With plain -m,
    # once daily.md is a symlink to today's journal target, realpath
    # follows it and the guard fires every subsequent run.
    DAILY_REAL="$(${pkgs.coreutils}/bin/realpath -ms "$DAILY_PATH")"
    TARGET_REAL="$(${pkgs.coreutils}/bin/realpath -ms "$TARGET_PATH")"

    if [[ "$DAILY_REAL" == "$TARGET_REAL" ]]; then
      echo "keystone-notes-daily-rollover: daily.symlinkPath resolves to today's journal target; refusing to replace the note with a symlink" >&2
      exit 1
    fi

    if [[ -L "$DAILY_PATH" ]] && [[ "$(${pkgs.coreutils}/bin/readlink "$DAILY_PATH")" == "$TARGET_REL" ]]; then
      if [[ ! -e "$TARGET_PATH" ]]; then
        : > "$TARGET_PATH"
      fi
      exit 0
    fi

    if [[ -e "$DAILY_PATH" ]] && [[ ! -L "$DAILY_PATH" ]]; then
      if [[ "$(${pkgs.coreutils}/bin/realpath -m "$DAILY_PATH")" != "$(${pkgs.coreutils}/bin/realpath -m "$TARGET_PATH")" ]]; then
        if [[ ! -e "$TARGET_PATH" ]]; then
          ${pkgs.coreutils}/bin/mv "$DAILY_PATH" "$TARGET_PATH"
        else
          if ! ${pkgs.diffutils}/bin/cmp -s "$DAILY_PATH" "$TARGET_PATH"; then
            printf '\n' >> "$TARGET_PATH"
            ${pkgs.coreutils}/bin/cat "$DAILY_PATH" >> "$TARGET_PATH"
          fi
          ${pkgs.coreutils}/bin/rm -f "$DAILY_PATH"
        fi
      fi
    fi

    if [[ ! -e "$TARGET_PATH" ]]; then
      : > "$TARGET_PATH"
    fi

    TMP_LINK="$DAILY_PATH.tmp"
    ${pkgs.coreutils}/bin/ln -sfn "$TARGET_REL" "$TMP_LINK"
    ${pkgs.coreutils}/bin/mv -Tf "$TMP_LINK" "$DAILY_PATH"
  '';

  notesSyncScript = pkgs.writeShellScript "keystone-notes-sync" ''
    set -euo pipefail

    NOTES_GIT_DIR=${lib.escapeShellArg "${cfg.path}/.git"}

    repo_sync() {
      ${pkgs.keystone.repo-sync}/bin/repo-sync \
        --repo ${lib.escapeShellArg cfg.repo} \
        --path ${lib.escapeShellArg cfg.path} \
        --commit-prefix ${lib.escapeShellArg cfg.commitPrefix} \
        --log-dir ${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/notes-sync/logs"}
    }

    if [[ ! -d "$NOTES_GIT_DIR" ]]; then
      repo_sync

      # First-run daily rollover needs a second sync pass because repo-sync is
      # responsible for the initial clone.
      ${lib.optionalString cfg.daily.enable ''
        ${dailyRolloverScript}
        repo_sync
      ''}
    else
      ${lib.optionalString cfg.daily.enable ''
        ${dailyRolloverScript}
      ''}
      repo_sync
    fi
  '';
in
{
  imports = [ ../shared/experimental.nix ];

  options.keystone.notes = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.keystone.experimental;
      description = "Enable Keystone notes sync (EXPERIMENTAL). Auto-enabled when keystone.experimental = true.";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Git repository URL for the notes repo. Empty disables sync.";
      example = "git@github.com:user/notes.git";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/notes";
      description = "Local checkout path for the notes repo.";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/5";
      description = "Systemd calendar spec for the sync timer. Default: every 5 minutes.";
    };

    commitPrefix = lib.mkOption {
      type = lib.types.str;
      default = "vault sync";
      description = "Commit message prefix used by repo-sync.";
    };

    sync = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the systemd sync service and timer. Disable when another mechanism handles sync (e.g. NixOS-level agent sync).";
      };
    };

    daily = {
      enable = lib.mkEnableOption "git-tracked daily note rollover";

      symlinkPath = lib.mkOption {
        type = lib.types.str;
        default = "daily.md";
        description = "Path to the current daily note entrypoint, relative to the notes repo root.";
      };

      journalPath = lib.mkOption {
        type = lib.types.str;
        default = "journal";
        description = "Directory for dated daily notes, relative to the notes repo root.";
      };

      dateFormat = lib.mkOption {
        type = lib.types.str;
        default = "%Y-%m-%d";
        description = "Format string passed to date(1) when deriving the dated daily note filename.";
      };
    };

    zk = {
      enable = lib.mkEnableOption "zk Zettelkasten notebook initialization";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.daily.enable [
      {
        assertion =
          !lib.hasPrefix "/" cfg.daily.symlinkPath && !pathHasParentTraversal cfg.daily.symlinkPath;
        message = "keystone.notes.daily.symlinkPath must stay under keystone.notes.path and must not contain '..' segments.";
      }
      {
        assertion =
          !lib.hasPrefix "/" cfg.daily.journalPath && !pathHasParentTraversal cfg.daily.journalPath;
        message = "keystone.notes.daily.journalPath must stay under keystone.notes.path and must not contain '..' segments.";
      }
    ];

    systemd.user.services.keystone-notes-sync = lib.mkIf (cfg.sync.enable && cfg.repo != "") {
      Unit = {
        Description = "Sync notes repo via repo-sync";
      };

      Service = {
        Type = "oneshot";
        Environment = [
          "SSH_AUTH_SOCK=${sshAuthSock}"
        ];
        ExecStart = "${notesSyncScript}";
      };
    };

    systemd.user.timers.keystone-notes-sync = lib.mkIf (cfg.sync.enable && cfg.repo != "") {
      Unit = {
        Description = "Timer for notes repo sync";
      };

      Timer = {
        OnCalendar = cfg.syncInterval;
        Persistent = true;
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };

    # Scaffold zk notebook structure on activation (if enabled and not already present)
    home.activation.zkScaffold = lib.mkIf cfg.zk.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Only scaffold if the notes repo directory exists (it may not be cloned yet)
        if [ -d "${cfg.path}" ]; then
          ${zkScaffoldScript}
        fi
      ''
    );
  };
}
