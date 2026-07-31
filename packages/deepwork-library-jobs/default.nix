{
  lib,
  runCommand,
  deepwork-src,
}:
runCommand "deepwork-library-jobs"
  {
    meta = {
      description = "DeepWork library jobs for spec-driven development";
    };
  }
  ''
    mkdir -p $out
    cp -r ${deepwork-src}/library/jobs/spec_driven_development $out/
  ''
