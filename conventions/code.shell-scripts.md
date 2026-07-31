<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Shell Scripts (code.shell-scripts)

Standards for authoring fault-tolerant, succinct shell scripts within keystone and related repositories. These rules apply to standalone `.sh` files, inline scripts in Nix builders (`writeShellApplication`, `writeShellScriptBin`), and extracted scripts used with `replaceVars`.

## Execution Environment

1. All bash scripts MUST begin with `set -euo pipefail` immediately after the shebang or at the top of the script body.
2. Standalone scripts MUST use `#!/usr/bin/env bash` rather than hardcoded paths like `#!/bin/bash`.
3. Scripts packaged via `writeShellApplication` MUST NOT include a shebang — the builder adds it automatically.
4. When a section of code intentionally handles failure (e.g., capturing exit codes), `set +e` or `set +o pipefail` MAY be used locally and MUST be re-enabled immediately after.

## Static Analysis

5. All scripts MUST pass ShellCheck with zero warnings or errors.
6. If a ShellCheck rule must be bypassed, it SHALL be disabled inline with a comment citing the rule and a justification.
7. SC2155 (declare and assign separately): `local` declarations MUST be split from command-substitution assignments to avoid masking exit codes.

```bash
# Correct — SC2155 compliant
local dir
dir=$(git rev-parse --show-toplevel 2>/dev/null || true)

# Wrong — masks the exit code of the subshell
local dir=$(git rev-parse --show-toplevel)
```

## Lifecycle and Cleanup

8. Scripts that create temporary files, directories, or lock files MUST register a `trap` on `EXIT` to ensure cleanup regardless of exit path.
9. Temporary directories MUST be created with `mktemp -d` and removed in the trap handler.
10. Lock files SHOULD use `mkdir` for atomic acquisition — `mkdir` is race-free unlike file-based locks.

```bash
WORK_DIR=$(mktemp -d)
cleanup() {
    local exit_code=$?
    rm -rf "${WORK_DIR}"
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM
```

## Quoting and Variable Expansion

11. All variable expansions MUST be double-quoted: `"$var"`, `"${var}"`, `"${array[@]}"`.
12. Default values MUST use parameter expansion: `"${VAR:-default}"` for fallback, `"${VAR:?message}"` for required parameters.
13. Scripts MUST prefer `[[ ]]` over `[ ]` or `test` — double brackets prevent word splitting and enable regex matching.
14. Command substitution MUST use `$(command)` — backticks SHALL NOT be used.

## Function Discipline

15. All variables declared within a function MUST use the `local` keyword.
16. Functions SHOULD return meaningful exit codes — `0` for success, non-zero for specific failure modes.
17. Error messages MUST be written to stderr: `echo "Error: ..." >&2`.

## Argument Handling

18. Scripts with flags MUST use a `while [[ $# -gt 0 ]]; do case ... esac; done` loop for argument parsing.
19. Unknown arguments MUST be rejected with an error message and non-zero exit, not silently ignored.
20. When forwarding arguments to subcommands, scripts SHOULD collect remaining args in an array and re-set positional parameters with `set -- "${REMAINING[@]}"`.

## Directory Context

21. When changing directories, scripts MUST use short-circuit failure: `cd /path || exit 1`.
22. For temporary directory changes, `pushd`/`popd` SHOULD be used with output suppressed: `pushd /tmp >/dev/null || exit 1`.

## Nix Packaging

For general Nix packaging conventions, see `tool.nix`. For dev shell dependency management, see `tool.nix-devshell`.

23. New keystone CLI scripts MUST be packaged with `writeShellApplication` — it provides automatic shebang, `set -euo pipefail`, and declarative `runtimeInputs` for PATH management.
24. `writeShellScriptBin` SHOULD only be used when the script body is generated from Nix expressions (e.g., case statements built from attrsets).
25. Scripts that require build-time values (tool paths, generated code, configuration) MUST use `replaceVars` with the `@placeholder@` pattern — not string interpolation in Nix.
26. Placeholders in `replaceVars` scripts MUST use the format `@descriptiveName@` and MUST be documented with a comment at the top of the script listing all placeholders and their sources.
27. Runtime dependencies MUST be declared in `runtimeInputs` (for `writeShellApplication`) or injected via `replaceVars` absolute paths — scripts MUST NOT assume tools are globally installed.
28. User-facing repo-backed `.sh` entrypoints SHOULD live as standalone files instead of inline Nix strings so development mode can link them directly into `PATH`.
29. When development mode links a standalone script from the repo checkout, the script file itself MUST remain directly executable.
30. Repo-backed scripts that use `@placeholder@` build-time substitution MUST provide a development-mode fallback for any non-executable asset path they need at runtime (for example CSS, templates, or config fragments). The packaged script sees substituted absolute paths; the live checkout script does not.
31. The preferred development-mode fallback is to resolve assets relative to the script file itself (for example via `BASH_SOURCE[0]`) and fail clearly if the adjacent asset is missing.

```nix
# writeShellApplication — preferred for CLI tools
pkgs.writeShellApplication {
  name = "my-tool";
  runtimeInputs = with pkgs; [ git jq curl ];
  text = builtins.readFile ./my-tool.sh;
}

# replaceVars — for build-time substitution
pkgs.replaceVars ./scripts/my-script.sh {
  python3 = "${pkgs.python3}/bin/python3";
  configPath = "/etc/my-config";
}
```

## Logging

32. Scripts that run as services or in automation SHOULD use structured logging with timestamps: `echo "[$(date '+%H:%M:%S')] $*"`.
33. Log files SHOULD use ISO date filenames: `$(date +%Y-%m-%d_%H%M%S).log`.
34. Long-running scripts MAY use `tee -a "$LOG_FILE"` to write to both stdout and a log file simultaneously.

## Golden Example

A keystone utility script following all rules — packaged via `writeShellApplication`, using strict mode, ShellCheck-clean, with proper cleanup, argument parsing, and error handling:

```bash
# Placeholders (injected via replaceVars):
#   @configDir@ — path to configuration directory

set -euo pipefail

WORK_DIR=$(mktemp -d)
cleanup() {
    local exit_code=$?
    rm -rf "${WORK_DIR}"
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

# --- Argument parsing ---

TARGET=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        -h|--help) echo "Usage: my-tool --target <name> [--verbose]"; exit 0 ;;
        *) echo "Error: unknown argument '$1'" >&2; exit 1 ;;
    esac
done

if [[ -z "${TARGET}" ]]; then
    echo "Error: --target is required" >&2
    exit 1
fi

# --- Main logic ---

log() {
    if [[ "${VERBOSE}" == true ]]; then
        echo "[$(date '+%H:%M:%S')] $*"
    fi
}

process_target() {
    local name="$1"
    local config_file
    config_file="@configDir@/${name}.yaml"

    if [[ ! -f "${config_file}" ]]; then
        echo "Error: config not found for '${name}'" >&2
        return 1
    fi

    log "Processing ${name} from ${config_file}"
    # ... implementation ...
}

process_target "${TARGET}"
```
