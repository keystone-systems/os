{
  lib,
  runCommand,
  keystone-src,
}:
runCommand "keystone-conventions"
  {
    meta = with lib; {
      description = "Keystone project conventions and configuration templates";
      license = licenses.mit;
    };
  }
  ''
    mkdir -p $out
    cp -r ${keystone-src}/conventions/* $out/
  ''
