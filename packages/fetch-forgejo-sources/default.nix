{
  lib,
  stdenv,
  makeWrapper,
  curl,
  jq,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "fetch-forgejo-sources";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/fetch-forgejo-sources $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/fetch-forgejo-sources \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          jq
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "Fetch Forgejo issues, PRs, and review comments for agent task loops";
    mainProgram = "fetch-forgejo-sources";
  };
}
