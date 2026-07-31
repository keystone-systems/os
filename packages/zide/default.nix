{
  bash,
  bc,
  coreutils,
  lazygit,
  lib,
  makeWrapper,
  stdenvNoCC,
  yazi,
  zellij,
}:
stdenvNoCC.mkDerivation {
  pname = "keystone-zide";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/layouts" "$out/yazi" "$out/lf"
    install -Dm755 bin/* -t "$out/bin/"
    cp -r layouts/* "$out/layouts/"
    cp -r yazi/* "$out/yazi/"
    cp -r lf/* "$out/lf/"

    patchShebangs "$out/bin"

    for command in "$out"/bin/*; do
      wrapProgram "$command" \
        --suffix PATH : "${
          lib.makeBinPath [
            bash
            bc
            coreutils
            lazygit
            yazi
            zellij
          ]
        }"
    done

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/zide" --help >/dev/null
    "$out/bin/zide-pick" --help >/dev/null
    "$out/bin/zide-edit" --help >/dev/null
    "$out/bin/zide-rename" --help >/dev/null
    test -f "$out/layouts/default.kdl"
    grep -F 'zide-pick' "$out/layouts/default.kdl" >/dev/null

    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Keystone Zellij IDE layout helpers";
    license = licenses.mit;
    mainProgram = "zide";
    platforms = platforms.unix;
  };
}
