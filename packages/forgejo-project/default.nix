{
  lib,
  stdenv,
  makeWrapper,
  curl,
  jq,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "forgejo-project";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/forgejo-project $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/forgejo-project \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          jq
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "Forgejo project board management CLI via web routes";
    mainProgram = "forgejo-project";
  };
}
