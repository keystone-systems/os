{ pkgs }:
pkgs.runCommand "virtual-machine-unit"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export VIRTUAL_MACHINE_SCRIPT=${../../bin/virtual-machine}
    python ${./test_virtual_machine.py} -v
    touch "$out"
  ''
