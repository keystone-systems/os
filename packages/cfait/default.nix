{
  lib,
  craneLib,
  fetchFromGitHub,
}:
let
  pname = "cfait";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "trougnouf";
    repo = "cfait";
    rev = "v${version}";
    hash = "sha256-N5OjvYXAgDcaYklgbjZxZv0eS6toIZ/Gd0E+CynFLOU=";
  };

  commonArgs = {
    inherit src pname version;

    # Only build the TUI binary (default feature), skip GUI and mobile
    cargoExtraArgs = "--no-default-features --features tui";
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Tests require system TLS certificates unavailable in the Nix sandbox
    doCheck = false;

    meta = with lib; {
      description = "Powerful, fast and elegant CalDAV task/TODO manager (TUI)";
      homepage = "https://github.com/trougnouf/cfait";
      license = licenses.gpl3Only;
      maintainers = [ ];
      mainProgram = "cfait";
    };
  }
)
