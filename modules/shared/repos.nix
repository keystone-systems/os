# Keystone Repos & Development Mode
#
# Implements REQ-018.3: managed repo registry with auto-population from flake inputs.
#
# keystone.repos declares managed repositories keyed by owner/repo.
# keystone.development enables local checkout path resolution across all modules.
#
# Repos are auto-populated from flake inputs passed via keystone._repoInputs.
# Only inputs with discoverable source URLs (github, git) are registered.
# Auto-derived entries use mkDefault priority so consumers can override.
#
{
  lib,
  config,
  options,
  ...
}:
with lib;
let
  cfg = config.keystone;
  inputs = cfg._repoInputs;
  # No explicit entry for the keystone input: it is now an ssh:// git input for
  # ks.systems/os, which mkRepoEntry derives correctly as "ks.systems/os". The
  # entry that used to live here still named ncrmro/keystone on GitHub -- the
  # pre-migration home -- and being explicit made it outrank derivation, so
  # every consumer registered a repo that no longer exists there.
  explicitRepos = {
    # Explicit entry required: the desktop input's sourceInfo carries no
    # owner/repo (especially under ks-dev path overrides), so auto-derivation
    # would register a bare "desktop" repo and dev symlinks would dangle at
    # ~/repos/desktop instead of ~/repos/ks.systems/desktop.
    "ks.systems/desktop" = {
      url = "https://git.ncrmro.com/ks.systems/desktop.git";
      flakeInput = "desktop";
      branch = "main";
    };
  };
  explicitFlakeInputs = listToAttrs (
    mapAttrsToList (key: value: {
      name = value.flakeInput;
      value = key;
    }) (filterAttrs (_: value: value.flakeInput != null) explicitRepos)
  );

  # Whether we are running inside a Home Manager module that has access to NixOS config
  osConfig =
    if config ? osConfig then
      config.osConfig
    else if options ? osConfig && options.osConfig ? value then
      options.osConfig.value
    else
      null;

  # Derive a repo entry from a flake input's sourceInfo.
  # Returns null for inputs without a discoverable git URL.
  # Handles github (owner/repo) and git (direct URL) input types.
  mkRepoEntry =
    name: input:
    let
      # Safe access to sourceInfo to avoid context-related evaluation errors
      si = if builtins.isAttrs input && input ? sourceInfo then input.sourceInfo else { };
      type = si.type or "path";
    in
    if type == "github" && si ? owner && si ? repo then
      {
        name = "${si.owner}/${si.repo}";
        value = {
          url = "https://github.com/${si.owner}/${si.repo}.git";
          flakeInput = name;
          branch = "main";
        };
      }
    else if (type == "git" || type == "path") then
      let
        # Try to extract owner/repo from URL if available.
        # Avoid using si.path directly if it's a store path to prevent evaluation errors.
        url = si.url or "";

        # Clean URL of protocols and prefixes
        # Note: replaceStrings replaces all occurrences of each string in the first list with the corresponding string in the second list.
        cleanUrl =
          replaceStrings
            [ "git+" "file://" "https://" "ssh://" "git@github.com:" ]
            [
              ""
              ""
              ""
              ""
              ""
            ]
            url;
        # Split and take last two parts
        parts = filter (s: s != "") (splitString "/" cleanUrl);
        len = length parts;
        repo = if len >= 1 then removeSuffix ".git" (last parts) else null;
        owner = if len >= 2 then elemAt parts (len - 2) else null;

        # Special case: under a ks-dev path override the keystone input is a
        # store path with no owner/repo to recover, so fall back to its real
        # home. This was ncrmro/keystone before the forge migration.
        defaultOwnerRepo = if name == "keystone" then "ks.systems/os" else name;

        derivedName = if owner != null && repo != null then "${owner}/${repo}" else defaultOwnerRepo;
      in
      {
        name = derivedName;
        value = {
          inherit url;
          flakeInput = name;
          branch = "main";
        };
      }
    else
      null;

  autoEntries = filter (
    e: e != null && !(builtins.hasAttr (e.value.flakeInput or "") explicitFlakeInputs)
  ) (mapAttrsToList mkRepoEntry inputs);
  autoRepos = listToAttrs autoEntries;
in
{
  options.keystone = {
    development = mkOption {
      type = types.bool;
      default = if osConfig != null then osConfig.keystone.development or false else false;
      description = ''
        Enable development mode globally. When true, modules use local repo
        checkouts at ~/repos/OWNER/REPO/ instead of Nix store copies.
        Requires keystone.repos to declare managed repositories.

        This defaults to false per process.enable-by-default exception rule 17 —
        development mode requires local repo checkouts to function.
      '';
    };

    _repoInputs = mkOption {
      type = types.attrs;
      default = { };
      internal = true;
      description = "Flake inputs for auto-deriving keystone.repos entries. Only inputs with discoverable source URLs are registered.";
    };

    repos = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            url = mkOption {
              type = types.str;
              description = "Git remote URL";
            };
            flakeInput = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Corresponding flake input name for --override-input in dev mode.";
            };
            branch = mkOption {
              type = types.str;
              default = "main";
              description = "Default branch for pull/push";
            };
          };
        }
      );
      default = if osConfig != null then osConfig.keystone.repos or { } else { };
      description = "Managed repositories keyed by owner/repo. Cloned to ~/repos/{owner}/{repo}/.";
    };
  };

  config.keystone.repos = mapAttrs (_: v: mkDefault v) (autoRepos // explicitRepos);
}
