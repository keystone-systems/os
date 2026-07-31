{
  lib,
  stdenv,
  makeWrapper,
  git,
  gh,
  openssh,
  jq,
  forgejo-cli,
}:
stdenv.mkDerivation {
  pname = "agent-coding-agent";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/agent.coding-agent $out/bin/
    cp $src/agent.coding-agent.claude $out/bin/
    cp $src/agent.coding-agent.codex $out/bin/
    cp $src/agent.coding-agent.gemini $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/agent.coding-agent \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          gh
          openssh
          jq
          forgejo-cli
        ]
      }
  '';

  meta = with lib; {
    description = "Orchestrates coding tasks: branch, invoke subagent, push, PR, review";
    mainProgram = "agent.coding-agent";
  };
}
