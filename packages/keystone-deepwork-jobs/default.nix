{
  lib,
  runCommand,
  keystone-src,
}:
# Published keystone-native DeepWork jobs.
#
# Only `.deepwork/jobs/` is packaged. The sibling `.deepwork/jobs-internal/`
# directory is intentionally excluded — it holds keystone-development-only
# workflows (contributor authoring tools, in-progress stubs) that are only
# reachable in dev mode via the local checkout path appended to
# DEEPWORK_ADDITIONAL_JOBS_FOLDERS (see modules/terminal/deepwork.nix).
#
# Runtime jobs that adopter-installed code invokes (e.g. `task_loop`, called by
# `modules/os/agents/scripts/task-loop.sh`) MUST stay in `.deepwork/jobs/` so
# they reach adopter hosts via this derivation.
runCommand "keystone-deepwork-jobs"
  {
    meta = with lib; {
      description = "Keystone repository DeepWork workflow jobs (published only)";
      license = licenses.mit;
    };
  }
  ''
    mkdir -p $out
    if [ -d ${keystone-src}/.deepwork/jobs ] && [ "$(ls -A ${keystone-src}/.deepwork/jobs 2>/dev/null)" ]; then
      for d in ${keystone-src}/.deepwork/jobs/*/; do
        [ -d "$d" ] && cp -r "$d" $out/
      done
    fi
  ''
