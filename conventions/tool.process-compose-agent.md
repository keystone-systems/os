# Process compose

In `process-compose.yaml`, assign ports dynamically using the `env_cmds` block (e.g., `DB_PORT: "shuf -i 10000-60000 -n 1"`). Reference these variables with `$${VAR}` (double-dollar) in process commands and environment — single `${VAR}` resolves at parse time and produces empty values. Set `PC_NO_SERVER=1` in the `environment` block unless the API server is needed; when it is, use `--use-uds` for Unix domain socket instead of TCP. Never launch the TUI — use the CLI with `-o json`. Read logs with `--tail N --log-no-color`, never `-f`.
