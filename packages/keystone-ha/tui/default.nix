{
  lib,
  craneLib,
  pkg-config,
  openssl,
}:
let
  src = craneLib.cleanCargoSource ./..;

  commonArgs = {
    inherit src;
    pname = "keystone-ha-tui-client";
    version = "0.1.0";

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Build only the tui crate from the workspace
    cargoExtraArgs = "-p keystone-ha-tui-client";

    meta = with lib; {
      description = "TUI client for Keystone cross-realm resource management";
      homepage = "https://github.com/ncrmro/keystone";
      license = licenses.mit;
      maintainers = [ ];
      mainProgram = "keystone-ha-tui";
    };
  }
)
