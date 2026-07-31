{
  lib,
  fetchzip,
  makeWrapper,
  nodejs,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "chrome-devtools-mcp";
  version = "0.20.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-tbi5cmrF1m3uI2fgHg5GgbmKhPaamn2dCeKwS8gRe6w=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;
  doInstallCheck = true;

  installPhase = ''
    runHook preInstall

    pkgDir="$out/lib/node_modules/chrome-devtools-mcp"
    mkdir -p "$pkgDir" "$out/bin"

    cp -r --no-preserve=mode,ownership LICENSE build package.json "$pkgDir"/

    makeWrapper ${nodejs}/bin/node "$out/bin/chrome-devtools-mcp" \
      --add-flags "$pkgDir/build/src/bin/chrome-devtools-mcp.js"
    makeWrapper ${nodejs}/bin/node "$out/bin/chrome-devtools" \
      --add-flags "$pkgDir/build/src/bin/chrome-devtools.js"

    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/chrome-devtools-mcp --help >/dev/null
    $out/bin/chrome-devtools --help >/dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "Chrome DevTools MCP server for browser automation";
    homepage = "https://github.com/nicolo-ribaudo/chrome-devtools-mcp";
    downloadPage = "https://www.npmjs.com/package/chrome-devtools-mcp";
    license = lib.licenses.asl20;
    mainProgram = "chrome-devtools-mcp";
  };
})
