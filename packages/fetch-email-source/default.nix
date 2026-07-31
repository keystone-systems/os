{
  lib,
  stdenv,
  makeWrapper,
  himalaya,
  jq,
}:
stdenv.mkDerivation {
  pname = "fetch-email-source";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/fetch-email-source $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/fetch-email-source \
      --prefix PATH : ${
        lib.makeBinPath [
          himalaya
          jq
        ]
      }
  '';

  meta = with lib; {
    description = "Fetch email envelopes and enrich with message bodies via himalaya";
    mainProgram = "fetch-email-source";
  };
}
