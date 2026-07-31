{
  lib,
  bun,
  writeShellScriptBin,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./src
      ./package.json
      ./tsconfig.json
    ];
  };
in
writeShellScriptBin "agents-e2e" ''
  exec ${bun}/bin/bun run ${src}/src/main.ts "$@"
''
