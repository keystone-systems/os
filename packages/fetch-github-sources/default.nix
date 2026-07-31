{
  lib,
  stdenv,
  makeWrapper,
  gh,
  jq,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "fetch-github-sources";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/fetch-github-sources $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/fetch-github-sources \
      --prefix PATH : ${
        lib.makeBinPath [
          gh
          jq
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "Fetch GitHub issues, PRs, and review comments for agent task loops";
    mainProgram = "fetch-github-sources";
  };
}
