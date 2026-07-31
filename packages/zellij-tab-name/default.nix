{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation rec {
  pname = "zellij-tab-name";
  version = "0.4.2";

  src = fetchurl {
    url = "https://github.com/Cynary/zellij-tab-name/releases/download/v${version}/zellij-tab-name.wasm";
    hash = "sha256-Tt9rrMAKL+d6xGTIaXXHzHf5y/1JTDb9wrgbIm4p4OY=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 "$src" "$out/share/zellij/plugins/zellij-tab-name.wasm"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Zellij plugin for renaming the tab containing a given pane";
    homepage = "https://github.com/Cynary/zellij-tab-name";
    license = licenses.bsd3;
    platforms = platforms.all;
  };
}
