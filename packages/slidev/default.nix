{
  lib,
  buildNpmPackage,
  fetchzip,
}:
buildNpmPackage (finalAttrs: {
  pname = "slidev";
  version = "52.14.1";

  src = fetchzip {
    url = "https://registry.npmjs.org/@slidev/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha256-EGTCVqv2rQ8gocwCHej2G7e5U1iL+YP9tVNctikPhwA=";
  };

  npmDepsHash = "sha256-1dw289xyqdLAtl9HtZHSry0mDBATQlZrvOR/d7kvhQg=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  dontNpmBuild = true;

  meta = {
    description = "Presentation slides for developers, powered by Markdown and Vue";
    homepage = "https://sli.dev";
    downloadPage = "https://www.npmjs.com/package/@slidev/cli";
    license = lib.licenses.mit;
    mainProgram = "slidev";
  };
})
