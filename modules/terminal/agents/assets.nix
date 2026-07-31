{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
with lib;
let
  terminalCfg = config.keystone.terminal;
  isDev = config.keystone.development;
  isAgent = lib.hasPrefix "agent-" config.home.username;
  devScripts = import ../../shared/dev-script-link.nix { inherit lib; };
  repoCheckout = if isAgent then null else devScripts.resolveRepoCheckout config "keystone";
  # agentsLib reads `config.keystone.os.*`, so it must be constructed with the
  # NixOS config (osConfig), not the home-manager config tree.
  agentsLib =
    if osConfig != null then
      import ../../os/agents/lib.nix {
        inherit lib pkgs;
        config = osConfig;
      }
    else
      null;
  # `keystone.os.agents` is a NixOS-level option, not a home-manager option,
  # so reading it from `config` always returned { } here and the manifest
  # never reflected the host's agent set. Bridge via `osConfig` (the standard
  # home-manager pattern, used elsewhere in keystone for keystone.development
  # and keystone.repos) so the generated agent-assets.json matches reality.
  osAgents =
    if osConfig != null && osConfig.keystone ? os && osConfig.keystone.os ? agents then
      osConfig.keystone.os.agents
    else
      { };
  manifestRelPath = ".config/keystone/agent-assets.json";
  scriptRelPath = "modules/terminal/agents/keystone-sync-agent-assets.sh";
  scriptPackage = pkgs.writeShellScriptBin "keystone-sync-agent-assets" (
    builtins.readFile ./keystone-sync-agent-assets.sh
  );
  agentsWithMcp = mapAttrs (name: agentCfg: {
    inherit (agentCfg) host archetype;
    notesPath = agentCfg.notes.path;
    mcpServers = {
      deepwork = {
        command = "${pkgs.keystone.deepwork}/bin/deepwork";
        args = [
          "serve"
          "--path"
          "."
          "--platform"
          "claude"
        ];
      };
    }
    // optionalAttrs (agentCfg.chrome.enable && agentCfg.chrome.mcp.enable) {
      chrome-devtools = {
        command = "${pkgs.keystone.chrome-devtools-mcp}/bin/chrome-devtools-mcp";
        args = [
          "--browserUrl"
          "http://127.0.0.1:${toString (agentsLib.globalAgentChromeDebugPort name agentCfg)}"
        ];
      };
    };
  }) osAgents;
  # Consumer-flake agent-assets root. Skills/subagents are materialized here
  # by `ks sync-agent-assets`; home-manager activation symlinks each tool's
  # home-dir subdir into the corresponding path. See
  # conventions/tool.cli-coding-agents.md § "Consumer Flake Agent Assets".
  consumerFlakeAgents =
    if
      osConfig != null && osConfig.keystone ? systemFlake && osConfig.keystone.systemFlake.path != null
    then
      "${osConfig.keystone.systemFlake.path}/agents"
    else
      null;
  manifestContent = builtins.toJSON {
    developmentMode = isDev;
    repoCheckout = repoCheckout;
    fallbackConventionsDir = ../../../conventions;
    fallbackTemplatesDir = ./templates;
    archetype = terminalCfg.conventions.archetype;
    resolvedCapabilities = config.keystone.terminal.aiExtensions.resolvedCapabilities or [ ];
    publishedCommands = config.keystone.terminal.aiExtensions.publishedCommands or [ ];
    repos = attrNames (config.keystone.repos or { });
    agents = agentsWithMcp;
    consumerFlakeAgents = consumerFlakeAgents;
  };
  # Home-dir → consumer-flake directory symlinks. Each tuple is
  # `(linkRelPath, targetRelPath)`; the link is
  # `$HOME/<linkRelPath>` → `<consumerFlakeAgents>/<targetRelPath>`.
  #
  # Canonical skill tree lives at `<consumer-flake>/agents/skills/` per the
  # .agents/skills/ open standard (see docs/research/agent-skills.md). Most
  # CLI coding agents (Codex, Gemini, Copilot CLI, Cursor, Rovo Dev, Kiro,
  # OpenCode, Augment) read `~/.agents/skills/` natively. Claude Code is the
  # only holdout and gets a second symlink at `~/.claude/skills/` pointing
  # at the same target — same content, two access paths.
  toolSymlinks = [
    {
      linkRelPath = ".agents/skills";
      targetRelPath = "skills";
    }
    {
      linkRelPath = ".claude/skills";
      targetRelPath = "skills";
    }
    {
      linkRelPath = ".claude/agents";
      targetRelPath = "claude/agents";
    }
  ];
  # Render the symlink list as a properly-escaped bash array literal so we can
  # iterate safely regardless of values. Currently every component is a simple
  # identifier with no shell metacharacters or whitespace, but escapeShellArg
  # future-proofs the contract — see PR #539 review.
  toolSymlinkBashArray = concatStringsSep " " (
    map (s: lib.escapeShellArg "${s.linkRelPath}:${s.targetRelPath}") toolSymlinks
  );
  # Per-tool instruction files that symlink as individual files (not dirs)
  # from the home dir to the canonical `_shared/AGENTS.md`. Each tool reads
  # the same bytes via its native instruction-file path.
  instructionFileSymlinks = [
    {
      linkRelPath = ".claude/CLAUDE.md";
      targetRelPath = "_shared/AGENTS.md";
    }
    {
      linkRelPath = ".gemini/GEMINI.md";
      targetRelPath = "_shared/AGENTS.md";
    }
    {
      linkRelPath = ".codex/AGENTS.md";
      targetRelPath = "_shared/AGENTS.md";
    }
  ];
  instructionFileBashArray = concatStringsSep " " (
    map (f: lib.escapeShellArg "${f.linkRelPath}:${f.targetRelPath}") instructionFileSymlinks
  );
  syncScriptPath =
    if repoCheckout != null then
      "${repoCheckout}/${scriptRelPath}"
    else
      "${scriptPackage}/bin/keystone-sync-agent-assets";
