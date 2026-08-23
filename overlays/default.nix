# Overlay that provides keystone packages.
# Receives flake inputs as arguments so that paths and flake references resolve
# correctly when a consumer flake applies the overlay.
{
  self,
  crane,
  browser-previews,
  ghostty,
  yazi,
  lfs-s3-src,
}:
let
  # Paths must be captured in `let` BEFORE the overlay function, otherwise they
  # get evaluated in the wrong context when the overlay is applied by a consumer flake
  repo-sync-src = ../packages/repo-sync;
  zellij-tab-name-src = ../packages/zellij-tab-name;
  agents-e2e-src = ../packages/agents-e2e;
  ks-src = ../packages/ks;
  lfs-s3-pkg-src = ../packages/lfs-s3;
  slidev-src = ../packages/slidev;
  browser-previews-flake = browser-previews;
  ghostty-flake = ghostty;
  yazi-flake = yazi;
in
final: prev:
let
  system = final.stdenv.hostPlatform.system;
in
{
  # Expose crane library for Rust package builds — auto-resolved by callPackage
  craneLib = crane.mkLib final;

  keystone = {
    repo-sync = final.callPackage repo-sync-src { };
    agents-e2e = final.callPackage agents-e2e-src { };
    ks = final.callPackage ks-src { };
    zellij-tab-name = final.callPackage zellij-tab-name-src { };
    # hyprpolkitagent and write-polkit-theme moved to ks.systems/desktop;
    # flake.nix's alias overlay re-exports them as pkgs.keystone.* from
    # final.keystone-desktop.* for name stability.
    # Browsers from browser-previews
    google-chrome = browser-previews-flake.packages.${system}.google-chrome;
    # Desktop tools from flake inputs
    yazi = yazi-flake.packages.${system}.default;
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
