{
  lib,
  craneLib,
  fetchCrate,
  openssl,
  pkg-config,
}:
let
  pname = "forgejo-cli-ex";
  version = "0.1.9";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-tyf3LHor7q/XfYR110dL6mMUvuiKL6hPnHO9ompqYg8=";
  };

  commonArgs = {
    inherit src pname version;

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Upstream integration tests expect Docker and network access.
    doCheck = false;

    meta = with lib; {
      description = "Forgejo CLI extension using UI endpoints for Actions operations";
      homepage = "https://github.com/JKamsker/forgejo-cli-ex";
      license = licenses.lgpl3Plus;
      maintainers = [ ];
      mainProgram = "fj-ex";
    };
  }
)