in
{
  config = mkIf terminalCfg.enable (mkMerge [
    {
      home.file.${manifestRelPath}.text = manifestContent;
    }

    (devScripts.mkHomeScriptCommand {
      inherit config pkgs;
      commandName = "keystone-sync-agent-assets";
      relativePath = scriptRelPath;
      package = scriptPackage;
      runtimeInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.yq-go
      ];
    })

    # Symlink each tool's home-dir agent-asset subdir (e.g. ~/.claude/skills)
    # at the consumer flake's `agents/<tool>/<subdir>/` path. Runs for both
    # admin and OS agent users — the L1→L2 inheritance contract in
    # conventions/tool.cli-coding-agents.md rule 18. The actual *content*
    # under that path is written by `ks sync-agent-assets` (manual), not by
    # this activation. Activation never modifies file content; it only
    # ensures the symlink topology is correct.
    {
      home.activation.keystoneAgentAssetSymlinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${
          lib.makeBinPath [
            pkgs.coreutils
          ]
        }:$PATH"

        # Resolve consumer-flake agents root at runtime. Prefer the runtime
        # pointer file (survives Nix evaluation, follows the active system
        # flake) so re-evaluating with a different flake doesn't strand the
        # symlinks. The pointer is a *regular file* written by
        # modules/shared/system-flake.nix containing the path as text — not a
        # symlink — so read it with `read`, not `readlink`. Matches the Rust
        # pattern at packages/ks/src/repo.rs:131-137.
        consumer_flake=""
        if [ -f /run/current-system/keystone-system-flake ]; then
          IFS= read -r consumer_flake < /run/current-system/keystone-system-flake || consumer_flake=""
        fi
        if [ -z "$consumer_flake" ]; then
          # Fall back to the Nix-eval-time value if available.
          ${
            if consumerFlakeAgents != null then
              ''consumer_flake="${osConfig.keystone.systemFlake.path}"''
            else
              ''consumer_flake=""''
          }
        fi
        if [ -z "$consumer_flake" ]; then
          echo "keystone-agent-asset-symlinks: keystone.systemFlake.path is unset and /run/current-system/keystone-system-flake is missing; skipping symlink activation" >&2
          exit 0
        fi
        agents_root="$consumer_flake/agents"

        is_agent_user=${if isAgent then "1" else "0"}

        # Count blocker-refusals so we can fail the activation at the end.
        # A non-empty dir / regular file / other non-symlink entry at a managed
        # link site silently rots the on-disk view of agent assets if we just
        # warn — every subsequent rebuild keeps skipping. Treat it as a hard
        # failure so nixos-rebuild surfaces it. Bootstrap warnings (missing
        # target dirs / files) are NOT counted.
        refusal_count=0

        tool_symlinks=( ${toolSymlinkBashArray} )
        for entry in "''${tool_symlinks[@]}"; do
          link_rel="''${entry%%:*}"
          target_rel="''${entry#*:}"

          target="$agents_root/$target_rel"
          link="$HOME/$link_rel"

          # Admin pre-creates the consumer-flake target dir so agents (which
          # cannot write inside the admin's home) find it ready. Agents skip
          # this step and just install their symlink at their own home.
          # See convention rule 18.
          if [ "$is_agent_user" = "0" ]; then
            mkdir -p "$target"
          elif [ ! -d "$target" ]; then
            echo "keystone-agent-asset-symlinks: consumer-flake target $target does not exist yet; skipping $link (admin should run home-manager activation first)" >&2
            continue
          fi

          # Ensure the parent of the link exists (~/.claude, ~/.agents, etc.).
          mkdir -p "$(dirname "$link")"

          if [ -L "$link" ]; then
            current="$(readlink "$link")"
            if [ "$current" = "$target" ]; then
              # No-op for matching symlink, but still surface empty-dir hint below.
              :
            else
              rm -f "$link"
              ln -s "$target" "$link"
            fi
          elif [ -d "$link" ]; then
            if [ -z "$(ls -A "$link" 2>/dev/null)" ]; then
              rmdir "$link"
              ln -s "$target" "$link"
            else
              echo "keystone-agent-asset-symlinks: refusing to replace non-empty directory $link with symlink to $target" >&2
              echo "  Move or remove the existing directory, then re-run home-manager activation." >&2
              refusal_count=$((refusal_count + 1))
              continue
            fi
          elif [ -e "$link" ]; then
            echo "keystone-agent-asset-symlinks: $link exists and is not a directory or symlink; leaving untouched" >&2
            refusal_count=$((refusal_count + 1))
            continue
          else
            ln -s "$target" "$link"
          fi

          # OS agent users need traversal permission down the admin's home dir
          # chain. If `test -r` fails, the symlink itself is valid but reads
          # through it will fail with EACCES — warn explicitly so the operator
          # can fix permissions before tools surface a confusing ENOENT.
          if [ "$is_agent_user" = "1" ] && [ ! -r "$target" ]; then
            echo "keystone-agent-asset-symlinks: $target is not readable by $USER; CLI tools running as this agent will fail to read skills/agents through $link until traversal permissions are fixed on the admin's home chain" >&2
          fi

          # Empty-target hint: after this PR, ks switch no longer auto-syncs
          # content. If the admin's target dir is empty, point them at the
          # manual refresh path so they don't see empty skills/agents
          # subdirs without explanation.
          if [ "$is_agent_user" = "0" ] && [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
            echo "keystone-agent-asset-symlinks: $target is empty — run 'ks sync-agent-assets' to populate keystone-curated content" >&2
          fi
        done

        # Per-tool instruction files (CLAUDE.md, GEMINI.md, AGENTS.md) —
        # file-level symlinks. Content lives in
        # `<consumer-flake>/agents/<tool>/<filename>`, written by
        # `ks sync-agent-assets`. If the target doesn't exist yet, skip
        # with a clear warning (the user has not run sync-agent-assets).
        # Convention rules 19 and 20.
        instruction_files=( ${instructionFileBashArray} )
        for entry in "''${instruction_files[@]}"; do
          link_rel="''${entry%%:*}"
          target_rel="''${entry#*:}"

          target="$agents_root/$target_rel"
          link="$HOME/$link_rel"

          if [ ! -f "$target" ]; then
            echo "keystone-agent-asset-symlinks: instruction file $target does not exist yet; skipping $link (run 'ks sync-agent-assets' to populate)" >&2
            continue
          fi

          # Ensure parent dir of the link exists.
          mkdir -p "$(dirname "$link")"

          if [ -L "$link" ]; then
            current="$(readlink "$link")"
            if [ "$current" = "$target" ]; then
              continue
            fi
            rm -f "$link"
          elif [ -f "$link" ]; then
            # A regular file at the link site — possibly user-edited, possibly
            # a leftover from a pre-symlink generation home-manager hasn't
            # cleaned. Refuse rather than silently clobbering user content.
            echo "keystone-agent-asset-symlinks: refusing to replace regular file $link with symlink to $target" >&2
            echo "  Move or remove the file, then re-run home-manager activation." >&2
            refusal_count=$((refusal_count + 1))
            continue
          elif [ -e "$link" ]; then
            echo "keystone-agent-asset-symlinks: $link exists and is not a file or symlink; leaving untouched" >&2
            refusal_count=$((refusal_count + 1))
            continue
          fi

          ln -s "$target" "$link"
        done

        if [ "$refusal_count" -gt 0 ]; then
          if [ "$refusal_count" = 1 ]; then noun=entry; else noun=entries; fi
          echo "keystone-agent-asset-symlinks: $refusal_count blocking $noun — clear them and re-run home-manager activation" >&2
          exit 1
        fi
      '';
    }
  ]);
}
