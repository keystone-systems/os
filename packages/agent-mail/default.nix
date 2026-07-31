{
  lib,
  stdenv,
  makeWrapper,
  himalaya,
  coreutils,
  jq,
}:
stdenv.mkDerivation {
  pname = "agent-mail";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin $out/share/agent-mail/templates
    cp $src/bin/agent-mail $out/bin/
    cp $src/templates/*.md $out/share/agent-mail/templates/
    chmod +x $out/bin/*

    wrapProgram $out/bin/agent-mail \
      --prefix PATH : ${
        lib.makeBinPath [
          himalaya
          jq
          coreutils
        ]
      } \
      --set AGENT_MAIL_TEMPLATES "$out/share/agent-mail/templates"
  '';

  meta = with lib; {
    description = "Send structured email templates to OS agents";
    mainProgram = "agent-mail";
  };
}
