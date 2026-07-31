# Overlay that provides keystone packages.
# Receives flake inputs as arguments so that paths and flake references resolve
# correctly when a consumer flake applies the overlay.
{
  self,
  crane,
  himalaya,
  calendula,
  cardamum,
  comodoro,
  llm-agents,
  browser-previews,
  ghostty,
  yazi,
  agenix,
  deepwork,
  grafana-mcp-src,
  lfs-s3-src,
}:
let
  # Paths must be captured in `let` BEFORE the overlay function, otherwise they
  # get evaluated in the wrong context when the overlay is applied by a consumer flake
  zesh-src = ../packages/zesh;
  agent-coding-agent-src = ../packages/agent-coding-agent;
  agent-mail-src = ../packages/agent-mail;
  fetch-email-source-src = ../packages/fetch-email-source;
  fetch-forgejo-sources-src = ../packages/fetch-forgejo-sources;
  forgejo-cli-ex-src = ../packages/forgejo-cli-ex;
  forgejo-project-src = ../packages/forgejo-project;
  fetch-github-sources-src = ../packages/fetch-github-sources;
  repo-sync-src = ../packages/repo-sync;
  podman-agent-src = ../packages/podman-agent;
  cfait-src = ../packages/cfait;
  zide-src = ../packages/zide;
  zellij-tab-name-src = ../packages/zellij-tab-name;
  hyprpolkitagent-src = ../packages/hyprpolkitagent;
  write-polkit-theme-src = ../packages/write-polkit-theme;
  agents-e2e-src = ../packages/agents-e2e;
  ks-src = ../packages/ks;
  chrome-devtools-mcp-src = ../packages/chrome-devtools-mcp;
  grafana-mcp-pkg-src = ../packages/grafana-mcp;
  lfs-s3-pkg-src = ../packages/lfs-s3;
  deepwork-library-jobs-src = ../packages/deepwork-library-jobs;
  keystone-deepwork-jobs-src = ../packages/keystone-deepwork-jobs;
  keystone-conventions-src = ../packages/keystone-conventions;
  slidev-src = ../packages/slidev;
  himalaya-flake = himalaya;
  calendula-flake = calendula;
  cardamum-flake = cardamum;
  comodoro-flake = comodoro;
  browser-previews-flake = browser-previews;
  ghostty-flake = ghostty;
  yazi-flake = yazi;
  agenix-flake = agenix;
  deepwork-flake = deepwork;
in
final: prev:
let
  system = final.stdenv.hostPlatform.system;
in
{
  # Expose crane library for Rust package builds — auto-resolved by callPackage
  craneLib = crane.mkLib final;

  keystone = {
    zesh = final.callPackage zesh-src { };
    agent-coding-agent = final.callPackage agent-coding-agent-src { };
    agent-mail = final.callPackage agent-mail-src { himalaya = final.keystone.himalaya; };
    fetch-email-source = final.callPackage fetch-email-source-src {
      himalaya = final.keystone.himalaya;
    };
    fetch-forgejo-sources = final.callPackage fetch-forgejo-sources-src { };
    forgejo-cli-ex = final.callPackage forgejo-cli-ex-src { };
    forgejo-project = final.callPackage forgejo-project-src { };
    fetch-github-sources = final.callPackage fetch-github-sources-src { };
    repo-sync = final.callPackage repo-sync-src { };
    podman-agent = final.callPackage podman-agent-src { };
    agents-e2e = final.callPackage agents-e2e-src { };
    ks = final.callPackage ks-src { };
    cfait = final.callPackage cfait-src { };
    zide = final.callPackage zide-src { };
    zellij-tab-name = final.callPackage zellij-tab-name-src { };
    hyprpolkitagent = final.callPackage hyprpolkitagent-src { };
    write-polkit-theme = final.callPackage write-polkit-theme-src { };
    himalaya = himalaya-flake.packages.${system}.default;
    calendula = calendula-flake.packages.${system}.default;
    cardamum = cardamum-flake.packages.${system}.default;
    # Comodoro upstream flake is missing dbus from buildInputs/nativeBuildInputs.
    # The postInstall phase runs the binary (to generate completions) before
    # fixup patches RPATH, so we also set LD_LIBRARY_PATH during install.
    comodoro = comodoro-flake.packages.${system}.default.overrideAttrs (
      old:
      let
        libPath = final.lib.makeLibraryPath [ final.dbus ];
      in
      {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.pkg-config
          final.makeWrapper
        ];
        buildInputs = (old.buildInputs or [ ]) ++ [ final.dbus ];
        postInstall = ''
          export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ''
        + (old.postInstall or "")
        + ''
          wrapProgram $out/bin/comodoro --prefix LD_LIBRARY_PATH : "${libPath}"
        '';
      }
    );
    # Consume llm-agents' own flake outputs rather than re-importing source.
    # llm-agents owns the package's nixpkgs alignment, helper plumbing
    # (wrapBuddy, versionCheckHomeHook, buildNpmPackage), and Rust vendor
    # hashes — keeping those downstream caused recurring drift every time
    # a Cargo.lock moved upstream.
    claude-code = llm-agents.packages.${system}.claude-code;
    gemini-cli = llm-agents.packages.${system}.gemini-cli;
    codex = llm-agents.packages.${system}.codex;
    opencode = llm-agents.packages.${system}.opencode;
    # Browsers from browser-previews
    google-chrome = browser-previews-flake.packages.${system}.google-chrome;
    # Desktop tools from flake inputs
    yazi = yazi-flake.packages.${system}.default;
    agenix = agenix-flake.packages.${system}.default;
    deepwork = deepwork-flake.packages.${system}.default;
    deepwork-library-jobs = final.callPackage deepwork-library-jobs-src {
      deepwork-src = deepwork-flake;
    };
    keystone-deepwork-jobs = final.callPackage keystone-deepwork-jobs-src {
      keystone-src = self;
    };
    keystone-conventions = final.callPackage keystone-conventions-src {
      keystone-src = self;
    };
    chrome-devtools-mcp = final.callPackage chrome-devtools-mcp-src { };
    grafana-mcp = final.callPackage grafana-mcp-pkg-src {
      inherit grafana-mcp-src;
    };
    lfs-s3 = final.callPackage lfs-s3-pkg-src {
      inherit lfs-s3-src;
    };
    slidev = final.callPackage slidev-src { };
  }
  // final.lib.optionalAttrs final.stdenv.isLinux {
    # ghostty only has .default for Linux systems
    ghostty = ghostty-flake.packages.${system}.default;
  };
  # Top-level overrides so programs.ghostty/yazi use flake versions
  yazi = yazi-flake.packages.${system}.default;
}
// prev.lib.optionalAttrs prev.stdenv.isLinux {
  ghostty = ghostty-flake.packages.${prev.stdenv.hostPlatform.system}.default;
}
