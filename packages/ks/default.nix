{
  lib,
  stdenv,
  craneLib,
  pkg-config,
  openssl,
  zlib,
  cmake,
  makeWrapper,
  bash,
  coreutils,
  cups,
  fzf,
  git,
  glow,
  hostname,
  nix,
  openssh,
  pandoc,
  polkit,
  sudo,
  systemd,
  python3Packages,
}:
let
  version = "0.1.0";
  pname = "ks";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./src
      ./tests
      ./Cargo.toml
      ./Cargo.lock
      ./print.css
    ];
  };

  commonArgs = {
    inherit pname version src;
    strictDeps = true;

    nativeBuildInputs = [
      pkg-config
      cmake
    ];

    buildInputs = [
      openssl
      zlib
    ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  runtimePath = lib.makeBinPath (
    [
      bash
      coreutils
      fzf
      git
      glow
      hostname
      nix
      openssh
      pandoc
      python3Packages.weasyprint
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      cups
      polkit
      sudo
      systemd
    ]
  );

  package = craneLib.buildPackage (
    commonArgs
    // {
      inherit cargoArtifacts;
      doCheck = false;

      nativeBuildInputs = commonArgs.nativeBuildInputs ++ [ makeWrapper ];

      postFixup = ''
        wrapProgram $out/bin/ks --suffix PATH : "${runtimePath}"
      '';

      meta = with lib; {
        description = "Keystone CLI/TUI for infrastructure configuration and management";
        homepage = "https://github.com/ncrmro/keystone";
        license = licenses.mit;
        maintainers = [ ];
        mainProgram = "ks";
      };
    }
  );
in
package.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests = {
      cargo-test = craneLib.cargoTest (
        commonArgs
        // {
          inherit cargoArtifacts;
          cargoTestExtraArgs = "--all-features";
          # CRITICAL: ensure_in_sync_* unit tests in cmd::update_approve
          # build real git fixtures via Command::new("git"). Without git
          # on the sandbox PATH the tests panic at fixture setup, not at
          # the assertion they're meant to exercise.
          nativeCheckInputs = [ git ];
        }
      );
      cargo-clippy = craneLib.cargoClippy (
        commonArgs
        // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "--all-targets --all-features -- --deny warnings";
        }
      );
      cargo-fmt = craneLib.cargoFmt { inherit (commonArgs) pname version src; };
    };
  };
})
