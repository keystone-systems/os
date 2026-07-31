{ lib }:
let
  checkoutCandidates =
    homeDir: repoEntry:
    let
      parts = lib.splitString "/" repoEntry;
      repoName = lib.last parts;
    in
    [
      "${homeDir}/repos/${repoEntry}"
      "${homeDir}/repos/${lib.head parts}/${repoName}"
      "${homeDir}/repos/${lib.head parts}/ks-config/../${repoName}"
      "${homeDir}/repos/${lib.head parts}/ks-config/${repoName}"
      "${homeDir}/.keystone/repos/${repoEntry}"
    ];

  resolveRepoCheckout =
    config: repoFlakeInput:
    let
      repos = config.keystone.repos or { };
      homeDir = config.home.homeDirectory;
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
    in
    if (config.keystone.development or false) && repoEntry != null then
      lib.head (checkoutCandidates homeDir repoEntry)
    else
      null;

  # NixOS system-level counterpart to resolveRepoCheckout.
  # Derives the live checkout path from keystone.os.users to locate the home directory.
  # Returns null when development mode is off or the repo is not registered.
  resolveNixOSRepoCheckout =
    config: repoFlakeInput:
    let
      repos = config.keystone.repos or { };
      keystoneUsers = config.keystone.os.users or { };
      userNames = lib.attrNames keystoneUsers;
      mainUserName = if userNames != [ ] then lib.head userNames else null;
      homeDir = if mainUserName != null then "/home/${mainUserName}" else null;
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
    in
    if (config.keystone.development or false) && repoEntry != null && homeDir != null then
      lib.head (checkoutCandidates homeDir repoEntry)
    else
      null;

  mkHomeRepoFile =
    {
      config,
      targetPath,
      relativePath,
      sourcePath,
      repoFlakeInput ? "keystone",
      executable ? null,
    }:
    let
      repoCheckout = resolveRepoCheckout config repoFlakeInput;
      fileValue =
        if repoCheckout != null then
          {
            source = config.lib.file.mkOutOfStoreSymlink "${repoCheckout}/${relativePath}";
          }
        else
          {
            source = sourcePath;
          };
    in
    {
      home.file.${targetPath} =
        fileValue // lib.optionalAttrs (executable != null) { inherit executable; };
    };

  mkHomeRepoFiles =
    {
      config,
      files,
      repoFlakeInput ? "keystone",
    }:
    lib.mkMerge (
      map (
        file:
        mkHomeRepoFile (
          {
            inherit config;
            repoFlakeInput = file.repoFlakeInput or repoFlakeInput;
          }
          // file
        )
      ) files
    );
in
{
  inherit
    resolveRepoCheckout
    resolveNixOSRepoCheckout
    mkHomeRepoFile
    mkHomeRepoFiles
    ;

  mkHomeScriptCommand =
    {
      config,
      pkgs,
      commandName,
      relativePath,
      package,
      runtimeInputs ? [ ],
      extraEnvSetup ? "",
      repoFlakeInput ? "keystone",
    }:
    let
      repoCheckout = resolveRepoCheckout config repoFlakeInput;
      repos = config.keystone.repos or { };
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
      candidateScripts = lib.optionals (repoEntry != null) (
        map (candidate: "${candidate}/${relativePath}") (
          checkoutCandidates config.home.homeDirectory repoEntry
        )
      );
      candidateScriptArray = lib.concatStringsSep " " (map lib.escapeShellArg candidateScripts);
      runtimePath = lib.makeBinPath runtimeInputs;
      commandWrapper = pkgs.writeShellScript "hm_${commandName}.sh" ''
        export PATH="${runtimePath}:$PATH"
        ${extraEnvSetup}
        for live_script in ${candidateScriptArray}; do
          if [ -f "$live_script" ]; then
            exec ${pkgs.bash}/bin/bash "$live_script" "$@"
          fi
        done

        exec "${package}/bin/${commandName}" "$@"
      '';
    in
    lib.mkMerge [
      (lib.mkIf (repoCheckout == null) {
        home.packages = [ package ];
      })
      (lib.mkIf (repoCheckout != null) {
        home.file.".local/bin/${commandName}" = {
          source = commandWrapper;
          executable = true;
        };
      })
    ];

  # NixOS system-level counterpart to mkHomeScriptCommand.
  # Returns a derivation suitable for environment.systemPackages that execs the
  # script from the live checkout in dev mode, or the Nix store copy in production.
  #
  # Arguments:
  #   config        — NixOS module config
  #   pkgs          — nixpkgs
  #   commandName   — name of the resulting binary
  #   relativePath  — path relative to the repo root (e.g. "modules/os/agents/scripts/agentctl.sh")
  #   nixStorePath  — Nix path literal for the store copy (e.g. ./scripts/agentctl.sh)
  #   extraEnvSetup — optional shell lines to export env vars before exec (default "")
  #   repoFlakeInput — flake input name to resolve (default "keystone")
  mkSystemScriptPackage =
    {
      config,
      pkgs,
      commandName,
      relativePath,
      nixStorePath,
      runtimeInputs ? [ ],
      extraEnvSetup ? "",
      repoFlakeInput ? "keystone",
    }:
    let
      liveCheckout = resolveNixOSRepoCheckout config repoFlakeInput;
      repos = config.keystone.repos or { };
      keystoneUsers = config.keystone.os.users or { };
      userNames = lib.attrNames keystoneUsers;
      mainUserName = if userNames != [ ] then lib.head userNames else null;
      homeDir = if mainUserName != null then "/home/${mainUserName}" else null;
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
      candidateScripts =
        if homeDir != null && repoEntry != null then
          map (candidate: "${candidate}/${relativePath}") (checkoutCandidates homeDir repoEntry)
        else
          [ ];
      candidateScriptArray = lib.concatStringsSep " " (map lib.escapeShellArg candidateScripts);
      runtimePath = lib.makeBinPath runtimeInputs;
    in
    pkgs.writeShellScriptBin commandName ''
      export PATH="${runtimePath}:$PATH"
      ${extraEnvSetup}
      ${lib.optionalString (liveCheckout != null) ''
        for live_script in ${candidateScriptArray}; do
          if [ -f "$live_script" ]; then
            exec ${pkgs.bash}/bin/bash "$live_script" "$@"
          fi
        done
      ''}

      exec ${pkgs.bash}/bin/bash "${nixStorePath}" "$@"
    '';
}
