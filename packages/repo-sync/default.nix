{
  lib,
  writeShellApplication,
  git,
  coreutils,
  findutils,
  openssh,
}:
writeShellApplication {
  name = "repo-sync";
  runtimeInputs = [
    git
    coreutils
    findutils
    openssh
  ];
  text = builtins.readFile ./repo-sync.sh;
  meta = with lib; {
    description = "Clone-if-absent, fetch/commit/rebase/push sync for git repos (REQ-009)";
    license = licenses.mit;
    mainProgram = "repo-sync";
  };
}
