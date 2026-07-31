{
  lib,
  stdenv,
  makeWrapper,
  coreutils,
  curl,
}:
stdenv.mkDerivation {
  pname = "podman-agent";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/podman-agent.sh $out/bin/podman-agent
    chmod +x $out/bin/podman-agent
    wrapProgram $out/bin/podman-agent \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          curl
        ]
      }
  '';

  meta = {
    description = "Run AI coding agents in Podman containers with persistent Nix store";
    mainProgram = "podman-agent";
  };
}
