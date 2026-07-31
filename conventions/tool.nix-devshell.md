# Nix dev shells

All repos use `flake.nix` with a dev shell providing project dependencies. Run commands via `nix develop -c <cmd>` or from a direnv-activated shell (`.envrc` with `use flake`; run `direnv allow` before first use). To add a missing tool, add it to `devShells.default.buildInputs` in `flake.nix`. Never run `playwright install` — the devshell provides browsers via `playwright-driver.browsers`; pin `@playwright/test` to match `nix eval --raw nixpkgs#playwright-driver.version`.
